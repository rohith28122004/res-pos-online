import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../protocol/protocol.dart';
import 'command_dispatcher.dart';
import 'host_api.dart';

/// The POS host's LAN API (docs/PROTOCOL.md §7): HTTPS + WebSocket with the
/// self-signed certificate devices pinned at pairing. Every route except
/// `health` and `pair` needs a device credential; everything except sign-in
/// also needs a live staff session. The logic lives in [HostApi], shared with
/// the cloud relay connector.
class LanServer {
  LanServer(this.api);

  final HostApi api;

  AppDatabase get _db => api.ctx.db;

  static const maxBody = 256 * 1024;
  static const _revalidateEvery = Duration(seconds: 60);

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
      ..useCertificateChainBytes(utf8.encode(api.keys.tlsCertPem))
      ..usePrivateKeyBytes(utf8.encode(api.keys.tlsKeyPem));
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

  String _client(HttpRequest r) => r.connectionInfo?.remoteAddress.address ?? 'unknown';

  Future<RemoteCaller> _authenticate(HttpRequest r) =>
      api.authenticate(r.headers.value('x-cafedesk-device'), r.headers.value(HttpHeaders.authorizationHeader));

  Future<void> _handle(HttpRequest r) async {
    try {
      final path = r.uri.path;
      final q = r.uri.queryParameters;
      switch ((r.method, path)) {
        case ('GET', '/v1/health'):
          return _json(r, 200, {
            'ok': true,
            'minProtocolVersion': ProtocolVersion.min,
            'maxProtocolVersion': ProtocolVersion.max,
          });
        case ('POST', '/v1/pair'):
          return _json(r, 200, await api.pair(await _readJson(r), clientKey: _client(r)));
        case ('POST', '/v1/auth/sealed'):
          api.checkLimit(_client(r));
          await api.identity();
          final device = await api.sessions.authenticateDevice(r.headers.value('x-cafedesk-device'));
          final body = await _readJson(r);
          if (body is! Map) throw const ProtocolException(ErrorCode.validation, 'Expected a JSON object');
          return _json(r, 200, await api.sealed(device, body['sealed'], clientKey: _client(r)));
        case ('POST', '/v1/auth/sign-out'):
          await api.signOut(await _authenticate(r));
          return _json(r, 200, {'ok': true});
        case ('GET', '/v1/snapshot'):
          return _json(r, 200, await api.snapshot(await _authenticate(r), q['scope']));
        case ('POST', '/v1/commands'):
          final caller = await _authenticate(r);
          return _json(r, 200, (await api.command(caller, await _readJson(r))).toJson());
        case ('GET', '/v1/events'):
          await _authenticate(r);
          return _json(
            r,
            200,
            await api.events(
              int.tryParse(q['epoch'] ?? '') ?? 0,
              int.tryParse(q['after'] ?? '') ?? 0,
              limit: int.tryParse(q['limit'] ?? '') ?? 200,
            ),
          );
        case ('GET', '/v1/socket'):
          return await _socket(r);
      }
      if (r.method == 'GET' && path.startsWith('/v1/commands/')) {
        final caller = await _authenticate(r);
        return _json(r, 200, (await api.lookup(caller, path.substring('/v1/commands/'.length))).toJson());
      }
      throw const ProtocolException(ErrorCode.notFound, 'Unknown route');
    } on ProtocolException catch (e) {
      _error(r, e);
    } on Object {
      // Never echo internals (or request bodies) back to the device.
      _error(r, const ProtocolException(ErrorCode.internal, 'The POS could not complete this request'));
    }
  }

  // ---- WebSocket ----------------------------------------------------------------

  Future<void> _socket(HttpRequest r) async {
    if (!WebSocketTransformer.isUpgradeRequest(r)) {
      throw const ProtocolException(ErrorCode.validation, 'WebSocket upgrade expected');
    }
    final caller = await _authenticate(r);
    final epoch = int.tryParse(r.uri.queryParameters['epoch'] ?? '') ?? 0;
    final after = int.tryParse(r.uri.queryParameters['after'] ?? '') ?? 0;
    // Closed by _DeviceSocket.close() or when the device disconnects.
    // ignore: close_sinks
    final ws = await WebSocketTransformer.upgrade(r);
    ws.pingInterval = const Duration(seconds: 20);
    final s = _DeviceSocket(
      ws,
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
    final identity = await api.identity();
    final latest = (await api.events(0, 0, limit: 1))['through']! as int;
    s.send({'t': 'hello', 'hostEpoch': identity.hostEpoch, 'latestSequence': latest});
    await _pushTo(s);
  }

  Future<void> _revalidate(_DeviceSocket s) async {
    try {
      await api.authenticate(s.deviceHeader, s.authorization);
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
        final page = await api.events(s.epoch, s.cursor);
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
    if (r.contentLength > maxBody) {
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
    this.caller,
    this.epoch,
    this.cursor, {
    required this.deviceHeader,
    required this.authorization,
  });

  final WebSocket ws;
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
