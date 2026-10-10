import 'dart:async';
import 'dart:io';

import 'transport.dart';

/// ESC/POS over a raw TCP socket (commonly port 9100). Works on a local
/// network with no internet; the printer must be reachable.
class TcpTransport implements PrinterTransport {
  const TcpTransport();

  @override
  Future<SendResult> send(
    PrinterEndpoint endpoint,
    PrintPayload payload, {
    required Duration timeout,
    required String jobName,
  }) async {
    if (payload is! BytesPayload) return const SendResult.failed('Network printers need ESC/POS data');
    final hostError = validateHost(endpoint.address) ?? validatePort(endpoint.port);
    if (hostError != null) return SendResult.failed(hostError);

    Socket socket;
    try {
      socket = await Socket.connect(endpoint.address.trim(), endpoint.port!, timeout: timeout);
    } on Object catch (e) {
      // Nothing was written, so this is a clean failure.
      return SendResult.failed('Could not connect to ${endpoint.address}:${endpoint.port} (${_short(e)})');
    }
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
      socket.add(payload.bytes);
      await socket.flush().timeout(timeout);
      await socket.close().timeout(timeout);
      return const SendResult.submitted();
    } on Object catch (e) {
      // Some bytes may already be in the printer: outcome is uncertain.
      return SendResult.unknown('Connection lost while sending (${_short(e)})');
    } finally {
      socket.destroy();
    }
  }

  @override
  Future<SendResult> testConnection(PrinterEndpoint endpoint, {required Duration timeout}) async {
    final hostError = validateHost(endpoint.address) ?? validatePort(endpoint.port);
    if (hostError != null) return SendResult.failed(hostError);
    try {
      final socket = await Socket.connect(endpoint.address.trim(), endpoint.port!, timeout: timeout);
      socket.destroy();
      return const SendResult.submitted();
    } on Object catch (e) {
      return SendResult.failed('Could not connect to ${endpoint.address}:${endpoint.port} (${_short(e)})');
    }
  }

  static String _short(Object e) {
    if (e is SocketException) return e.osError?.message ?? e.message;
    if (e is TimeoutException) return 'timed out';
    return e.toString();
  }
}
