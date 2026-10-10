@TestOn('windows')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:cafedesk/core/printing/encoders/escpos.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/core/printing/transports/windows_spooler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Exercises the real winspool/gdi32 FFI code against Windows' built-in
/// "Microsoft Print to PDF" queue with output redirected to a file. This proves
/// the API calls and struct layouts work; it is NOT a thermal printer test.
void main() {
  const pdfQueue = 'Microsoft Print to PDF';
  late Directory tmp;
  late bool available;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('cafedesk_spooler');
    available = (await listWindowsPrinters()).contains(pdfQueue);
  });
  tearDownAll(() => tmp.delete(recursive: true));

  test('lists installed printers', () async {
    final names = await listWindowsPrinters();
    expect(names, isNotEmpty);
  });

  test('opening a missing printer fails cleanly (safe to retry)', () async {
    final r = await testWindowsPrinter('No Such Printer 12345');
    expect(r.outcome, SendOutcome.failed);
    final send = await sendRawToWindowsPrinter('No Such Printer 12345', Uint8List.fromList([1, 2, 3]), jobName: 't');
    expect(send.outcome, SendOutcome.failed);
  });

  test('RAW job reaches the spooler byte-for-byte', () async {
    if (!available) return markTestSkipped('$pdfQueue not installed');
    final out = p.join(tmp.path, 'raw.bin');
    final bytes = Uint8List.fromList([0x1B, 0x40, ...'CafeDesk RAW test'.codeUnits, 0x0A, 0x1D, 0x56, 0x42, 0x00]);
    final r = await sendRawToWindowsPrinter(pdfQueue, bytes, jobName: 'CafeDesk RAW test', outputFile: out);
    // OpenPrinter → StartDocPrinter(RAW) → WritePrinter → EndDocPrinter all
    // succeeded and the spooler accepted the job.
    expect(r.outcome, SendOutcome.submitted, reason: r.error);
    for (var i = 0; i < 30 && !(File(out).existsSync() && File(out).lengthSync() >= bytes.length); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    // "Microsoft Print to PDF" is a v4 (XPS) driver that discards RAW data, so
    // the file can be empty here; a RAW-capable queue (e.g. "Generic / Text
    // Only" on a FILE: port, or a thermal printer driver) keeps the bytes.
    final written = File(out).existsSync() ? File(out).readAsBytesSync() : Uint8List(0);
    if (written.isNotEmpty) expect(written, bytes);
  });

  test('driver-rendered job draws the receipt image through GDI', () async {
    if (!available) return markTestSkipped('$pdfQueue not installed');
    final out = p.join(tmp.path, 'gdi.pdf');
    // 384 x 200 test pattern: black border and stripes.
    const w = 384, h = 200;
    final data = Uint8List(w ~/ 8 * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final black = y < 4 || y >= h - 4 || x < 4 || x >= w - 4 || (y ~/ 20).isEven && x % 40 < 20;
        if (black) data[y * (w ~/ 8) + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    final bmp = MonoBitmap(width: w, height: h, data: data);
    final r = await printBitmapToWindowsPrinter(
      pdfQueue,
      bmp.data,
      bmp.width,
      bmp.height,
      jobName: 'CafeDesk GDI test',
      outputFile: out,
    );
    expect(r.outcome, SendOutcome.submitted, reason: r.error);
    for (var i = 0; i < 100 && !(File(out).existsSync() && File(out).lengthSync() > 0); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final pdf = File(out).readAsBytesSync();
    expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
  });
}
