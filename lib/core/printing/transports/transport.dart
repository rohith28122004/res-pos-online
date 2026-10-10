import 'dart:typed_data';

import '../encoders/escpos.dart';

enum TransportType {
  tcp('tcp', 'Network (LAN / Wi-Fi, ESC/POS)'),
  bluetooth('bluetooth', 'Bluetooth Classic (Android)'),
  windowsRaw('windows_raw', 'Windows printer — RAW ESC/POS'),
  windowsDriver('windows_driver', 'Windows printer — driver rendered');

  const TransportType(this.code, this.label);
  final String code;
  final String label;

  static TransportType parse(String code) => TransportType.values.firstWhere((t) => t.code == code);
}

/// What we can honestly say about a send.
enum SendOutcome {
  /// Bytes reached the printer connection or the Windows spooler. This does
  /// NOT prove paper came out.
  submitted,

  /// Definitely not sent (could not connect / open the printer). Safe to retry.
  failed,

  /// Something broke after data started flowing (timeout, disconnect, crash).
  /// It may or may not have printed: a person must check before retrying.
  unknown,
}

class SendResult {
  const SendResult(this.outcome, [this.error]);
  const SendResult.submitted() : this(SendOutcome.submitted);
  const SendResult.failed(String error) : this(SendOutcome.failed, error);
  const SendResult.unknown(String error) : this(SendOutcome.unknown, error);

  final SendOutcome outcome;
  final String? error;

  bool get ok => outcome == SendOutcome.submitted;

  @override
  String toString() => error == null ? outcome.name : '${outcome.name}: $error';
}

sealed class PrintPayload {
  const PrintPayload();
}

/// Raw ESC/POS bytes.
class BytesPayload extends PrintPayload {
  const BytesPayload(this.bytes);
  final Uint8List bytes;
}

/// A rendered page for the Windows driver path.
class RasterPayload extends PrintPayload {
  const RasterPayload(this.bitmap);
  final MonoBitmap bitmap;
}

class PrinterEndpoint {
  const PrinterEndpoint({required this.type, required this.address, this.port});
  final TransportType type;

  /// Host/IP, Bluetooth MAC address, or Windows printer name.
  final String address;
  final int? port;

  @override
  String toString() => port == null ? '${type.code}:$address' : '${type.code}:$address:$port';
}

abstract class PrinterTransport {
  Future<SendResult> send(
    PrinterEndpoint endpoint,
    PrintPayload payload, {
    required Duration timeout,
    required String jobName,
  });

  /// Connects (or opens the printer) without printing.
  Future<SendResult> testConnection(PrinterEndpoint endpoint, {required Duration timeout});
}

class DiscoveredPrinter {
  const DiscoveredPrinter({required this.name, required this.address, required this.type, this.detail});
  final String name;
  final String address;
  final TransportType type;
  final String? detail;
}

/// Validates a host name or IPv4 address for LAN printers.
String? validateHost(String host) {
  final h = host.trim();
  if (h.isEmpty) return 'Enter the printer IP address or host name';
  final ipv4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$').firstMatch(h);
  if (ipv4 != null) {
    for (var i = 1; i <= 4; i++) {
      if (int.parse(ipv4.group(i)!) > 255) return 'That IP address is not valid';
    }
    return null;
  }
  if (h.length > 253 ||
      !RegExp(
        r'^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$',
      ).hasMatch(h)) {
    return 'That host name is not valid';
  }
  return null;
}

String? validatePort(int? port) =>
    (port == null || port < 1 || port > 65535) ? 'Port must be between 1 and 65535 (usually 9100)' : null;

String? validateBluetoothAddress(String address) =>
    RegExp(r'^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$').hasMatch(address.trim())
    ? null
    : 'Choose a paired Bluetooth printer';
