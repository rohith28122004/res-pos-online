import 'dart:io';

import 'package:flutter/services.dart';

import 'transport.dart';

/// Android Bluetooth Classic (SPP/RFCOMM) via the Kotlin plugin in
/// android/app/src/main/kotlin/.../BluetoothPrinterPlugin.kt. BLE-only
/// printers and vendor protocols are not supported.
class BluetoothTransport implements PrinterTransport {
  const BluetoothTransport();

  static const _channel = MethodChannel('cafedesk/bluetooth_printer');

  static bool get supported => Platform.isAndroid;

  /// 'granted', 'denied' or 'permanently_denied'.
  static Future<String> permissionStatus() async {
    if (!supported) return 'unsupported';
    return (await _channel.invokeMethod<String>('permissionStatus')) ?? 'denied';
  }

  static Future<String> requestPermission() async {
    if (!supported) return 'unsupported';
    return (await _channel.invokeMethod<String>('requestPermission')) ?? 'denied';
  }

  static Future<void> openAppSettings() async {
    if (supported) await _channel.invokeMethod<void>('openAppSettings');
  }

  /// Paired (bonded) devices. Pair the printer in Android settings first.
  static Future<List<DiscoveredPrinter>> bondedDevices() async {
    if (!supported) return const [];
    final result = await _channel.invokeListMethod<Map<Object?, Object?>>('bondedDevices') ?? const [];
    return [
      for (final d in result)
        DiscoveredPrinter(
          name: (d['name'] as String?) ?? 'Unnamed device',
          address: d['address']! as String,
          type: TransportType.bluetooth,
          detail: d['address'] as String?,
        ),
    ];
  }

  @override
  Future<SendResult> send(
    PrinterEndpoint endpoint,
    PrintPayload payload, {
    required Duration timeout,
    required String jobName,
  }) async {
    if (!supported) return const SendResult.failed('Bluetooth printing is only available on Android');
    if (payload is! BytesPayload) return const SendResult.failed('Bluetooth printers need ESC/POS data');
    final err = validateBluetoothAddress(endpoint.address);
    if (err != null) return SendResult.failed(err);
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('send', {
        'address': endpoint.address.trim(),
        'bytes': payload.bytes,
        'timeoutMs': timeout.inMilliseconds,
      });
      return _result(r);
    } on PlatformException catch (e) {
      // The plugin reports pre-write failures itself; an exception here means
      // we cannot tell whether bytes went out.
      return SendResult.unknown('Bluetooth error: ${e.message ?? e.code}');
    }
  }

  @override
  Future<SendResult> testConnection(PrinterEndpoint endpoint, {required Duration timeout}) async {
    if (!supported) return const SendResult.failed('Bluetooth printing is only available on Android');
    final err = validateBluetoothAddress(endpoint.address);
    if (err != null) return SendResult.failed(err);
    try {
      final r = await _channel.invokeMapMethod<String, Object?>('test', {
        'address': endpoint.address.trim(),
        'timeoutMs': timeout.inMilliseconds,
      });
      return _result(r);
    } on PlatformException catch (e) {
      return SendResult.failed('Bluetooth error: ${e.message ?? e.code}');
    }
  }

  static SendResult _result(Map<String, Object?>? r) {
    final outcome = r?['outcome'] as String?;
    final error = r?['error'] as String?;
    return switch (outcome) {
      'submitted' => const SendResult.submitted(),
      'failed' => SendResult.failed(error ?? 'Could not connect'),
      _ => SendResult.unknown(error ?? 'No answer from the Bluetooth plugin'),
    };
  }
}
