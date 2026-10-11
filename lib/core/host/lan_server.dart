import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../features/devices/application/device_service.dart';
import '../database/app_database.dart';
import '../protocol/protocol.dart';
import '../protocol/sealed.dart';
import '../service_context.dart';
import 'approvals.dart';
import 'command_dispatcher.dart';
import 'host_keys.dart';
import 'session_service.dart';
import 'snapshots.dart';

/// Counts failures per client address; refuses after [limit] in [window].
class FailureLimiter {
  FailureLimiter({this.limit = 5, this.window = const Duration(minutes: 1)});

  final int limit;
  final Duration window;
  final _failures = <String, List<DateTime>>{};

  Duration? blockedFor(String key, DateTime now) {
    final list = _failures[key]?..removeWhere((t) => now.difference(t) > window);
    if (list == null || list.length < limit) return null;
    return window - now.difference(list.first);
  }

  void fail(String key, DateTime now) => _failures.putIfAbsent(key, () => []).add(now);
  void succeed(String key) => _failures.remove(key);
}

/// The POS host's LAN API (docs/PROTOCOL.md §7): HTTPS + WebSocket with the
/// self-signed certificate devices pinned at pairing. Every route except
/// `health` and `pair` needs a device credential; everything except sign-in
/// also needs a live staff session.
class LanServer {
  LanServer({
    required this.ctx,
    required this.keys,
    required this.dispatcher,
    HostSessions? sessions,
    DeviceService? devices,
    HostReads? reads,
  }) : sessions = sessions ?? HostSessions(ctx),
       devices = devices ?? DeviceService(ctx),
       reads = reads ?? HostReads(ctx);

  final ServiceContext ctx;
  final HostKeys keys;
  final CommandDispatcher dispatcher;
  final HostSessions sessions;
  final DeviceService devices;
  final HostReads reads;

  ApprovalRegistry get approvals => dispatcher.approvals;
  AppDatabase get _db => ctx.db;

  static const maxBody = 256 * 1024;
  static const _sealedReplayWindow = Duration(minutes: 10);
  static const _revalidateEvery = Duration(seconds: 60);

  final _limiter = FailureLimiter();
  final _seenRequestIds = <String, DateTime>{};
  final _sockets = <_DeviceSocket>{};
  HttpServer? _server;
  StreamSubscription<Object?>? _eventsSub;

  bool get running => _server != null;
  int? get port => _server?.port;
  int get connectedSockets => _sockets.length;

  /// Starts listening on all IPv4 interfaces (port 0 picks a free port).
  Future<void> start({int port = 47821, InternetAddress? address}) async {
    if (_server != null) return;
    final context = SecurityContext(withTrustedRoots: false)
      ..useCertificateChainBytes(utf8.encode(keys.tlsCertPem))
      ..usePrivateKeyBytes(utf8.encode(keys.tlsKeyPem));
    final server = await HttpServer.bindSecure(address ?? InternetAddress.anyIPv4, port, context);
    server.idleTimeout = const Duration(seconds: 30);
    _server = server;
    _eventsSub = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.hostEvents, limitUpdateKind: UpdateKind.insert))
        .listen((_) => _pushToSockets());
    server.listen((r) => unawaited(_handle(r)), onError: (_) {});
  }

  Future<void> stop() async {
    await _eventsSub?.cancel();
    _eventsSub = null;
    for (final s in _sockets.toList()) {
      await s.close(1001, 'POS server stopped');
    }
    _sockets.clear();
    await _server?.close(force: true);
    _server = null;
  }

  // ---- Request handling ---------------------------------------------------------

  Future<void> _handle(HttpRequest r) async {
    try {
      final path = r.uri.path;
      switch ((r.method, path)) {
        case ('GET', '/v1/health'):
          return _json(r, 200, {
            'ok': true,
            'minProtocolVersion': ProtocolVersion.min,
            'maxProtocolVersion': ProtocolVersion.max,
          });
        case ('POST', '/v1/pair'):
          return await _pair(r);
        case ('POST', '/v1/auth/sealed'):
          return await _sealed(r);
        case ('POST', '/v1/auth/sign-out'):
          final (_, caller) = await _authenticate(r);
          await sessions.signOut(caller);
          return _json(r, 200, {'ok': true});
        case ('GET', '/v1/snapshot'):
          final (_, caller) = await _authenticate(r);
          final scope = caller.deviceRole == DeviceRole.kitchen ? 'kitchen' : 'waiter';
          if ((r.uri.queryParameters['scope'] ?? scope) != scope) {
            throw const ProtocolException(ErrorCode.forbidden, 'This device cannot read that view');
          }
          return _json(r, 200, await reads.snapshot(scope));
        case ('POST', '/v1/commands'):
          final (_, caller) = await _authenticate(r);
          final body = await _readJson(r);
          final result = await dispatcher.handle(caller, body);
          return _json(r, 200, result.toJson());
        case ('GET', '/v1/events'):
          await _authenticate(r);
          final epoch = int.tryParse(r.uri.queryParameters['epoch'] ?? '') ?? 0;
          final after = int.tryParse(r.uri.queryParameters['after'] ?? '') ?? 0;
          final limit = (int.tryParse(r.uri.queryParameters['limit'] ?? '') ?? 200).clamp(1, 500);
          return _json(r, 200, await reads.eventsAfter(epoch, after, limit: limit));
        case ('GET', '/v1/socket'):
          return await _socket(r);
      }
      if (r.method == 'GET' && path.startsWith('/v1/commands/')) {
        final (_, caller) = await _authenticate(r);
        final id = path.substring('/v1/commands/'.length);
        final found = await dispatcher.lookup(caller, id);
        if (found == null) {
          throw const ProtocolException(ErrorCode.notFound, 'The POS has no record of this command');
        }
        return _json(r, 200, found.toJson());
      }
      throw const ProtocolException(ErrorCode.notFound, 'Unknown route');
    } on ProtocolException catch (e) {
      _error(r, e);
    } on Object {
      // Never echo internals (or request bodies) back to the device.
      _error(r, const ProtocolException(ErrorCode.internal, 'The POS could not complete this request'));
    }
  }

  Future<(PairedDeviceRow, RemoteCaller)> _authenticate(HttpRequest r) async {
    final identity = await _identity();
    final device = await sessions.authenticateDevice(r.headers.value('x-cafedesk-device'));
    final caller = await sessions.authenticateSession(
      device,
      r.headers.value(HttpHeaders.authorizationHeader),
      identity,
    );
    return (device, caller);
  }

  Future<HostIdentityRow> _identity() async {
    final identity = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (identity == null) {
      throw const ProtocolException(ErrorCode.forbidden, 'This POS is not set up for connected devices');
    }
    if (identity.reconcileRequired) {
      throw const ProtocolException(
        ErrorCode.epochChanged,
        'The POS was restored from a backup. The owner must reconnect devices on the POS first.',
      );
    }
    return identity;
  }

  String _client(HttpRequest r) => r.connectionInfo?.remoteAddress.address ?? 'unknown';

  void _checkLimit(HttpRequest r) {
    final wait = _limiter.blockedFor(_client(r), ctx.now());
    if (wait != null) {
      throw ProtocolException(
        ErrorCode.rateLimited,
        'Too many attempts. Wait a minute and try again.',
        details: {'retryAfterMs': wait.inMilliseconds},
      );
    }
  }

  Future<void> _pair(HttpRequest r) async {
    _checkLimit(r);
    final identity = await _identity();
    final body = await _readJson(r);
    if (body is! Map) throw const ProtocolException(ErrorCode.validation, 'Expected a JSON object');
    final j = body.cast<String, Object?>();
    final version = j['protocolVersion'];
    if (version is! int || !ProtocolVersion.supported(version)) {
      throw const ProtocolException(
        ErrorCode.updateRequired,
        'Update CaféDesk Online on this device',
        details: {'min': ProtocolVersion.min, 'max': ProtocolVersion.max},
      );
    }
    final PairingResult result;
    try {
      result = await devices.redeem(
        code: requireString(j, 'pairingCode', maxLength: 100),
        deviceName: requireString(j, 'deviceName', maxLength: 40),
        platform: optionalString(j, 'platform', maxLength: 40),
        appVersion: optionalString(j, 'appVersion', maxLength: 40),
      );
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.unauthenticated) _limiter.fail(_client(r), ctx.now());
      rethrow;
    }
    _limiter.succeed(_client(r));
    return _json(r, 200, {
      'deviceId': result.deviceId,
      'deviceCredential': result.credential,
      'role': result.role,
      'restaurantId': identity.restaurantId,
      'hostDeviceId': identity.hostDeviceId,
      'hostEpoch': identity.hostEpoch,
      'hostSigningPublicKey': identity.signingPublicKey,
      'hostSealPublicKey': identity.sealPublicKey,
      'cloudUrl': identity.cloudUrl,
      'restaurantName': (await ctx.settings()).name,
    });
  }

  Future<void> _sealed(HttpRequest r) async {
    _checkLimit(r);
    final identity = await _identity();
    final device = await sessions.authenticateDevice(r.headers.value('x-cafedesk-device'));
    final body = await _readJson(r);
    if (body is! Map) throw const ProtocolException(ErrorCode.validation, 'Expected a JSON object');
    final response = await handleSealed(device, identity, body['sealed'], clientKey: _client(r));
    return _json(r, 200, response);
  }

  /// Opens and runs a sealed request. Shared by the LAN route and the cloud
  /// relay (the cloud forwards the same sealed box).
  Future<Map<String, Object?>> handleSealed(
    PairedDeviceRow device,
    HostIdentityRow identity,
    Object? sealed, {
    required String clientKey,
  }) async {
    final req = await Sealed.open(sealed, hostSealKey: keys.sealKey, deviceId: device.id);
    final requestId = requireId(req, 'requestId');
    final now = ctx.now();
    _seenRequestIds.removeWhere((_, t) => now.difference(t) > _sealedReplayWindow);
    if (_seenRequestIds.containsKey(requestId)) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This request was already used');
    }
    _seenRequestIds[requestId] = now;
    final email = requireString(req, 'email', maxLength: 254);
    final password = requireString(req, 'password', maxLength: 128);
    try {
      switch (req['kind']) {
        case 'sign_in':
          final s = await sessions.signIn(device, email, password, identity, keys);
          _limiter.succeed(clientKey);
          return {
            'sessionToken': s.token,
            'expiresAt': s.expiresAt,
            'staff': {'staffId': s.actor.staffId, 'name': s.actor.name, 'role': s.actor.role.name},
          };
        case 'approve':
          final approval = await sessions.approve(email, password);
          final id = approvals.grant(approval, device.id);
          _limiter.succeed(clientKey);
          return {
            'approvalId': id,
            'ownerName': approval.ownerName,
            'expiresAt': approval.issuedAt.millisecondsSinceEpoch + const Duration(minutes: 5).inMilliseconds,
          };
        default:
          throw const ProtocolException(ErrorCode.validation, 'Unknown sealed request');
      }
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.unauthenticated) _limiter.fail(clientKey, ctx.now());
      rethrow;
    }
  }

  // ---- WebSocket ----------------------------------------------------------------

  Future<void> _socket(HttpRequest r) async {
    if (!WebSocketTransformer.isUpgradeRequest(r)) {
      throw const ProtocolException(ErrorCode.validation, 'WebSocket upgrade expected');
    }
    final (device, caller) = await _authenticate(r);
    final epoch = int.tryParse(r.uri.queryParameters['epoch'] ?? '') ?? 0;
    final after = int.tryParse(r.uri.queryParameters['after'] ?? '') ?? 0;
    // Closed by _DeviceSocket.close() or when the device disconnects.
    // ignore: close_sinks
    final ws = await WebSocketTransformer.upgrade(r);
    ws.pingInterval = const Duration(seconds: 20);
    final s = _DeviceSocket(
      ws,
      device.id,
      caller,
      epoch,
      after,
      deviceHeader: r.headers.value('x-cafedesk-device'),
      authorization: r.headers.value(HttpHeaders.authorizationHeader),
    );
    _sockets.add(s);
    ws.listen(
      (_) {}, // Read-only socket: commands go through POST /v1/commands.
      onDone: () => _sockets.remove(s),
      onError: (_) => _sockets.remove(s),
      cancelOnError: true,
    );
    s.revalidate = Timer.periodic(_revalidateEvery, (_) => unawaited(_revalidate(s)));
    final identity = await _identity();
    s.send({'t': 'hello', 'hostEpoch': identity.hostEpoch, 'latestSequence': await _latestSequence()});
    await _pushTo(s);
  }

  Future<int> _latestSequence() async => (await reads.eventsAfter(0, 0, limit: 1))['through']! as int;

  Future<void> _revalidate(_DeviceSocket s) async {
    try {
      final identity = await _identity();
      final device = await sessions.authenticateDevice(s.deviceHeader);
      await sessions.authenticateSession(device, s.authorization, identity);
    } on ProtocolException catch (e) {
      await s.close(4401, e.code);
      _sockets.remove(s);
    }
  }

  void _pushToSockets() {
    for (final s in _sockets.toList()) {
      unawaited(_pushTo(s));
    }
  }

  Future<void> _pushTo(_DeviceSocket s) async {
    if (s.pushing) {
      s.pushAgain = true;
      return;
    }
    s.pushing = true;
    try {
      do {
        s.pushAgain = false;
        final page = await reads.eventsAfter(s.epoch, s.cursor);
        if (page['snapshotRequired'] == true) {
          s.send({'t': 'snapshot_required', 'hostEpoch': page['hostEpoch']});
          s.epoch = page['hostEpoch']! as int;
          s.cursor = page['through']! as int;
          continue;
        }
        final events = page['events']! as List<Object?>;
        final through = page['through']! as int;
        if (events.isNotEmpty || through > s.cursor) {
          s.send({'t': 'events', 'events': events, 'through': through});
          s.cursor = through;
          if (events.length >= 200) s.pushAgain = true;
        }
      } while (s.pushAgain && !s.closed);
    } on Object {
      await s.close(1011, 'POS error');
      _sockets.remove(s);
    } finally {
      s.pushing = false;
    }
  }

  // ---- JSON helpers ---------------------------------------------------------------

  Future<Object?> _readJson(HttpRequest r) async {
    if ((r.contentLength) > maxBody) {
      throw const ProtocolException(ErrorCode.tooLarge, 'Request is too large');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in r) {
      bytes.add(chunk);
      if (bytes.length > maxBody) throw const ProtocolException(ErrorCode.tooLarge, 'Request is too large');
    }
    try {
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on FormatException {
      throw const ProtocolException(ErrorCode.validation, 'Request is not valid JSON');
    }
  }

  void _json(HttpRequest r, int status, Object? body) {
    r.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set(HttpHeaders.cacheControlHeader, 'no-store')
      ..write(jsonEncode(body));
    unawaited(r.response.close());
  }

  void _error(HttpRequest r, ProtocolException e) {
    try {
      _json(r, ErrorCode.httpStatus(e.code), {'error': e.toJson()});
    } on Object {
      // The connection is already gone or upgraded.
    }
  }
}

class _DeviceSocket {
  _DeviceSocket(
    this.ws,
    this.deviceId,
    this.caller,
    this.epoch,
    this.cursor, {
    required this.deviceHeader,
    required this.authorization,
  });

  final WebSocket ws;
  final String deviceId;
  final RemoteCaller caller;
  int epoch;
  int cursor;
  final String? deviceHeader;
  final String? authorization;
  Timer? revalidate;
  bool pushing = false;
  bool pushAgain = false;
  bool closed = false;

  void send(Map<String, Object?> message) {
    if (!closed) ws.add(jsonEncode(message));
  }

  Future<void> close(int code, String reason) async {
    if (closed) return;
    closed = true;
    revalidate?.cancel();
    await ws.close(code, reason);
  }
}
