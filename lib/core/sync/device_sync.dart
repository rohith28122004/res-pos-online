import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../features/devices/application/device_service.dart' show PairingPayload;
import '../errors/app_exception.dart';
import '../network/lan_client.dart';
import '../protocol/canonical_json.dart';
import '../protocol/protocol.dart';
import '../protocol/sealed.dart';
import '../security/secret_store.dart';
import '../time/business_time.dart';
import 'client_database.dart';
import 'host_route.dart';

/// States of a command on the phone (shown to the user).
abstract final class CommandState {
  static const queued = 'queued'; // saved on the phone, waiting for the POS
  static const sending = 'sending';
  static const relayed = 'relayed'; // the cloud holds it; the POS has not answered
  static const accepted = 'accepted';
  static const rejected = 'rejected';
  static const needsReview = 'needs_review'; // never sent automatically again
  static const discarded = 'discarded';

  static const open = {queued, sending, relayed};
}

/// Connection summary for the banner.
class LinkStatus {
  const LinkStatus({
    this.route,
    this.live = false,
    this.lastLiveAt,
    this.problem,
    this.hostConnectedToCloud,
  });

  /// 'lan', 'cloud' or null (neither reachable).
  final String? route;

  /// Receiving live updates right now.
  final bool live;
  final int? lastLiveAt;

  /// signInRequired, deviceRevoked, wrongCertificate, updateRequired,
  /// hostRestored — or null.
  final String? problem;
  final bool? hostConnectedToCloud;

  LinkStatus copyWith({String? route, bool? live, int? lastLiveAt, String? problem, bool clearProblem = false}) =>
      LinkStatus(
        route: route ?? this.route,
        live: live ?? this.live,
        lastLiveAt: lastLiveAt ?? this.lastLiveAt,
        problem: clearProblem ? null : (problem ?? this.problem),
        hostConnectedToCloud: hostConnectedToCloud,
      );
}

/// The phone side of CaféDesk Online: pairing, sign-in, the cached view of the
/// POS (snapshot + event cursor), the durable command queue and kitchen
/// alarms. The POS host decides everything; this only stores, sends and shows.
class DeviceSync {
  DeviceSync({
    required this.db,
    required this.secrets,
    required this.clock,
    LanClient Function(List<String> addresses, int port, String certSha256)? lanClientFactory,
    this.cloudRouteFactory,
    Random? random,
  }) : _lanClientFactory = lanClientFactory ?? ((a, p, f) => LanClient(addresses: a, port: p, certSha256: f)),
       _random = random ?? Random();

  final ClientDatabase db;
  final SecretStore secrets;
  final Clock clock;
  final LanClient Function(List<String>, int, String) _lanClientFactory;
  final HostRoute Function(ClientLinkRow link)? cloudRouteFactory;
  final Random _random;

  static const commandExpiry = Duration(minutes: 30);
  static const maxBackoff = Duration(seconds: 60);
  static const _uuid = Uuid();

  final _status = StreamController<LinkStatus>.broadcast();
  final _alarms = StreamController<Map<String, Object?>>.broadcast();
  LinkStatus _current = const LinkStatus();

  HostRoute? _lan;
  HostRoute? _cloud;
  bool _running = false;
  StreamSubscription<LiveMessage>? _liveSub;
  Timer? _reconnect;
  Timer? _deliverTimer;
  int _reconnectAttempts = 0;
  Future<void>? _deliverRun;
  bool _disposed = false;
  final _pending = <Future<void>>{};
  bool _deliverAgain = false;

  Stream<LinkStatus> get status => _status.stream;
  LinkStatus get currentStatus => _current;

  /// New kitchen tickets (TicketView), once each.
  Stream<Map<String, Object?>> get alarms => _alarms.stream;

  int _now() => clock.nowUtc().millisecondsSinceEpoch;

  void _setStatus(LinkStatus s) {
    _current = s;
    if (!_status.isClosed) _status.add(s);
  }

  // ---- Pairing -------------------------------------------------------------------

  Future<ClientLinkRow?> link() => db.select(db.clientLink).getSingleOrNull();

  static String _credentialKey(String deviceId) => 'cafedesk-online/device/$deviceId/credential';
  static String _sessionKey(String deviceId) => 'cafedesk-online/device/$deviceId/session';

  /// Pairs this phone with a POS using the text of its pairing QR code.
  Future<ClientLinkRow> pair(
    String pairingText, {
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    if (await link() != null) throw const ConflictException('This phone is already paired. Unpair it first.');
    final p = PairingPayload.parse(pairingText);
    if (p.expiresAt <= _now()) {
      throw const ValidationException('This pairing code has expired. Show a new one on the POS.');
    }
    final client = _lanClientFactory(p.addresses, p.port, p.certSha256);
    final Map<String, Object?> r;
    try {
      r = await client.request(
        'POST',
        '/v1/pair',
        body: {
          'protocolVersion': ProtocolVersion.current,
          'pairingCode': p.code,
          'deviceName': deviceName,
          'platform': ?platform,
          'appVersion': ?appVersion,
        },
      );
    } on RouteUnavailable {
      client.close();
      throw const ConflictException(
        'Could not reach the POS. Connect this phone to the café Wi-Fi and make sure the POS is open with '
        'device connections on.',
      );
    } on ProtocolException catch (e) {
      client.close();
      throw ConflictException(e.message);
    }
    client.close();
    if (r['restaurantId'] != p.restaurantId || r['hostDeviceId'] != p.hostDeviceId || r['role'] != p.role) {
      throw const ConflictException('The POS answered with different details than its pairing code. Try again.');
    }
    final deviceId = r['deviceId']! as String;
    await secrets.write(_credentialKey(deviceId), r['deviceCredential']! as String);
    final now = _now();
    await db
        .into(db.clientLink)
        .insert(
          ClientLinkCompanion.insert(
            singleton: const Value(1),
            deviceId: deviceId,
            role: p.role,
            deviceName: deviceName,
            restaurantId: p.restaurantId,
            restaurantName: (r['restaurantName'] as String?) ?? p.restaurantName,
            hostDeviceId: p.hostDeviceId,
            hostEpoch: r['hostEpoch']! as int,
            hostAddressesJson: jsonEncode(p.addresses),
            hostPort: p.port,
            certSha256: p.certSha256,
            signingPublicKey: r['hostSigningPublicKey']! as String,
            sealPublicKey: r['hostSealPublicKey']! as String,
            cloudUrl: Value(r['cloudUrl'] as String?),
            pairedAt: now,
          ),
        );
    return (await link())!;
  }

  /// Forgets the pairing and everything cached or queued on this phone.
  Future<void> unpair() async {
    await stop();
    final l = await link();
    if (l != null) {
      await secrets.delete(_credentialKey(l.deviceId));
      await secrets.delete(_sessionKey(l.deviceId));
    }
    await db.transaction(() async {
      await db.delete(db.clientLink).go();
      await db.delete(db.clientSessions).go();
      await db.delete(db.pendingCommands).go();
      await db.delete(db.drafts).go();
      await db.delete(db.cacheEntries).go();
      await db.delete(db.ticketAlerts).go();
    });
    _setStatus(const LinkStatus());
  }

  HostRoute _lanRoute(ClientLinkRow l) => _lan ??= LanRoute(
    _lanClientFactory((jsonDecode(l.hostAddressesJson) as List).cast<String>(), l.hostPort, l.certSha256),
  );

  HostRoute? _cloudRoute(ClientLinkRow l) {
    final factory = cloudRouteFactory;
    if (l.cloudUrl == null || factory == null) return null;
    return _cloud ??= factory(l);
  }

  List<HostRoute> _routes(ClientLinkRow l) => [_lanRoute(l), ?_cloudRoute(l)];

  Future<RouteAuth> _auth(ClientLinkRow l, {bool session = true}) async {
    final credential = await secrets.read(_credentialKey(l.deviceId));
    if (credential == null) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This phone lost its pairing. Pair it again.');
    }
    final token = session ? await secrets.read(_sessionKey(l.deviceId)) : null;
    if (session && token == null) throw const ProtocolException(ErrorCode.unauthenticated, 'Sign in first');
    return RouteAuth(deviceCredential: credential, sessionToken: token);
  }

  /// Tries LAN first, then the cloud relay. Returns the first answer.
  Future<T> _viaRoutes<T>(ClientLinkRow l, Future<T> Function(HostRoute r) call) async {
    RouteUnavailable? last;
    for (final r in _routes(l)) {
      try {
        final v = await call(r);
        if (_current.route != r.name) _setStatus(_current.copyWith(route: r.name));
        return v;
      } on RouteUnavailable catch (e) {
        last = e;
      }
    }
    _setStatus(LinkStatus(lastLiveAt: _current.lastLiveAt, problem: _current.problem));
    throw last ?? const RouteUnavailable('The POS is not reachable');
  }

  // ---- Staff sign-in ------------------------------------------------------------------

  Future<ClientSessionRow?> session() => db.select(db.clientSessions).getSingleOrNull();

  Stream<ClientSessionRow?> watchSession() => db.select(db.clientSessions).watchSingleOrNull();

  Future<ClientSessionRow> signIn(String email, String password) async {
    final l = await link();
    if (l == null) throw const ConflictException('Pair this phone with the POS first');
    final auth = await _auth(l, session: false);
    final box = await Sealed.seal(
      {'kind': 'sign_in', 'email': email.trim(), 'password': password, 'requestId': _uuid.v4()},
      hostSealPublicKey: b64urlDecode(l.sealPublicKey),
      deviceId: l.deviceId,
    );
    final Map<String, Object?> r;
    try {
      r = await _viaRoutes(l, (route) => route.sealed(box, auth));
    } on RouteUnavailable {
      throw const ConflictException('The POS is not reachable. Sign in when it is.');
    } on ProtocolException catch (e) {
      _noteProblem(e);
      throw ConflictException(e.message);
    }
    final staff = (r['staff']! as Map).cast<String, Object?>();
    await secrets.write(_sessionKey(l.deviceId), r['sessionToken']! as String);
    await db
        .into(db.clientSessions)
        .insertOnConflictUpdate(
          ClientSessionsCompanion.insert(
            singleton: const Value(1),
            staffId: staff['staffId']! as String,
            name: staff['name']! as String,
            role: staff['role']! as String,
            expiresAt: r['expiresAt']! as int,
          ),
        );
    _setStatus(_current.copyWith(clearProblem: true));
    _bg(deliverNow);
    return (await session())!;
  }

  /// Signs out on this phone. Drafts and unsent commands stay with their
  /// owner and are not sent while someone else is signed in.
  Future<void> signOut() async {
    final l = await link();
    if (l != null) {
      try {
        final auth = await _auth(l);
        await _viaRoutes(l, (r) => r.signOut(auth));
      } on Object {
        // Offline: the token expires on its own; it is deleted here anyway.
      }
      await secrets.delete(_sessionKey(l.deviceId));
    }
    await db.delete(db.clientSessions).go();
  }

  /// Owner approval typed on this phone (sealed to the POS). Returns a
  /// single-use approval id for the next command.
  Future<String> requestApproval(String email, String password, String purpose) async {
    final l = (await link())!;
    final auth = await _auth(l, session: false);
    final box = await Sealed.seal(
      {'kind': 'approve', 'email': email.trim(), 'password': password, 'purpose': purpose, 'requestId': _uuid.v4()},
      hostSealPublicKey: b64urlDecode(l.sealPublicKey),
      deviceId: l.deviceId,
    );
    try {
      final r = await _viaRoutes(l, (route) => route.sealed(box, auth));
      return r['approvalId']! as String;
    } on RouteUnavailable {
      throw const ConflictException('The POS is not reachable. Ask again when it is.');
    } on ProtocolException catch (e) {
      throw ConflictException(e.message);
    }
  }

  void _noteProblem(ProtocolException e) {
    final problem = switch (e.code) {
      ErrorCode.sessionExpired || ErrorCode.unauthenticated || ErrorCode.staffDisabled => 'signInRequired',
      ErrorCode.deviceRevoked => 'deviceRevoked',
      wrongCertificate => 'wrongCertificate',
      ErrorCode.updateRequired => 'updateRequired',
      ErrorCode.epochChanged => 'hostRestored',
      _ => null,
    };
    if (problem != null) _setStatus(_current.copyWith(problem: problem));
  }

  // ---- Cached view ----------------------------------------------------------------------

  Stream<List<CacheEntryRow>> watchCache() => db.select(db.cacheEntries).watch();

  /// Loads a full snapshot and resets the cursor to it.
  Future<void> refresh() async {
    final l = (await link())!;
    final auth = await _auth(l);
    final scope = l.role == 'kitchen' ? 'kitchen' : 'waiter';
    final snap = await _viaRoutes(l, (r) => r.snapshot(scope, auth));
    await _applySnapshot(l, snap);
  }

  Future<void> _applySnapshot(ClientLinkRow l, Map<String, Object?> snap) async {
    final now = _now();
    final epoch = snap['hostEpoch']! as int;
    await db.transaction(() async {
      await db.delete(db.cacheEntries).go();
      Future<void> put(String key, String kind, Object? value) => db
          .into(db.cacheEntries)
          .insertOnConflictUpdate(
            CacheEntriesCompanion.insert(key: key, kind: kind, json: jsonEncode(value), updatedAt: now),
          );
      await put('meta', 'meta', {
        'restaurantName': snap['restaurantName'],
        'generatedAt': snap['generatedAt'],
        'hostEpoch': epoch,
      });
      if (snap['menu'] != null) await put('menu', 'menu', snap['menu']);
      if (snap['tables'] != null) await put('tables', 'tables', snap['tables']);
      for (final o in (snap['orders'] as List?) ?? const []) {
        final m = (o! as Map).cast<String, Object?>();
        await put('order:${m['orderId']}', 'order', m);
      }
      for (final t in (snap['tickets'] as List?) ?? const []) {
        final m = (t! as Map).cast<String, Object?>();
        await put('ticket:${m['ticketId']}', 'ticket', m);
        // First load: tickets already on the board are recorded silently.
        // After an outage: tickets created while away still sound once.
        final known = await (db.select(
          db.ticketAlerts,
        )..where((a) => a.ticketId.equals(m['ticketId']! as String))).getSingleOrNull();
        if (known == null) {
          final createdAt = m['createdAt']! as int;
          final sound = l.lastLiveAt != null && createdAt > l.lastLiveAt! && m['status'] == 'pending';
          await db
              .into(db.ticketAlerts)
              .insert(TicketAlertsCompanion.insert(ticketId: m['ticketId']! as String, alertedAt: now, sounded: sound));
          if (sound) _alarms.add(m);
        }
      }
      await (db.update(db.clientLink)..where((x) => x.singleton.equals(1))).write(
        ClientLinkCompanion(
          hostEpoch: Value(epoch),
          cursorEpoch: Value(epoch),
          cursorSequence: Value(snap['cursor']! as int),
          lastLiveAt: Value(now),
        ),
      );
    });
    if (epoch != l.hostEpoch) await _hostEpochChanged(epoch);
    _setStatus(_current.copyWith(lastLiveAt: now));
  }

  /// Applies events after the cursor; ignores old or duplicate ones. Returns
  /// false if a snapshot is needed instead (epoch change).
  Future<bool> applyEvents(int epoch, List<Map<String, Object?>> events, int through) async {
    final l = (await link())!;
    if (epoch != l.cursorEpoch) return false;
    var refetch = false;
    final now = _now();
    final fresh = <Map<String, Object?>>[];
    await db.transaction(() async {
      var cursor = l.cursorSequence;
      for (final e in events) {
        final seq = e['sequence']! as int;
        if (e['hostEpoch'] != epoch || seq <= cursor) continue;
        final payload = (e['payload']! as Map).cast<String, Object?>();
        switch (e['type']) {
          case EventType.orderUpdated:
            await db
                .into(db.cacheEntries)
                .insertOnConflictUpdate(
                  CacheEntriesCompanion.insert(
                    key: 'order:${payload['orderId']}',
                    kind: 'order',
                    json: jsonEncode(payload),
                    updatedAt: now,
                  ),
                );
          case EventType.ticketUpdated:
            await db
                .into(db.cacheEntries)
                .insertOnConflictUpdate(
                  CacheEntriesCompanion.insert(
                    key: 'ticket:${payload['ticketId']}',
                    kind: 'ticket',
                    json: jsonEncode(payload),
                    updatedAt: now,
                  ),
                );
            if (l.role == 'kitchen') {
              final id = payload['ticketId']! as String;
              final known = await (db.select(db.ticketAlerts)..where((a) => a.ticketId.equals(id))).getSingleOrNull();
              if (known == null) {
                await db
                    .into(db.ticketAlerts)
                    .insert(TicketAlertsCompanion.insert(ticketId: id, alertedAt: now, sounded: true));
                fresh.add(payload);
              }
            }
          case EventType.menuChanged || EventType.tablesChanged:
            refetch = true;
        }
        cursor = seq;
      }
      if (through > cursor) cursor = through;
      await (db.update(db.clientLink)..where((x) => x.singleton.equals(1))).write(
        ClientLinkCompanion(cursorSequence: Value(cursor), lastLiveAt: Value(now)),
      );
    });
    for (final t in fresh) {
      _alarms.add(t);
    }
    _setStatus(_current.copyWith(lastLiveAt: now));
    if (refetch) _bg(refresh);
    return true;
  }

  /// Pulls events after the cursor once (used after a command was accepted and
  /// when the live channel is down).
  Future<void> catchUp() async {
    final l = (await link())!;
    final auth = await _auth(l);
    for (var i = 0; i < 20; i++) {
      final cur = (await link())!;
      final page = await _viaRoutes(cur, (r) => r.events(cur.cursorEpoch, cur.cursorSequence, auth));
      if (page['snapshotRequired'] == true) {
        await refresh();
        return;
      }
      final events = [for (final e in page['events']! as List) (e! as Map).cast<String, Object?>()];
      await applyEvents(page['hostEpoch']! as int, events, page['through']! as int);
      if (events.length < 200) return;
    }
  }

  Future<void> _hostEpochChanged(int epoch) async {
    // The POS was restored: anything built for the old epoch needs a person.
    await (db.update(db.pendingCommands)..where((c) => c.state.isIn(CommandState.open))).write(
      PendingCommandsCompanion(
        state: const Value(CommandState.needsReview),
        errorCode: const Value(ErrorCode.epochChanged),
        errorMessage: const Value('The POS was restored from a backup. Check this before sending again.'),
        updatedAt: Value(_now()),
      ),
    );
    _setStatus(_current.copyWith(problem: 'hostRestored'));
  }

  // ---- Live updates ----------------------------------------------------------------------

  /// Keeps the cache current and the queue moving until [stop].
  Future<void> start() async {
    if (_running) return;
    _running = true;
    _deliverTimer = Timer.periodic(const Duration(seconds: 5), (_) => _bg(deliverNow));
    _bg(_connect);
  }

  Future<void> stop() async {
    _running = false;
    _reconnect?.cancel();
    _deliverTimer?.cancel();
    await _liveSub?.cancel();
    _liveSub = null;
    _lan?.close();
    _lan = null;
    _cloud?.close();
    _cloud = null;
  }

  /// Runs [task] in the background; [dispose] waits for it. Errors are
  /// swallowed here (the queue and status already record them).
  void _bg(Future<void> Function() task) {
    if (_disposed) return;
    late final Future<void> f;
    f = task().catchError((Object _) {}).whenComplete(() => _pending.remove(f));
    _pending.add(f);
  }

  Future<void> dispose() async {
    _disposed = true;
    await stop();
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList());
    }
    await _status.close();
    await _alarms.close();
  }

  void _scheduleReconnect() {
    if (!_running) return;
    _reconnectAttempts++;
    final cap = min(30000, 1000 * (1 << min(_reconnectAttempts, 5)));
    _reconnect?.cancel();
    _reconnect = Timer(Duration(milliseconds: 500 + _random.nextInt(cap)), () => _bg(_connect));
  }

  Future<void> _connect() async {
    if (!_running) return;
    final l = await link();
    final s = await session();
    if (l == null || s == null) {
      _scheduleReconnect();
      return;
    }
    try {
      final auth = await _auth(l);
      if (l.cursorEpoch == 0) await refresh();
      final cur = (await link())!;
      Stream<LiveMessage>? stream;
      String? routeName;
      for (final r in _routes(cur)) {
        try {
          stream = await r.live(cur.cursorEpoch, cur.cursorSequence, auth);
          routeName = r.name;
          break;
        } on RouteUnavailable {
          continue;
        }
      }
      if (stream == null) {
        _setStatus(LinkStatus(lastLiveAt: _current.lastLiveAt, problem: _current.problem));
        _scheduleReconnect();
        return;
      }
      _reconnectAttempts = 0;
      _setStatus(_current.copyWith(route: routeName, live: true, clearProblem: true));
      await _liveSub?.cancel();
      _liveSub = stream.listen(
        (m) => _bg(
          () => _onLive(m).catchError((Object e) {
            if (e is ProtocolException) _noteProblem(e);
          }),
        ),
        onDone: () {
          _setStatus(LinkStatus(lastLiveAt: _current.lastLiveAt, problem: _current.problem));
          _scheduleReconnect();
        },
        onError: (Object _) {},
        cancelOnError: false,
      );
      _bg(deliverNow);
    } on ProtocolException catch (e) {
      _noteProblem(e);
      if (e.code != ErrorCode.deviceRevoked && e.code != wrongCertificate) _scheduleReconnect();
    } on Object {
      _scheduleReconnect();
    }
  }

  Future<void> _onLive(LiveMessage m) async {
    final l = (await link())!;
    switch (m) {
      case LiveHello(:final hostEpoch):
        if (hostEpoch != l.cursorEpoch) await refresh();
      case LiveEvents(:final events, :final through):
        final ok = await applyEvents(l.cursorEpoch, events, through);
        if (!ok) await refresh();
      case LiveSnapshotRequired():
        await refresh();
        await _liveSub?.cancel();
        _scheduleReconnect();
      case LiveEventsAvailable(:final hostEpoch):
        if (hostEpoch != l.cursorEpoch) {
          await refresh();
        } else {
          await catchUp();
        }
      case LiveHostStatus():
        break;
    }
  }

  // ---- Commands ---------------------------------------------------------------------------

  Stream<List<PendingCommandRow>> watchCommands(String staffId) =>
      (db.select(db.pendingCommands)
            ..where((c) => c.staffId.equals(staffId) & c.state.isNotValue(CommandState.discarded))
            ..orderBy([(c) => OrderingTerm(expression: c.createdAt, mode: OrderingMode.desc)]))
          .watch();

  /// Saves a command on the phone (generated once, reused for every retry) and
  /// starts sending it.
  Future<String> enqueue({
    required String action,
    String? aggregateId,
    int? expectedRevision,
    required Map<String, Object?> payload,
    required String summary,
  }) async {
    final l = await link();
    final s = await session();
    if (l == null || s == null) throw const ConflictException('Sign in first');
    final id = _uuid.v4();
    final now = _now();
    final body = Command.build(
      commandId: id,
      restaurantId: l.restaurantId,
      deviceId: l.deviceId,
      staffId: s.staffId,
      hostEpoch: l.hostEpoch,
      action: action,
      aggregateId: aggregateId,
      expectedRevision: expectedRevision,
      issuedAt: now,
      payload: payload,
    );
    await db
        .into(db.pendingCommands)
        .insert(
          PendingCommandsCompanion.insert(
            commandId: id,
            staffId: s.staffId,
            action: action,
            aggregateId: Value(aggregateId),
            bodyJson: canonicalJson(body),
            summary: summary,
            state: CommandState.queued,
            createdAt: now,
            updatedAt: now,
          ),
        );
    _bg(deliverNow);
    return id;
  }

  Duration _backoff(int attempts) {
    final cap = min(maxBackoff.inMilliseconds, 1000 * (1 << min(attempts, 6)));
    return Duration(milliseconds: _random.nextInt(cap) + 250);
  }

  /// Sends due commands of the signed-in staff member (others wait for their
  /// owner to sign in again).
  /// Concurrent callers wait for the run already in progress (which then
  /// runs once more to pick up anything new).
  Future<void> deliverNow() {
    final running = _deliverRun;
    if (running != null) {
      _deliverAgain = true;
      return running;
    }
    final run = () async {
      try {
        do {
          _deliverAgain = false;
          await _deliverOnce();
        } while (_deliverAgain && !_disposed);
      } finally {
        _deliverRun = null;
      }
    }();
    _deliverRun = run;
    return run;
  }

  Future<void> _deliverOnce() async {
    final l = await link();
    final s = await session();
    if (l == null || s == null) return;
    final now = _now();
    final due =
        await (db.select(db.pendingCommands)
              ..where(
                (c) =>
                    c.staffId.equals(s.staffId) &
                    c.state.isIn(CommandState.open) &
                    c.nextAttemptAt.isSmallerOrEqualValue(now),
              )
              ..orderBy([(c) => OrderingTerm(expression: c.createdAt)]))
            .get();
    if (due.isEmpty) return;
    final RouteAuth auth;
    try {
      auth = await _auth(l);
    } on ProtocolException {
      return;
    }
    for (final c in due) {
      // Stop if someone else signed in meanwhile: never send one person's
      // command with another person's session.
      if ((await session())?.staffId != s.staffId) break;
      if (c.state != CommandState.relayed && now - c.createdAt > commandExpiry.inMilliseconds) {
        await _update(
          c.commandId,
          CommandState.needsReview,
          code: ErrorCode.expired,
          message:
              'Not delivered within ${commandExpiry.inMinutes} minutes, so it was not sent automatically. '
              'Check it before sending again.',
        );
        continue;
      }
      final stop = await _deliverOne(l, c, auth);
      if (stop) break;
    }
  }

  /// Returns true when delivery should pause (signed out, revoked, …).
  Future<bool> _deliverOne(ClientLinkRow l, PendingCommandRow c, RouteAuth auth) async {
    final body = (jsonDecode(c.bodyJson) as Map).cast<String, Object?>();
    final ambiguous = c.attempts > 0;
    await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(c.commandId))).write(
      PendingCommandsCompanion(
        state: Value(c.state == CommandState.relayed ? CommandState.relayed : CommandState.sending),
        attempts: Value(c.attempts + 1),
        updatedAt: Value(_now()),
      ),
    );
    for (final r in _routes(l)) {
      try {
        Delivery? d;
        // A previous attempt may have reached the POS: ask before sending again.
        if (ambiguous || c.state == CommandState.relayed) d = await r.lookup(c.commandId, auth);
        // Safe to send again on any route: the POS and the relay de-duplicate by
        // command id and body hash.
        if (d?.result == null) d = await r.send(body, auth);
        if (d?.result != null) {
          await _finish(c.commandId, d!.result!, r.name);
          return false;
        }
        if (d?.mailboxState != null) {
          final terminal = d!.mailboxState == 'expired' || d.mailboxState == 'quarantined';
          await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(c.commandId))).write(
            PendingCommandsCompanion(
              state: Value(terminal ? CommandState.needsReview : CommandState.relayed),
              mailboxState: Value(d.mailboxState),
              lastRoute: Value(r.name),
              errorCode: Value(terminal ? d.mailboxState!.toUpperCase() : null),
              errorMessage: Value(
                terminal ? 'The POS did not receive this in time. Check it before sending again.' : null,
              ),
              nextAttemptAt: Value(_now() + _backoff(c.attempts + 1).inMilliseconds),
              updatedAt: Value(_now()),
            ),
          );
          return false;
        }
      } on RouteUnavailable {
        continue;
      } on ProtocolException catch (e) {
        return _failed(c, e, r.name);
      }
    }
    await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(c.commandId))).write(
      PendingCommandsCompanion(
        state: Value(c.state == CommandState.relayed ? CommandState.relayed : CommandState.queued),
        nextAttemptAt: Value(_now() + _backoff(c.attempts + 1).inMilliseconds),
        updatedAt: Value(_now()),
      ),
    );
    return false;
  }

  Future<bool> _failed(PendingCommandRow c, ProtocolException e, String route) async {
    _noteProblem(e);
    switch (e.code) {
      case ErrorCode.rateLimited || ErrorCode.hostUnreachable || ErrorCode.hostTimeout:
        await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(c.commandId))).write(
          PendingCommandsCompanion(
            state: const Value(CommandState.queued),
            nextAttemptAt: Value(_now() + _backoff(c.attempts + 1).inMilliseconds),
            lastRoute: Value(route),
            updatedAt: Value(_now()),
          ),
        );
        return false;
      case ErrorCode.sessionExpired || ErrorCode.unauthenticated || ErrorCode.staffDisabled:
        // Keep it queued for this person; delivery resumes after sign-in.
        await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(c.commandId))).write(
          PendingCommandsCompanion(state: const Value(CommandState.queued), updatedAt: Value(_now())),
        );
        final l = await link();
        if (l != null && e.code != ErrorCode.unauthenticated) await secrets.delete(_sessionKey(l.deviceId));
        if (e.code != ErrorCode.unauthenticated) await db.delete(db.clientSessions).go();
        return true;
      case ErrorCode.deviceRevoked || wrongCertificate:
        await _update(c.commandId, CommandState.needsReview, code: e.code, message: e.message);
        return true;
      case ErrorCode.epochChanged || ErrorCode.commandIdReused:
        await _update(c.commandId, CommandState.needsReview, code: e.code, message: e.message);
        return false;
      default:
        await _update(c.commandId, CommandState.rejected, code: e.code, message: e.message);
        return false;
    }
  }

  Future<void> _finish(String commandId, CommandResult result, String route) async {
    await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).write(
      PendingCommandsCompanion(
        state: Value(result.accepted ? CommandState.accepted : CommandState.rejected),
        resultJson: Value(jsonEncode(result.toJson())),
        errorCode: Value(result.error?.code),
        errorMessage: Value(result.error?.message),
        lastRoute: Value(route),
        mailboxState: const Value(null),
        updatedAt: Value(_now()),
      ),
    );
    if (result.accepted) {
      final l = await link();
      if (l != null && l.cursorSequence < result.eventSequence) _bg(catchUp);
    }
  }

  Future<void> _update(String commandId, String state, {String? code, String? message}) =>
      (db.update(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).write(
        PendingCommandsCompanion(
          state: Value(state),
          errorCode: Value(code),
          errorMessage: Value(message),
          updatedAt: Value(_now()),
        ),
      );

  /// After review: send again. The same command is reused unless it was built
  /// for an older POS epoch, in which case a fresh command replaces it.
  Future<String> resend(String commandId) async {
    final c = await (db.select(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).getSingle();
    if (c.state == CommandState.accepted) throw const ConflictException('The POS already accepted this');
    final l = (await link())!;
    final body = (jsonDecode(c.bodyJson) as Map).cast<String, Object?>();
    if (body['hostEpoch'] != l.hostEpoch || c.errorCode == ErrorCode.commandIdReused) {
      await _update(commandId, CommandState.discarded);
      return enqueue(
        action: c.action,
        aggregateId: c.aggregateId,
        expectedRevision: body['expectedRevision'] as int?,
        payload: (body['payload']! as Map).cast<String, Object?>(),
        summary: c.summary,
      );
    }
    await (db.update(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).write(
      PendingCommandsCompanion(
        state: const Value(CommandState.queued),
        createdAt: Value(_now()),
        nextAttemptAt: const Value(0),
        errorCode: const Value(null),
        errorMessage: const Value(null),
        updatedAt: Value(_now()),
      ),
    );
    _bg(deliverNow);
    return commandId;
  }

  Future<void> discard(String commandId) async {
    final c = await (db.select(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).getSingle();
    if (c.state == CommandState.accepted) throw const ConflictException('The POS already accepted this');
    if (c.state == CommandState.sending) throw const ConflictException('This is being sent right now');
    await _update(commandId, CommandState.discarded);
  }

  /// PRICE_CHANGED: the user confirmed the POS prices; send a new command
  /// with those prices.
  Future<String> confirmNewPrices(String commandId) async {
    final c = await (db.select(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).getSingle();
    final result = c.resultJson == null ? null : CommandResult.fromJson((jsonDecode(c.resultJson!) as Map).cast());
    final error = result?.error;
    if (error == null || error.code != ErrorCode.priceChanged) {
      throw const ConflictException('There are no new prices to confirm');
    }
    final body = (jsonDecode(c.bodyJson) as Map).cast<String, Object?>();
    final payload = (body['payload']! as Map).cast<String, Object?>();
    final lines = [for (final line in payload['lines']! as List) (line! as Map).cast<String, Object?>()];
    for (final changed in error.details!['lines']! as List) {
      final ch = (changed! as Map).cast<String, Object?>();
      lines[ch['index']! as int] = {...lines[ch['index']! as int], 'expectedUnitPrice': ch['current']};
    }
    await _update(commandId, CommandState.discarded);
    return enqueue(
      action: c.action,
      aggregateId: c.aggregateId,
      expectedRevision: body['expectedRevision'] as int?,
      payload: {...payload, 'lines': lines},
      summary: c.summary,
    );
  }

  /// TABLE_OCCUPIED: add the same items to the order already on that table.
  Future<String> addToExistingOrder(String commandId) async {
    final c = await (db.select(db.pendingCommands)..where((x) => x.commandId.equals(commandId))).getSingle();
    final result = c.resultJson == null ? null : CommandResult.fromJson((jsonDecode(c.resultJson!) as Map).cast());
    final error = result?.error;
    if (error == null || error.code != ErrorCode.tableOccupied) {
      throw const ConflictException('This order was not refused because of an occupied table');
    }
    final payload = ((jsonDecode(c.bodyJson) as Map)['payload']! as Map).cast<String, Object?>();
    await _update(commandId, CommandState.discarded);
    return enqueue(
      action: CommandAction.orderAdd,
      aggregateId: error.details!['orderId']! as String,
      payload: {'lines': payload['lines'], 'sendToKitchen': payload['sendToKitchen'] ?? true},
      summary: c.summary,
    );
  }
}
