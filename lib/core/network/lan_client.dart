import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;

import '../protocol/protocol.dart';

/// The route could not be used (no network, host not running, timeout). The
/// request may or may not have reached the host — callers that change data
/// retry with the same command id, never a new one.
class RouteUnavailable implements Exception {
  const RouteUnavailable(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Client-side code: the host presented a certificate other than the one
/// pinned at pairing. Never retried on that address.
const wrongCertificate = 'WRONG_CERTIFICATE';

/// An [HttpClient] that trusts exactly one certificate: the POS host's, by the
/// SHA-256 of its DER bytes. No system roots, no other certificate, so a
/// look-alike server on the café Wi-Fi is refused at the TLS handshake.
HttpClient pinnedHttpClient(String certSha256, {Duration connectTimeout = const Duration(seconds: 4)}) {
  final client = HttpClient(context: SecurityContext(withTrustedRoots: false))
    ..connectionTimeout = connectTimeout
    ..idleTimeout = const Duration(seconds: 15)
    ..badCertificateCallback = (cert, host, port) => hash.sha256.convert(cert.der).toString() == certSha256;
  return client;
}

/// HTTPS + WebSocket client for the POS host's LAN API (docs/PROTOCOL.md §7).
class LanClient {
  LanClient({
    required List<String> addresses,
    required this.port,
    required this.certSha256,
    this.timeout = const Duration(seconds: 8),
  }) : _addresses = [...addresses];

  final List<String> _addresses;
  final int port;
  final String certSha256;
  final Duration timeout;

  String? _preferred;
  late final HttpClient _http = pinnedHttpClient(certSha256);

  List<String> get _order => [?_preferred, ..._addresses.where((a) => a != _preferred)];

  Uri _uri(String address, String path, [Map<String, String>? query]) =>
      Uri(scheme: 'https', host: address, port: port, path: path, queryParameters: query);

  /// Sends a request, trying each known host address. Returns the decoded JSON
  /// body of a 2xx response; throws [ProtocolException] for an error response
  /// and [RouteUnavailable] when no address answered.
  Future<Map<String, Object?>> request(
    String method,
    String path, {
    Object? body,
    Map<String, String> headers = const {},
    Map<String, String>? query,
  }) async {
    var certificateRefused = false;
    for (final address in _order) {
      HttpClientResponse response;
      try {
        final req = await _http.openUrl(method, _uri(address, path, query)).timeout(timeout);
        headers.forEach(req.headers.set);
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(jsonEncode(body));
        }
        response = await req.close().timeout(timeout);
      } on HandshakeException {
        certificateRefused = true;
        continue;
      } on SocketException {
        continue;
      } on TimeoutException {
        continue;
      } on HttpException {
        continue;
      }
      _preferred = address;
      final text = await utf8.decoder.bind(response).join().timeout(timeout, onTimeout: () => '');
      Object? json;
      try {
        json = text.isEmpty ? null : jsonDecode(text);
      } on FormatException {
        json = null;
      }
      if (response.statusCode >= 200 && response.statusCode < 300 && json is Map) {
        return json.cast<String, Object?>();
      }
      if (json is Map && json['error'] is Map) {
        throw ProtocolException.fromJson((json['error']! as Map).cast<String, Object?>());
      }
      throw ProtocolException(ErrorCode.internal, 'Unexpected answer from the POS (HTTP ${response.statusCode})');
    }
    if (certificateRefused) {
      throw const ProtocolException(
        wrongCertificate,
        'A device on this network answered as the POS but is not the POS this phone was paired with.',
      );
    }
    throw const RouteUnavailable('The POS is not reachable on this network');
  }

  /// Opens the event WebSocket on the first address that accepts it.
  Future<WebSocket> openSocket(
    String path, {
    Map<String, String> headers = const {},
    Map<String, String>? query,
  }) async {
    var certificateRefused = false;
    for (final address in _order) {
      try {
        final uri = _uri(address, path, query).replace(scheme: 'wss');
        final ws = await WebSocket.connect(uri.toString(), headers: headers, customClient: _http).timeout(timeout);
        _preferred = address;
        return ws;
      } on HandshakeException {
        certificateRefused = true;
      } on SocketException {
        // Try the next address.
      } on TimeoutException {
        // Try the next address.
      } on WebSocketException {
        // Refused upgrade (e.g. expired sign-in): the HTTP routes report why.
      } on HttpException {
        // Try the next address.
      }
    }
    if (certificateRefused) {
      throw const ProtocolException(wrongCertificate, 'The POS certificate does not match this pairing');
    }
    throw const RouteUnavailable('The POS is not reachable on this network');
  }

  void close() => _http.close(force: true);
}
