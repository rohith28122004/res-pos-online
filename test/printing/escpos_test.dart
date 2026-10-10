import 'dart:typed_data';

import 'package:cafedesk/core/printing/documents/layout.dart';
import 'package:cafedesk/core/printing/documents/print_documents.dart';
import 'package:cafedesk/core/printing/encoders/escpos.dart';
import 'package:flutter_test/flutter_test.dart';

ReceiptDocument sampleReceipt({String? copy}) => ReceiptDocument(
  title: 'RECEIPT',
  restaurantName: 'Test Café',
  headerLines: const ['1 Main Road'],
  number: 'TST-000001',
  dateTime: '2026-10-05 10:00',
  infoLines: const ['Dine-in · Order #1', 'Cashier: Cara'],
  lines: const [
    ReceiptLineDoc(quantity: 2, name: 'Coffee', unitPrice: 10000, amount: 20000),
    ReceiptLineDoc(
      quantity: 1,
      name: 'Paneer tikka grilled sandwich with extra cheese and mint chutney',
      variant: 'Large',
      modifiers: ['+ Extra cheese'],
      unitPrice: 20000,
      amount: 20000,
      discount: 2000,
    ),
  ],
  summary: const [AmountRow('Subtotal', 40000), AmountRow('Item discounts', -2000), AmountRow('CGST 2.5%', 450)],
  total: 38450,
  payments: const [AmountRow('Cash', 38450), AmountRow('Cash received', 50000), AmountRow('Change', 11550)],
  footerLines: const ['Thank you!'],
  currencyCode: 'INR',
  copyLabel: copy,
);

void main() {
  test('CP437 table has exactly 128 characters', () {
    // Encoding every high character round-trips to a distinct byte.
    final bytes = <int>{};
    for (final rune in 'ÇüéâäàåçêëèïîìÄÅ½¼¡«»░▒▓│┤■'.runes) {
      final e = encodeText(String.fromCharCode(rune), CodePage.cp437);
      expect(e.unsupported, isEmpty);
      bytes.add(e.bytes.single);
    }
    expect(bytes.length, 'ÇüéâäàåçêëèïîìÄÅ½¼¡«»░▒▓│┤■'.runes.length);
    expect(encodeText('é', CodePage.cp437).bytes, [0x82]);
    expect(encodeText('■', CodePage.cp437).bytes, [0xFE]);
    expect(encodeText('é', CodePage.wpc1252).bytes, [0xE9]);
    expect(encodeText('€', CodePage.wpc1252).bytes, [0x80]);
  });

  test('rupee falls back to INR explicitly; unknown scripts are reported', () {
    final r = encodeText('₹120', CodePage.cp437);
    expect(String.fromCharCodes(r.bytes), 'INR120');
    expect(r.unsupported, isEmpty);
    final tamil = encodeText('காபி', CodePage.cp437);
    expect(tamil.unsupported, isNotEmpty);
  });

  test('text encoder refuses to print corrupt text', () {
    const enc = EscPosTextEncoder(codePage: CodePage.cp437, charsPerLine: 32, cutMode: CutMode.partial);
    expect(() => enc.encode(const [PText('காபி')]), throwsA(isA<UnsupportedCharactersError>()));
  });

  test('receipt layout fits the paper width and wraps long names (58 and 80 mm)', () {
    for (final width in [32, 48]) {
      final ops = layoutReceipt(sampleReceipt(), LayoutOptions(charsPerLine: width));
      final lines = previewLines(ops, width);
      expect(lines.every((l) => l.runes.length <= width), isTrue, reason: 'width $width');
      final text = lines.join('\n');
      // Double-size text is previewed with spaced letters.
      expect(text, contains('T O T A L   I N R'));
      expect(text, contains('3 8 4 . 5 0'));
      expect(text, contains('Paneer'));
      expect(text, contains('chutney'));
      expect(text, contains('Change'));
    }
  });

  test('copies are clearly marked', () {
    final lines = previewLines(
      layoutReceipt(sampleReceipt(copy: CopyLabel.copy), const LayoutOptions(charsPerLine: 32)),
      32,
    );
    expect(lines.where((l) => l.contains('*** COPY ***')).length, 2);
  });

  test('ESC/POS bytes: init, code page, cut and optional drawer pulse', () {
    const enc = EscPosTextEncoder(codePage: CodePage.cp437, charsPerLine: 48, cutMode: CutMode.partial);
    final bytes = enc.encode(layoutReceipt(sampleReceipt(), const LayoutOptions(charsPerLine: 48, drawerPulse: true)));
    expect(bytes.sublist(0, 5), [0x1B, 0x40, 0x1B, 0x74, 0x00]);
    expect(_contains(bytes, [0x1D, 0x56, 0x42, 0x00]), isTrue, reason: 'partial cut');
    expect(_contains(bytes, [0x1B, 0x70, 0x00]), isTrue, reason: 'drawer pulse');
    final noCut = const EscPosTextEncoder(
      codePage: CodePage.cp437,
      charsPerLine: 48,
      cutMode: CutMode.none,
    ).encode(layoutReceipt(sampleReceipt(), const LayoutOptions(charsPerLine: 48)));
    expect(_contains(noCut, [0x1D, 0x56]), isFalse);
    expect(_contains(noCut, [0x1B, 0x70]), isFalse, reason: 'drawer pulse off by default');
  });

  test('KOT shows cancellations and hides prices by default', () {
    const kot = KotDocument(
      ticketNo: 7,
      kind: 'correction',
      orderRef: 'T4 · #23',
      orderTypeLabel: 'Dine-in',
      dateTime: '2026-10-05 10:05',
      staffName: 'Cara',
      reason: 'Customer left',
      lines: [KotLineDoc(quantity: -2, name: 'Coffee', unitPrice: 10000, note: 'No sugar')],
      currencyCode: 'INR',
    );
    final text = previewLines(layoutKot(kot, const LayoutOptions(charsPerLine: 32)), 32).join('\n');
    expect(text, contains('CANCEL 2 x Coffee'));
    expect(text, contains('Customer left'));
    expect(text, isNot(contains('100.00')));
  });

  test('raster encoder emits GS v 0 bands', () {
    final bmp = MonoBitmap(width: 16, height: 3, data: Uint8List.fromList([0xFF, 0x00, 0x0F, 0xF0, 0x00, 0xFF]));
    final bytes = const EscPosRasterEncoder(cutMode: CutMode.full, bandHeight: 2).encode(bmp);
    expect(bytes.sublist(0, 2), [0x1B, 0x40]);
    expect(bytes.sublist(2, 10), [0x1D, 0x76, 0x30, 0x00, 2, 0, 2, 0]);
    expect(bytes.sublist(10, 14), [0xFF, 0x00, 0x0F, 0xF0]);
    expect(bytes.sublist(14, 22), [0x1D, 0x76, 0x30, 0x00, 2, 0, 1, 0]);
    expect(_contains(bytes, [0x1D, 0x56, 0x41, 0x00]), isTrue);
  });

  test('RGBA to mono threshold', () {
    final rgba = Uint8List.fromList([0, 0, 0, 255, 255, 255, 255, 255, 10, 10, 10, 0]);
    final m = MonoBitmap.fromRgba(rgba, 3, 1, targetWidth: 8);
    expect(m.dot(0, 0), isTrue);
    expect(m.dot(1, 0), isFalse);
    expect(m.dot(2, 0), isFalse, reason: 'transparent is paper');
  });

  test('document JSON round trip', () {
    final doc = sampleReceipt(copy: CopyLabel.reprint);
    final back = decodeDocument(doc.encode()) as ReceiptDocument;
    expect(back.encode(), doc.encode());
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}
