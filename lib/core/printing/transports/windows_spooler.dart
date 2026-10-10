/// Windows print spooler integration through dart:ffi (winspool.drv and
/// gdi32.dll). Two paths:
///  * RAW: ESC/POS bytes are handed to the installed printer queue unchanged
///    (for thermal printers whose queue accepts raw data).
///  * Driver-rendered: the receipt is rasterised in Dart and drawn on the
///    printer's GDI device context, so the vendor driver renders it.
///
/// Calls run on a background isolate so a slow spooler never blocks the UI.
/// "Submitted" means the spooler accepted the job — not that paper came out.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'transport.dart';

// ---- Native signatures -------------------------------------------------------

typedef _OpenPrinterN = Int32 Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _OpenPrinterD = int Function(Pointer<Utf16>, Pointer<IntPtr>, Pointer<Void>);
typedef _HandleN = Int32 Function(IntPtr);
typedef _HandleD = int Function(int);
typedef _StartDocPrinterN = Uint32 Function(IntPtr, Uint32, Pointer<_DocInfo1>);
typedef _StartDocPrinterD = int Function(int, int, Pointer<_DocInfo1>);
typedef _WritePrinterN = Int32 Function(IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>);
typedef _WritePrinterD = int Function(int, Pointer<Uint8>, int, Pointer<Uint32>);
typedef _EnumPrintersN =
    Int32 Function(Uint32, Pointer<Utf16>, Uint32, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint32>);
typedef _EnumPrintersD = int Function(int, Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint32>);
typedef _CreateDCN = IntPtr Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>);
typedef _CreateDCD = int Function(Pointer<Utf16>, Pointer<Utf16>, Pointer<Utf16>, Pointer<Void>);
typedef _StartDocN = Int32 Function(IntPtr, Pointer<_DocInfoW>);
typedef _StartDocD = int Function(int, Pointer<_DocInfoW>);
typedef _GetDeviceCapsN = Int32 Function(IntPtr, Int32);
typedef _GetDeviceCapsD = int Function(int, int);
typedef _StretchDIBitsN =
    Int32 Function(
      IntPtr,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Int32,
      Pointer<Uint8>,
      Pointer<Uint8>,
      Uint32,
      Uint32,
    );
typedef _StretchDIBitsD =
    int Function(int, int, int, int, int, int, int, int, int, Pointer<Uint8>, Pointer<Uint8>, int, int);
typedef _GetLastErrorN = Uint32 Function();
typedef _GetLastErrorD = int Function();

final class _DocInfo1 extends Struct {
  external Pointer<Utf16> pDocName;
  external Pointer<Utf16> pOutputFile;
  external Pointer<Utf16> pDatatype;
}

final class _DocInfoW extends Struct {
  @Int32()
  external int cbSize;
  external Pointer<Utf16> lpszDocName;
  external Pointer<Utf16> lpszOutput;
  external Pointer<Utf16> lpszDatatype;
  @Uint32()
  external int fwType;
}

final class _PrinterInfo4 extends Struct {
  external Pointer<Utf16> pPrinterName;
  external Pointer<Utf16> pServerName;
  @Uint32()
  external int attributes;
}

class _Win {
  _Win() {
    final spool = DynamicLibrary.open('winspool.drv');
    final gdi = DynamicLibrary.open('gdi32.dll');
    final kernel = DynamicLibrary.open('kernel32.dll');
    openPrinter = spool.lookupFunction<_OpenPrinterN, _OpenPrinterD>('OpenPrinterW');
    closePrinter = spool.lookupFunction<_HandleN, _HandleD>('ClosePrinter');
    startDocPrinter = spool.lookupFunction<_StartDocPrinterN, _StartDocPrinterD>('StartDocPrinterW');
    startPagePrinter = spool.lookupFunction<_HandleN, _HandleD>('StartPagePrinter');
    writePrinter = spool.lookupFunction<_WritePrinterN, _WritePrinterD>('WritePrinter');
    endPagePrinter = spool.lookupFunction<_HandleN, _HandleD>('EndPagePrinter');
    endDocPrinter = spool.lookupFunction<_HandleN, _HandleD>('EndDocPrinter');
    abortPrinter = spool.lookupFunction<_HandleN, _HandleD>('AbortPrinter');
    enumPrinters = spool.lookupFunction<_EnumPrintersN, _EnumPrintersD>('EnumPrintersW');
    createDC = gdi.lookupFunction<_CreateDCN, _CreateDCD>('CreateDCW');
    deleteDC = gdi.lookupFunction<_HandleN, _HandleD>('DeleteDC');
    startDoc = gdi.lookupFunction<_StartDocN, _StartDocD>('StartDocW');
    startPage = gdi.lookupFunction<_HandleN, _HandleD>('StartPage');
    endPage = gdi.lookupFunction<_HandleN, _HandleD>('EndPage');
    endDoc = gdi.lookupFunction<_HandleN, _HandleD>('EndDoc');
    abortDoc = gdi.lookupFunction<_HandleN, _HandleD>('AbortDoc');
    getDeviceCaps = gdi.lookupFunction<_GetDeviceCapsN, _GetDeviceCapsD>('GetDeviceCaps');
    stretchDIBits = gdi.lookupFunction<_StretchDIBitsN, _StretchDIBitsD>('StretchDIBits');
    getLastError = kernel.lookupFunction<_GetLastErrorN, _GetLastErrorD>('GetLastError');
  }

  late final _OpenPrinterD openPrinter;
  late final _HandleD closePrinter;
  late final _StartDocPrinterD startDocPrinter;
  late final _HandleD startPagePrinter;
  late final _WritePrinterD writePrinter;
  late final _HandleD endPagePrinter;
  late final _HandleD endDocPrinter;
  late final _HandleD abortPrinter;
  late final _EnumPrintersD enumPrinters;
  late final _CreateDCD createDC;
  late final _HandleD deleteDC;
  late final _StartDocD startDoc;
  late final _HandleD startPage;
  late final _HandleD endPage;
  late final _HandleD endDoc;
  late final _HandleD abortDoc;
  late final _GetDeviceCapsD getDeviceCaps;
  late final _StretchDIBitsD stretchDIBits;
  late final _GetLastErrorD getLastError;
}

const _printerEnumLocal = 0x2;
const _printerEnumConnections = 0x4;
const _horzRes = 8;
const _vertRes = 10;
const _dibRgbColors = 0;
const _srcCopy = 0x00CC0020;

/// Installed printer queue names.
Future<List<String>> listWindowsPrinters() async {
  if (!Platform.isWindows) return const [];
  return Isolate.run(_enumPrinters);
}

List<String> _enumPrinters() {
  final w = _Win();
  return using((arena) {
    final needed = arena<Uint32>();
    final returned = arena<Uint32>();
    const flags = _printerEnumLocal | _printerEnumConnections;
    w.enumPrinters(flags, nullptr, 4, nullptr, 0, needed, returned);
    if (needed.value == 0) return <String>[];
    final buffer = arena<Uint8>(needed.value);
    if (w.enumPrinters(flags, nullptr, 4, buffer, needed.value, needed, returned) == 0) return <String>[];
    final infos = buffer.cast<_PrinterInfo4>();
    return [
      for (var i = 0; i < returned.value; i++) infos[i].pPrinterName.toDartString(),
    ]..sort();
  });
}

/// RAW job: bytes go to the queue unchanged. [outputFile] (testing only)
/// redirects the job to a file instead of the device.
Future<SendResult> sendRawToWindowsPrinter(
  String printerName,
  Uint8List bytes, {
  required String jobName,
  String? outputFile,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!Platform.isWindows) return const SendResult.failed('Windows printing is only available on Windows');
  try {
    final r = await Isolate.run(() => _sendRaw(printerName, bytes, jobName, outputFile)).timeout(timeout);
    return r;
  } on Object catch (e) {
    return SendResult.unknown('Windows spooler did not answer in time ($e)');
  }
}

SendResult _sendRaw(String printerName, Uint8List bytes, String jobName, String? outputFile) {
  final w = _Win();
  return using((arena) {
    final handlePtr = arena<IntPtr>();
    if (w.openPrinter(printerName.toNativeUtf16(allocator: arena), handlePtr, nullptr) == 0) {
      return SendResult.failed('Could not open printer "$printerName" (Windows error ${w.getLastError()})');
    }
    final h = handlePtr.value;
    try {
      final doc = arena<_DocInfo1>()
        ..ref.pDocName = jobName.toNativeUtf16(allocator: arena)
        ..ref.pOutputFile = outputFile == null ? nullptr : outputFile.toNativeUtf16(allocator: arena)
        ..ref.pDatatype = 'RAW'.toNativeUtf16(allocator: arena);
      final jobId = w.startDocPrinter(h, 1, doc);
      if (jobId == 0) {
        return SendResult.failed(
          'The printer queue refused a RAW job (Windows error ${w.getLastError()}). '
          'Try the "driver rendered" mode for this printer.',
        );
      }
      w.startPagePrinter(h);
      final buf = arena<Uint8>(bytes.length);
      buf.asTypedList(bytes.length).setAll(0, bytes);
      final written = arena<Uint32>();
      final ok = w.writePrinter(h, buf, bytes.length, written) != 0;
      if (!ok || written.value != bytes.length) {
        final err = w.getLastError();
        w.abortPrinter(h);
        return SendResult.unknown('Only ${written.value} of ${bytes.length} bytes were written (Windows error $err)');
      }
      w.endPagePrinter(h);
      if (w.endDocPrinter(h) == 0) {
        return SendResult.unknown('Windows could not finish the print job (error ${w.getLastError()})');
      }
      return const SendResult.submitted();
    } finally {
      w.closePrinter(h);
    }
  });
}

/// Driver-rendered job: the 1-bit page is stretched to the printable width
/// of the queue's device context, split over pages if needed.
Future<SendResult> printBitmapToWindowsPrinter(
  String printerName,
  Uint8List bits,
  int width,
  int height, {
  required String jobName,
  String? outputFile,
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (!Platform.isWindows) return const SendResult.failed('Windows printing is only available on Windows');
  try {
    return await Isolate.run(
      () => _printBitmap(printerName, bits, width, height, jobName, outputFile),
    ).timeout(timeout);
  } on Object catch (e) {
    return SendResult.unknown('Windows printing did not answer in time ($e)');
  }
}

SendResult _printBitmap(String printerName, Uint8List bits, int width, int height, String jobName, String? outputFile) {
  final w = _Win();
  return using((arena) {
    final dc = w.createDC(
      'WINSPOOL'.toNativeUtf16(allocator: arena),
      printerName.toNativeUtf16(allocator: arena),
      nullptr,
      nullptr,
    );
    if (dc == 0) return SendResult.failed('Could not open printer "$printerName" for drawing');
    try {
      final pageW = w.getDeviceCaps(dc, _horzRes);
      final pageH = w.getDeviceCaps(dc, _vertRes);
      if (pageW <= 0 || pageH <= 0) return const SendResult.failed('The printer reported no printable area');

      // 1-bpp DIB rows must be DWORD aligned; palette 0 = white, 1 = black.
      // Each page gets its own top-down DIB drawn from source row 0, which
      // sidesteps StretchDIBits' source-rectangle quirks with top-down DIBs.
      final srcStride = width ~/ 8;
      final stride = (srcStride + 3) & ~3;
      final dib = arena<Uint8>(stride * height);
      final info = arena<Uint8>(48);
      void preparePage(int srcY, int rows) {
        final dibList = dib.asTypedList(stride * rows)..fillRange(0, stride * rows, 0);
        for (var y = 0; y < rows; y++) {
          dibList.setRange(y * stride, y * stride + srcStride, bits, (srcY + y) * srcStride);
        }
        final header = ByteData(48)
          ..setUint32(0, 40, Endian.little)
          ..setInt32(4, width, Endian.little)
          ..setInt32(8, -rows, Endian.little) // negative = top-down
          ..setUint16(12, 1, Endian.little)
          ..setUint16(14, 1, Endian.little)
          ..setUint32(16, 0, Endian.little)
          ..setUint32(20, stride * rows, Endian.little)
          ..setUint32(32, 2, Endian.little)
          ..setUint32(40, 0x00FFFFFF, Endian.little)
          ..setUint32(44, 0x00000000, Endian.little);
        info.asTypedList(48).setAll(0, header.buffer.asUint8List());
      }

      final doc = arena<_DocInfoW>()
        ..ref.cbSize = sizeOf<_DocInfoW>()
        ..ref.lpszDocName = jobName.toNativeUtf16(allocator: arena)
        ..ref.lpszOutput = outputFile == null ? nullptr : outputFile.toNativeUtf16(allocator: arena)
        ..ref.lpszDatatype = nullptr
        ..ref.fwType = 0;
      if (w.startDoc(dc, doc) <= 0) {
        return SendResult.failed('Windows refused the print job (error ${w.getLastError()})');
      }

      final srcRowsPerPage = (pageH * width / pageW).floor().clamp(1, height);
      var started = false;
      try {
        for (var srcY = 0; srcY < height; srcY += srcRowsPerPage) {
          final rows = (height - srcY) < srcRowsPerPage ? height - srcY : srcRowsPerPage;
          if (w.startPage(dc) <= 0) {
            if (!started) {
              w.abortDoc(dc);
              return const SendResult.failed('Windows could not start a page');
            }
            w.abortDoc(dc);
            return const SendResult.unknown('Windows stopped part-way through the job');
          }
          started = true;
          final destH = (rows * pageW / width).round();
          preparePage(srcY, rows);
          final drawn = w.stretchDIBits(dc, 0, 0, pageW, destH, 0, 0, width, rows, dib, info, _dibRgbColors, _srcCopy);
          w.endPage(dc);
          if (drawn == 0) {
            w.abortDoc(dc);
            return const SendResult.unknown('Windows could not draw the receipt image');
          }
        }
      } on Object {
        w.abortDoc(dc);
        rethrow;
      }
      if (w.endDoc(dc) <= 0) {
        return SendResult.unknown('Windows could not finish the print job (error ${w.getLastError()})');
      }
      return const SendResult.submitted();
    } finally {
      w.deleteDC(dc);
    }
  });
}

/// Checks that the queue exists and can be opened, without printing.
Future<SendResult> testWindowsPrinter(String printerName) async {
  if (!Platform.isWindows) return const SendResult.failed('Windows printing is only available on Windows');
  return Isolate.run(() {
    final w = _Win();
    return using((arena) {
      final handlePtr = arena<IntPtr>();
      if (w.openPrinter(printerName.toNativeUtf16(allocator: arena), handlePtr, nullptr) == 0) {
        return SendResult.failed('Printer "$printerName" was not found or cannot be opened');
      }
      w.closePrinter(handlePtr.value);
      return const SendResult.submitted();
    });
  });
}

class WindowsSpoolerTransport implements PrinterTransport {
  const WindowsSpoolerTransport();

  @override
  Future<SendResult> send(
    PrinterEndpoint endpoint,
    PrintPayload payload, {
    required Duration timeout,
    required String jobName,
  }) async {
    final name = endpoint.address.trim();
    if (name.isEmpty) return const SendResult.failed('Choose an installed Windows printer');
    return switch (payload) {
      BytesPayload(:final bytes) => sendRawToWindowsPrinter(name, bytes, jobName: jobName, timeout: timeout * 2),
      RasterPayload(:final bitmap) => printBitmapToWindowsPrinter(
        name,
        bitmap.data,
        bitmap.width,
        bitmap.height,
        jobName: jobName,
        timeout: timeout * 3,
      ),
    };
  }

  @override
  Future<SendResult> testConnection(PrinterEndpoint endpoint, {required Duration timeout}) =>
      testWindowsPrinter(endpoint.address.trim());
}
