import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../network/lan_client.dart' show RouteUnavailable;
import '../protocol/protocol.dart';
import 'host_route.dart';

/// Error codes that are business outcomes from the POS. Any other code inside
/// a relayed result (sign-in, device, epoch, version, internal) is a delivery
/// problem the phone handles like a transport error, not a final answer.
const _businessCodes = {
  ErrorCode.validation,
  ErrorCode.staleRevision,
  ErrorCode.tableOccupied,
  ErrorCode.orderClosed,
  ErrorCode.priceChanged,
  ErrorCode.itemUnavailable,
  ErrorCode.approvalRequired,
  ErrorCode.transitionNotAllowed,
  ErrorCode.conflict,
  ErrorCode.notFound,
};

/// The phone's route through the Cloudflare relay (docs/PROTOCOL.md §8). Same
/// commands, same ids and bodies as the LAN; normal web certificate checks
/// (the cloud has a public certificate). Plain http is accepted only for a
/// development Worker on localhost.
class CloudRoute implements HostRoute {
  CloudRoute(this.base, {HttpClient? http, this.timeout = const Duration(seconds: 15)})
    : _http = http ?? (HttpClient()..connectionTimeout = const Duration(seconds: 8));

  final Uri base;
  final Duration timeout;
  final HttpClient _http;

  @override
  String get name => 'cloud';

  Future<(int, Object?)> _raw(
    String method,
    String path, {
    Object? body,
    required RouteAuth auth,
    Map<String, String>? query,
  }) async {
    try {
      final req = await _http.openUrl(method, base.replace(path: path, queryParameters: query)).timeout(timeout);
      auth.headers.forEach(req.headers.set);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close().timeout(timeout);
      final text = await utf8.decoder.bind(res).join().timeout(timeout);
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        json = null;
      }
      return (res.statusCode, json);
    } on SocketException {
      throw const RouteUnavailable('The cloud relay is not reachable');
    } on TimeoutException {
      throw const RouteUnavailable('The cloud relay did not answer');
    } on HandshakeException {
      throw const RouteUnavailable('Could not make a secure connection to the cloud relay');
    } on HttpException {
      throw const RouteUnavailable('The cloud relay connection failed');
    }
  }

  Future<Map<String, Object?>> _json(
    String method,
    String path, {
    Object? body,
    required RouteAuth auth,
    Map<String, String>? query,
  }) async {
    final (status, json) = await _raw(method, path, body: body, auth: auth, query: query);
    if (status >= 200 && status < 300 && json is Map) return json.cast<String, Object?>();
    if (json is Map && json['error'] is Map) {
      final e = ProtocolException.fromJson((json['error']! as Map).cast<String, Object?>());
      // The host is down or busy: the phone treats this route as unavailable.
      if (e.code == ErrorCode.hostUnreachable || e.code == ErrorCode.hostTimeout) throw RouteUnavailable(e.message);
      throw e;
    }
    throw ProtocolException(ErrorCode.internal, 'Unexpected answer from the cloud relay (HTTP $status)');
  }

  Future<Map<String, Object?>> _request(String kind, Map<String, Object?> body, RouteAuth auth) => _json(
    'POST',
    '/v1/device/requests',
    body: {'protocolVersion': ProtocolVersion.current, 'kind': kind, 'body': body},
    auth: auth,
  );

  @override
  Future<Map<String, Object?>> sealed(Map<String, Object?> sealedBox, RouteAuth auth) =>
      _request('sealed_auth', {'sealed': sealedBox}, RouteAuth(deviceCredential: auth.deviceCredential));

  @override
  Future<Map<String, Object?>> snapshot(String scope, RouteAuth auth) => _request('snapshot', {'scope': scope}, auth);

  Delivery _delivery(Map<String, Object?> view) {
    final raw = view['result'];
    if (raw is Map) {
      final result = CommandResult.fromJson(raw.cast<String, Object?>());
      final error = result.error;
      if (error != null && !_businessCodes.contains(error.code)) throw error;
      return Delivery(result: result);
    }
    return Delivery(mailboxState: view['mailboxState'] as String?);
  }

  @override
  Future<Delivery> send(Map<String, Object?> command, RouteAuth auth) async =>
      _delivery(await _json('POST', '/v1/device/commands', body: command, auth: auth));

  @override
  Future<Delivery?> lookup(String commandId, RouteAuth auth) async {
    try {
      return _delivery(await _json('GET', '/v1/device/commands/$commandId', auth: auth));
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.notFound) return null;
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>> events(int epoch, int after, RouteAuth auth) =>
      _json('GET', '/v1/device/events', auth: auth, query: {'epoch': '$epoch', 'after': '$after'});

  @override
  Future<Stream<LiveMessage>> live(int epoch, int after, RouteAuth auth) async {
    final uri = base.replace(scheme: base.scheme == 'https' ? 'wss' : 'ws', path: '/v1/device/socket');
    final WebSocket ws;
    try {
      ws = await WebSocket.connect(uri.toString(), headers: auth.headers, customClient: _http).timeout(timeout);
    } on Object {
      throw const RouteUnavailable('The cloud relay is not reachable');
    }
    return liveStreamOf(ws, _parse);
  }

  static LiveMessage? _parse(Object? j) {
    if (j is! Map) return null;
    switch (j['t']) {
      case 'events':
        return LiveEventsAvailable(j['hostEpoch']! as int, j['latestSequence']! as int);
      case 'host':
        return LiveHostStatus(connected: j['connected'] == true);
      case 'command':
        return const LiveCommandNotice();
    }
    return null;
  }

  /// The relay has no sign-out route; the token is deleted on the phone and
  /// expires on its own.
  @override
  Future<void> signOut(RouteAuth auth) async => throw const RouteUnavailable('Sign-out is done on the LAN');

  @override
  void close() => _http.close(force: true);
}
