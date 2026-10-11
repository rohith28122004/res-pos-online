import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera QR scanning is available on Android phones and tablets.
bool get canScanQr => Platform.isAndroid;

/// Scans a CaféDesk Online pairing QR code and returns its text.
class PairScannerScreen extends StatefulWidget {
  const PairScannerScreen({super.key});
  @override
  State<PairScannerScreen> createState() => _PairScannerScreenState();
}

class _PairScannerScreenState extends State<PairScannerScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _done = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan the pairing code')),
    body: Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.startsWith('cdpair1.')) {
                _done = true;
                Navigator.of(context).pop(v);
                return;
              }
            }
          },
          errorBuilder: (context, error) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                error.errorCode == MobileScannerErrorCode.permissionDenied
                    ? 'Camera permission is off. Allow the camera for CaféDesk Online in Android settings, or paste '
                          'the pairing text instead.'
                    : 'The camera could not start. Paste the pairing text instead.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ),
        const Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Point the camera at the code on the POS screen',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ),
      ],
    ),
  );
}
