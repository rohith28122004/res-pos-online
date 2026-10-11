import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../app_info.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../protocol/protocol.dart';
import '../security/permissions.dart';
import '../security/secret_store.dart';
import '../sync/host_outbox.dart';
import 'command_dispatcher.dart';
import 'host_api.dart';
import 'host_keys.dart';

/// What the POS shows on its Cloud connection screen.
class CloudStatus {
  const CloudStatus({
    this.enrolled = false,
    this.socketConnected = false,
    this.lastUploadAt,
    this.ackedThrough,
    this.pendingEvents = 0,
    this.lastError,
  });

  final bool enrolled;
  final bool socketConnected;
  final int? lastUploadAt;
  final int? ackedThrough;
  final int pendingEvents;

  /// Plain-language problem, if any (e.g. "Content mismatch at #120").
  final String? lastError;

  CloudStatus copyWith({
    bool? enrolled,
    bool? socketConnected,
    int? lastUploadAt,
    int? ackedThrough,
    int? pendingEvents,
    String? lastError,
    bool clearError = false,
  }) => CloudStatus(
    enrolled: enrolled ?? this.enrolled,
    socketConnected: socketConnected ?? this.socketConnected,
    lastUploadAt: lastUploadAt ?? this.lastUploadAt,
    ackedThrough: ackedThrough ?? this.ackedThrough,
    pendingEvents: pendingEvents ?? this.pendingEvents,
    lastError: clearError ? null : (lastError ?? this.lastError),
  );
}

class CloudHttpException implements Exception {
  const CloudHttpException(this.status, this.error);
  final int status;
  final ProtocolException error;
  @override
  String toString() => 'HTTP $status ${error.code}: ${error.message}';
}

/// The POS host's link to the Cloudflare relay (docs/PROTOCOL.md §8):
/// enrollment, at-least-once ordered upload of the event outbox, and the relay
/// socket that brings phone commands to [HostApi]. The cloud never decides
/// anything; it only stores, forwards and reports.
class CloudConnector {
  CloudConnector({required this.api, required this.secrets, HttpClient? http, Random? random})
    : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 10)),
      _random = random ?? Random();

  final HostApi api;
  final SecretStore secrets;
  final HttpClient _http;
  final Random _random;

  static const batchEvents = 500;
  static const batchBytes = 900 * 1024;
  static const _timeout = Duration(seconds: 20);

  AppDatabase get _db => api.ctx.db;

  final _status = StreamController<CloudStatus>.broadcast();
  CloudStatus _current = const CloudStatus();
  Stream<CloudStatus> get status => _status.stream;
  CloudStatus get currentStatus => _current;

  bool _running = false;
  WebSocket? _socket;
  Timer? _uploadTimer;
  Timer? _reconnect;
  int _reconnectAttempts = 0;
  StreamSubscription<Object?>? _outboxSub;
  Future<void>? _uploading;
  bool _uploadAgain = false;
  final _pending = <Future<void>>{};

  void _set(CloudStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  /// Only https, except for a local development Worker on this machine.
  static Uri parseCloudUrl(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.host.isEmpty) throw const ValidationException('Enter the cloud address, like https://…');
    final local = uri.host == 'localhost' || uri.host == '127.0.0.1';
    if (uri.scheme != 'https' && !(local && uri.scheme == 'http')) {
      throw const ValidationException('The cloud address must start with https://');
    }
    return uri.replace(path: '', query: null, fragment: null);
  }

  Future<String?> _credential(HostIdentityRow id) => HostKeys.readCloudCredential(id.hostDeviceId, secrets);

  // ---- Enrollment ------------------------------------------------------------------

  /// Registers this POS with the cloud using a single-use enrollment code
  /// from the operator. The cloud keeps the restaurant ID the POS already
  /// uses with its phones.
  Future<void> enroll(Actor actor, {required String cloudUrl, required String enrollmentCode}) async {
    actor.require(Permission.manageDevices);
    final base = parseCloudUrl(cloudUrl);
    final id = await api.identity();
    if (id.cloudUrl != null) throw const ConflictException('This POS is already connected to the cloud');
    final settings = await api.ctx.settings();
    final Map<String, Object?> r;
    try {
      r = await _request(
        base,
        'POST',
        '/v1/enroll',
        body: {
          'enrollmentCode': enrollmentCode.trim(),
          'restaurantId': id.restaurantId,
          'restaurantName': settings.name,
          'hostDeviceId': id.hostDeviceId,
          'hostSigningPublicKey': id.signingPublicKey,
          'hostSealPublicKey': id.sealPublicKey,
          'appVersion': AppInfo.version,
        },
      );
    } on CloudHttpException catch (e) {
      throw ConflictException(e.error.message);
    } on Object {
      throw const ConflictException('Could not reach the cloud. Check the address and the internet connection.');
    }
    if (r['restaurantId'] != id.restaurantId) {
      throw const ConflictException('The cloud answered for a different restaurant; nothing was changed');
    }
    await HostKeys.writeCloudCredential(id.hostDeviceId, secrets, r['hostCredential']! as String);
    final now = api.ctx.nowMs();
    await _db.transaction(() async {
      await (_db.update(_db.hostIdentity)..where((h) => h.singleton.equals(1))).write(
        HostIdentityCompanion(cloudUrl: Value(base.toString()), cloudEnrolledAt: Value(now), updatedAt: Value(now)),
      );
      await api.ctx.audit(actor, 'connected.cloud_enrolled', details: {'cloud': base.host});
    });
    await backfill();
    _set(_current.copyWith(enrolled: true, clearError: true));
  }

  /// Puts everything the cloud needs but may never have seen into the outbox:
  /// devices paired before enrollment and the full financial history. Safe to
  /// repeat (the cloud upserts by row id).
  Future<void> backfill() async {
    final outbox = api.ctx.outbox;
    Future<void> each<T>(Future<List<T>> Function() rows, Future<void> Function(T row) emit) async {
      final list = await rows();
      for (var i = 0; i < list.length; i += 200) {
        await _db.transaction(() async {
          for (final r in list.skip(i).take(200)) {
            await emit(r);
          }
        });
      }
    }

    await each(() => _db.select(_db.pairedDevices).get(), (d) async {
      await outbox.emit(
        type: EventType.devicePaired,
        aggregateType: 'device',
        aggregateId: d.id,
        payload: {
          'deviceId': d.id,
          'role': d.role,
          'name': d.name,
          'credentialHash': d.credentialHash,
          'pairedAt': d.createdAt,
        },
      );
      if (d.revokedAt != null) {
        await outbox.emit(
          type: EventType.deviceRevoked,
          aggregateType: 'device',
          aggregateId: d.id,
          payload: {'deviceId': d.id, 'revokedAt': d.revokedAt},
        );
      }
    });
    await each(
      () => (_db.select(_db.shifts)..orderBy([(s) => OrderingTerm(expression: s.openedAt)])).get(),
      (s) => outbox.changed(Aggregate.shift, s.id),
    );
    await each(
      () => (_db.select(_db.bills)..orderBy([(b) => OrderingTerm(expression: b.createdAt)])).get(),
      (b) => outbox.changed(Aggregate.bill, b.id),
    );
    await each(
      () => (_db.select(_db.refunds)..orderBy([(r) => OrderingTerm(expression: r.createdAt)])).get(),
      (r) => outbox.changed(Aggregate.refund, r.id),
    );
    await each(
      () => (_db.select(_db.expenses)..orderBy([(e) => OrderingTerm(expression: e.createdAt)])).get(),
      (e) => outbox.changed(Aggregate.expense, e.id),
    );
    await each(
      () => (_db.select(_db.cashMovements)..orderBy([(m) => OrderingTerm(expression: m.createdAt)])).get(),
      (m) => outbox.changed(Aggregate.cashMovement, m.id),
    );
    await each(
      () => (_db.select(_db.orders)..where((o) => o.status.equals('cancelled'))).get(),
      (o) => outbox.changed(Aggregate.order, o.id),
    );
  }

  // ---- Running ------------------------------------------------------------------------

  Future<void> start() async {
    if (_running) return;
    final id = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (id?.cloudUrl == null) return;
    _running = true;
    _set(_current.copyWith(enrolled: true));
    _outboxSub = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.hostEvents, limitUpdateKind: UpdateKind.insert))
        .listen((_) => _bg(uploadNow));
    _uploadTimer = Timer.periodic(const Duration(seconds: 30), (_) => _bg(uploadNow));
    _bg(uploadNow);
    _bg(_connect);
  }

  Future<void> stop() async {
    _running = false;
    _uploadTimer?.cancel();
    _reconnect?.cancel();
    await _outboxSub?.cancel();
    _outboxSub = null;
    await _socket?.close(1000, 'POS stopping');
    _socket = null;
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
    _set(_current.copyWith(socketConnected: false));
  }

  Future<void> dispose() async {
    await stop();
    _http.close(force: true);
    await _status.close();
  }

  void _bg(Future<void> Function() task) {
    late final Future<void> f;
    f = task().catchError((Object _) {}).whenComplete(() => _pending.remove(f));
    _pending.add(f);
  }

  // ---- Upload -----------------------------------------------------------------------------

  /// Uploads outbox events the cloud has not acknowledged, in order. Callers
  /// arriving while an upload runs wait for it (it runs once more for them).
  Future<void> uploadNow() {
    final running = _uploading;
    if (running != null) {
      _uploadAgain = true;
      return running;
    }
    final run = () async {
      try {
        do {
          _uploadAgain = false;
          await _uploadOnce();
        } while (_uploadAgain && _running);
      } finally {
        _uploading = null;
      }
    }();
    _uploading = run;
    return run;
  }

  Future<void> _uploadOnce() async {
    final id = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (id == null || id.cloudUrl == null || id.reconcileRequired) return;
    final credential = await _credential(id);
    if (credential == null) {
      _set(_current.copyWith(lastError: 'The cloud credential is missing on this PC. Connect to the cloud again.'));
      return;
    }
    final base = Uri.parse(id.cloudUrl!);
    try {
      final state = await _request(base, 'GET', '/v1/host/sync-state', credential: credential);
      final epochs = [for (final e in state['epochs']! as List) (e! as Map).cast<String, Object?>()];
      final mine = epochs.where((e) => e['epoch'] == id.hostEpoch).firstOrNull;
      int next;
      if (mine == null) {
        if (id.hostEpoch > 1) {
          await _request(
            base,
            'POST',
            '/v1/host/epoch',
            credential: credential,
            body: {
              'epoch': id.hostEpoch,
              'startSequence': id.epochStartSequence,
              'reason': 'restore',
            },
          );
          next = id.epochStartSequence;
        } else {
          // Epoch 1 opens with the first batch, from the oldest event kept.
          final first = _db.hostEvents.sequence.min();
          final q = _db.selectOnly(_db.hostEvents)
            ..addColumns([first])
            ..where(_db.hostEvents.hostEpoch.equals(1));
          next = (await q.getSingle()).read(first) ?? 1;
        }
      } else {
        next = mine['nextSequence']! as int;
      }
      await _markAcked(id.hostEpoch, next - 1);
      for (var guard = 0; guard < 1000; guard++) {
        final rows =
            await (_db.select(_db.hostEvents)
                  ..where((e) => e.hostEpoch.equals(id.hostEpoch) & e.sequence.isBiggerOrEqualValue(next))
                  ..orderBy([(e) => OrderingTerm(expression: e.sequence)])
                  ..limit(batchEvents))
                .get();
        if (rows.isEmpty) break;
        if (rows.first.sequence != next) {
          _set(
            _current.copyWith(
              lastError: 'Events from #$next onwards are no longer on this POS. Contact support before continuing.',
            ),
          );
          return;
        }
        final batch = <Object?>[];
        var bytes = 0;
        for (final r in rows) {
          if (batch.isNotEmpty && bytes + r.eventJson.length > batchBytes) break;
          batch.add(jsonDecode(r.eventJson));
          bytes += r.eventJson.length;
        }
        try {
          final ack = await _request(
            base,
            'POST',
            '/v1/host/events',
            credential: credential,
            body: {
              'hostEpoch': id.hostEpoch,
              'events': batch,
            },
          );
          final through = (ack['ackedThrough'] as Map?)?['sequence'] as int? ?? (next + batch.length - 1);
          await _markAcked(id.hostEpoch, through);
          next = through + 1;
          _set(_current.copyWith(lastUploadAt: api.ctx.nowMs(), ackedThrough: through, clearError: true));
        } on CloudHttpException catch (e) {
          if (e.error.code == 'GAP') {
            next = (e.error.details?['expectedNext'] as int?) ?? next;
            continue;
          }
          rethrow;
        }
      }
      _set(_current.copyWith(pendingEvents: await _pendingCount(id.hostEpoch)));
    } on CloudHttpException catch (e) {
      _set(
        _current.copyWith(
          lastError: e.error.code == 'CONTENT_MISMATCH'
              ? 'The cloud holds different data for an event this POS sent. Uploads are paused; contact support.'
              : e.error.message,
        ),
      );
    } on Object {
      _set(_current.copyWith(pendingEvents: await _pendingCount(id.hostEpoch)));
    }
  }

  Future<void> _markAcked(int epoch, int through) async {
    if (through < 1) return;
    await (_db.update(_db.hostEvents)..where(
          (e) => e.hostEpoch.equals(epoch) & e.sequence.isSmallerOrEqualValue(through) & e.cloudAckedAt.isNull(),
        ))
        .write(HostEventsCompanion(cloudAckedAt: Value(api.ctx.nowMs())));
    final now = api.ctx.nowMs();
    await _db
        .into(_db.syncCheckpoints)
        .insertOnConflictUpdate(
          SyncCheckpointsCompanion.insert(
            name: 'cloud_upload',
            hostEpoch: epoch,
            sequence: through,
            updatedAt: now,
            lastSuccessAt: Value(now),
          ),
        );
  }

  Future<int> _pendingCount(int epoch) async {
    final c = countAll();
    final q = _db.selectOnly(_db.hostEvents)
      ..addColumns([c])
      ..where(_db.hostEvents.hostEpoch.equals(epoch) & _db.hostEvents.cloudAckedAt.isNull());
    return (await q.getSingle()).read(c) ?? 0;
  }

  // ---- Relay socket -----------------------------------------------------------------------

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectAttempts++;
    final cap = min(60000, 1000 * (1 << min(_reconnectAttempts, 6)));
    _reconnect?.cancel();
    _reconnect = Timer(Duration(milliseconds: 500 + _random.nextInt(cap)), () => _bg(_connect));
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final id = await api.identity();
      final credential = await _credential(id);
      if (id.cloudUrl == null || credential == null) return;
      final base = Uri.parse(id.cloudUrl!);
      final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/v1/host/socket');
      final ws = await WebSocket.connect(
        uri.toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer $credential'},
        customClient: _http,
      ).timeout(_timeout);
      ws.pingInterval = const Duration(seconds: 30);
      _socket = ws;
      _reconnectAttempts = 0;
      _set(_current.copyWith(socketConnected: true));
      ws.listen(
        (m) => _bg(() => _onMessage(ws, m)),
        onDone: () {
          if (identical(_socket, ws)) _socket = null;
          _set(_current.copyWith(socketConnected: false));
          _scheduleReconnect();
        },
        onError: (Object _) {},
        cancelOnError: false,
      );
    } on Object {
      _set(_current.copyWith(socketConnected: false));
      _scheduleReconnect();
    }
  }

  Future<void> _onMessage(WebSocket ws, Object? raw) async {
    if (raw is! String) return;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (json is! Map) return;
    final m = json.cast<String, Object?>();
    switch (m['t']) {
      case 'command':
        final reply = await handleRelayedCommand(m);
        ws.add(jsonEncode({'t': 'result', 'result': reply}));
      case 'request':
        final (status, body) = await handleRelayedRequest(m);
        ws.add(jsonEncode({'t': 'response', 'requestId': m['requestId'], 'status': status, 'body': body}));
      case 'ping':
        ws.add('{"t":"pong"}');
    }
  }

  /// A phone command forwarded by the cloud. Business outcomes come from the
  /// dispatcher (stored, idempotent); authentication and epoch problems are
  /// answered as rejected results the cloud does not keep as final.
  Future<Map<String, Object?>> handleRelayedCommand(Map<String, Object?> m) async {
    final command = m['command'];
    final commandId = command is Map ? command['commandId'] as String? : null;
    try {
      final (_, caller) = await api.authenticateRelayed(m['deviceId']! as String, m['sessionToken'] as String?);
      if (caller == null) throw const ProtocolException(ErrorCode.unauthenticated, 'Sign in first');
      return (await api.command(caller, command)).toJson();
    } on ProtocolException catch (e) {
      final id = await api.identity().then((i) => i.hostEpoch, onError: (Object _) => 0);
      return CommandResult(
        commandId: commandId ?? 'unknown',
        state: ResultState.rejected,
        hostEpoch: id,
        error: e,
      ).toJson();
    } on Object {
      return CommandResult(
        commandId: commandId ?? 'unknown',
        state: ResultState.rejected,
        hostEpoch: 0,
        error: const ProtocolException(ErrorCode.internal, 'The POS could not complete this request'),
      ).toJson();
    }
  }

  /// A relayed request (`sealed_auth`, `snapshot`, `command_lookup`): returns
  /// the HTTP status and body the phone would get on the LAN.
  Future<(int, Object?)> handleRelayedRequest(Map<String, Object?> m) async {
    try {
      final deviceId = m['deviceId']! as String;
      final body = (m['body'] as Map?)?.cast<String, Object?>() ?? const {};
      switch (m['kind']) {
        case 'sealed_auth':
          final (device, _) = await api.authenticateRelayed(deviceId, null);
          return (200, await api.sealed(device, body['sealed'], clientKey: 'cloud:$deviceId'));
        case 'snapshot':
          final caller = await _caller(deviceId, m['sessionToken'] as String?);
          return (200, await api.snapshot(caller, body['scope'] as String?));
        case 'command_lookup':
          final caller = await _caller(deviceId, m['sessionToken'] as String?);
          return (200, (await api.lookup(caller, requireId(body, 'commandId'))).toJson());
      }
      throw const ProtocolException(ErrorCode.notFound, 'Unknown request');
    } on ProtocolException catch (e) {
      return (ErrorCode.httpStatus(e.code), {'error': e.toJson()});
    } on Object {
      return (
        500,
        {'error': const ProtocolException(ErrorCode.internal, 'The POS could not complete this request').toJson()},
      );
    }
  }

  Future<RemoteCaller> _caller(String deviceId, String? token) async {
    final (_, caller) = await api.authenticateRelayed(deviceId, token);
    if (caller == null) throw const ProtocolException(ErrorCode.unauthenticated, 'Sign in first');
    return caller;
  }

  // ---- HTTP -------------------------------------------------------------------------------

  Future<Map<String, Object?>> _request(
    Uri base,
    String method,
    String path, {
    Object? body,
    String? credential,
  }) async {
    final req = await _http.openUrl(method, base.replace(path: path)).timeout(_timeout);
    if (credential != null) req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $credential');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final res = await req.close().timeout(_timeout);
    final text = await utf8.decoder.bind(res).join().timeout(_timeout);
    final Object? json = text.isEmpty ? null : jsonDecode(text);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return json is Map ? json.cast<String, Object?>() : const {};
    }
    final err = json is Map && json['error'] is Map
        ? ProtocolException.fromJson((json['error']! as Map).cast<String, Object?>())
        : ProtocolException(ErrorCode.internal, 'Cloud answered HTTP ${res.statusCode}');
    throw CloudHttpException(res.statusCode, err);
  }
}
