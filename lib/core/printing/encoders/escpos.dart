/// ESC/POS byte encoding. Pure Dart: no Flutter, no I/O, no money maths.
library;

import 'dart:typed_data';

import '../documents/layout.dart';

enum CodePage {
  /// PC437 (USA, Standard Europe) — ESC t 0. Supported by virtually every
  /// ESC/POS printer.
  cp437('cp437', 0, 'PC437 (USA / Standard Europe)'),

  /// WPC1252 (Windows Latin-1) — ESC t 16 on Epson-compatible printers.
  wpc1252('wpc1252', 16, 'WPC1252 (Windows Latin-1)'),

  /// 7-bit ASCII only; anything else is transliterated or rejected.
  ascii('ascii', 0, 'ASCII only');

  const CodePage(this.code, this.escTValue, this.label);
  final String code;
  final int escTValue;
  final String label;

  static CodePage parse(String code) => CodePage.values.firstWhere((c) => c.code == code, orElse: () => CodePage.cp437);
}

enum CutMode {
  none('none', 'No cutter'),
  partial('partial', 'Partial cut'),
  full('full', 'Full cut');

  const CutMode(this.code, this.label);
  final String code;
  final String label;

  static CutMode parse(String code) => CutMode.values.firstWhere((c) => c.code == code, orElse: () => CutMode.none);
}

const _cp437High =
    'ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ ';

const _wpc1252Specials = <int, int>{
  0x20AC: 0x80,
  0x201A: 0x82,
  0x0192: 0x83,
  0x201E: 0x84,
  0x2026: 0x85,
  0x2020: 0x86,
  0x2021: 0x87,
  0x02C6: 0x88,
  0x2030: 0x89,
  0x0160: 0x8A,
  0x2039: 0x8B,
  0x0152: 0x8C,
  0x017D: 0x8E,
  0x2018: 0x91,
  0x2019: 0x92,
  0x201C: 0x93,
  0x201D: 0x94,
  0x2022: 0x95,
  0x2013: 0x96,
  0x2014: 0x97,
  0x02DC: 0x98,
  0x2122: 0x99,
  0x0161: 0x9A,
  0x203A: 0x9B,
  0x0153: 0x9C,
  0x017E: 0x9E,
  0x0178: 0x9F,
};

final Map<int, int> _cp437Map = {
  for (var i = 0; i < _cp437High.runes.length; i++) _cp437High.runes.elementAt(i): 0x80 + i,
};

/// Explicit fallbacks used only when the code page lacks the character.
/// The rupee sign becomes "INR" — never a corrupt glyph.
const _transliterations = <String, String>{
  '₹': 'INR',
  '€': 'EUR',
  '—': '-',
  '–': '-',
  '‘': "'",
  '’': "'",
  '“': '"',
  '”': '"',
  '…': '...',
  '•': '*',
  '·': '-',
  '×': 'x',
  ' ': ' ',
  '\t': ' ',
};

int? _encodeRune(int rune, CodePage page) {
  if (rune >= 0x20 && rune < 0x7F) return rune;
  switch (page) {
    case CodePage.ascii:
      return null;
    case CodePage.cp437:
      return _cp437Map[rune];
    case CodePage.wpc1252:
      if (rune >= 0xA0 && rune <= 0xFF) return rune;
      return _wpc1252Specials[rune];
  }
}

class TextEncoding {
  const TextEncoding(this.bytes, this.unsupported);
  final List<int> bytes;

  /// Characters that could not be printed in this code page.
  final Set<String> unsupported;
}

/// Encodes [text] in [page]. Unprintable characters are transliterated when a
/// safe fallback exists; otherwise they are reported (and replaced by '?').
TextEncoding encodeText(String text, CodePage page) {
  final bytes = <int>[];
  final unsupported = <String>{};
  for (final rune in text.runes) {
    final b = _encodeRune(rune, page);
    if (b != null) {
      bytes.add(b);
      continue;
    }
    final ch = String.fromCharCode(rune);
    final alt = _transliterations[ch];
    if (alt != null && alt.runes.every((r) => _encodeRune(r, page) != null)) {
      for (final r in alt.runes) {
        bytes.add(_encodeRune(r, page)!);
      }
      continue;
    }
    if (rune == 0x0A || rune == 0x0D) continue;
    unsupported.add(ch);
    bytes.add(0x3F);
  }
  return TextEncoding(bytes, unsupported);
}

/// Characters in [ops] that [page] cannot print even after transliteration.
Set<String> unsupportedCharacters(List<PrintOp> ops, CodePage page) {
  final out = <String>{};
  for (final op in ops) {
    final texts = switch (op) {
      PText(:final text) => [text],
      PColumns(:final left, :final right) => [left, right],
      PRule(:final char) => [char],
      _ => const <String>[],
    };
    for (final t in texts) {
      out.addAll(encodeText(t, page).unsupported);
    }
  }
  return out;
}

abstract final class EscPos {
  static const esc = 0x1B;
  static const gs = 0x1D;
  static const lf = 0x0A;

  static List<int> init() => [esc, 0x40];
  static List<int> codePage(CodePage p) => [esc, 0x74, p.escTValue];
  static List<int> align(PAlign a) => [esc, 0x61, a.index];
  static List<int> bold(bool on) => [esc, 0x45, on ? 1 : 0];
  static List<int> size({required bool big}) => [gs, 0x21, big ? 0x11 : 0x00];
  static List<int> feed(int lines) => [esc, 0x64, lines.clamp(0, 255)];
  static List<int> cut(CutMode mode) => switch (mode) {
    CutMode.none => const [],
    CutMode.partial => [gs, 0x56, 0x42, 0x00],
    CutMode.full => [gs, 0x56, 0x41, 0x00],
  };

  /// Kick-out pulse on drawer pin 2 (ESC p 0 t1 t2).
  static List<int> drawerPulse() => [esc, 0x70, 0x00, 0x19, 0xFA];
}

class EscPosTextEncoder {
  const EscPosTextEncoder({required this.codePage, required this.charsPerLine, required this.cutMode});

  final CodePage codePage;
  final int charsPerLine;
  final CutMode cutMode;

  /// Encodes [ops]. Throws [UnsupportedCharactersError] if any text cannot be
  /// printed in the code page — the caller should switch to raster instead of
  /// printing corrupt text.
  Uint8List encode(List<PrintOp> ops) {
    final unsupported = unsupportedCharacters(ops, codePage);
    if (unsupported.isNotEmpty) throw UnsupportedCharactersError(unsupported);
    final out = BytesBuilder(copy: false)
      ..add(EscPos.init())
      ..add(EscPos.codePage(codePage));
    void line(String text) {
      out
        ..add(encodeText(text, codePage).bytes)
        ..addByte(EscPos.lf);
    }

    for (final op in ops) {
      switch (op) {
        case PText(:final text, :final align, :final bold, :final big):
          final width = big ? charsPerLine ~/ 2 : charsPerLine;
          out
            ..add(EscPos.align(align))
            ..add(EscPos.bold(bold))
            ..add(EscPos.size(big: big));
          for (final l in wrapText(text, width)) {
            line(l);
          }
          out
            ..add(EscPos.size(big: false))
            ..add(EscPos.bold(false))
            ..add(EscPos.align(PAlign.left));
        case PColumns(:final left, :final right, :final bold, :final big):
          final width = big ? charsPerLine ~/ 2 : charsPerLine;
          out
            ..add(EscPos.bold(bold))
            ..add(EscPos.size(big: big));
          for (final l in columnsToLines(left, right, width)) {
            line(l);
          }
          out
            ..add(EscPos.size(big: false))
            ..add(EscPos.bold(false));
        case PRule(:final char):
          line(char * charsPerLine);
        case PFeed(:final lines):
          out.add(EscPos.feed(lines));
        case PCut():
          out.add(EscPos.cut(cutMode));
        case PDrawerPulse():
          out.add(EscPos.drawerPulse());
      }
    }
    return out.toBytes();
  }
}

class UnsupportedCharactersError implements Exception {
  const UnsupportedCharactersError(this.characters);
  final Set<String> characters;

  @override
  String toString() => 'The printer code page cannot print: ${characters.join(' ')}';
}

/// 1-bit image, rows packed MSB-first, 1 = black dot.
class MonoBitmap {
  MonoBitmap({required this.width, required this.height, required this.data}) {
    if (width % 8 != 0) throw ArgumentError('width must be a multiple of 8');
    if (data.length != width ~/ 8 * height) throw ArgumentError('data length mismatch');
  }

  final int width;
  final int height;
  final Uint8List data;

  int get bytesPerRow => width ~/ 8;

  bool dot(int x, int y) => (data[y * bytesPerRow + (x >> 3)] & (0x80 >> (x & 7))) != 0;

  /// Converts RGBA pixels to 1-bit using a luminance threshold.
  static MonoBitmap fromRgba(Uint8List rgba, int srcWidth, int height, {int targetWidth = 0, int threshold = 140}) {
    final width = ((targetWidth == 0 ? srcWidth : targetWidth) + 7) ~/ 8 * 8;
    final bpr = width ~/ 8;
    final data = Uint8List(bpr * height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < srcWidth && x < width; x++) {
        final i = (y * srcWidth + x) * 4;
        final a = rgba[i + 3];
        // Transparent pixels count as white paper.
        final lum = a == 0 ? 255 : (rgba[i] * 299 + rgba[i + 1] * 587 + rgba[i + 2] * 114) ~/ 1000;
        if (lum < threshold) data[y * bpr + (x >> 3)] |= 0x80 >> (x & 7);
      }
    }
    return MonoBitmap(width: width, height: height, data: data);
  }
}

class EscPosRasterEncoder {
  const EscPosRasterEncoder({required this.cutMode, this.bandHeight = 128});

  final CutMode cutMode;

  /// Rows per GS v 0 command; small bands suit printers with little buffer.
  final int bandHeight;

  Uint8List encode(MonoBitmap image, {int feedLines = 3, bool cut = true, bool drawerPulse = false}) {
    final out = BytesBuilder(copy: false)..add(EscPos.init());
    final bpr = image.bytesPerRow;
    for (var y = 0; y < image.height; y += bandHeight) {
      final rows = (image.height - y) < bandHeight ? image.height - y : bandHeight;
      out.add([EscPos.gs, 0x76, 0x30, 0x00, bpr & 0xFF, (bpr >> 8) & 0xFF, rows & 0xFF, (rows >> 8) & 0xFF]);
      out.add(Uint8List.sublistView(image.data, y * bpr, (y + rows) * bpr));
    }
    out.add(EscPos.feed(feedLines));
    if (cut) out.add(EscPos.cut(cutMode));
    if (drawerPulse) out.add(EscPos.drawerPulse());
    return out.toBytes();
  }
}

/// Plain-text preview of what a text-mode printer will produce (used for the
/// on-screen receipt preview and tests).
List<String> previewLines(List<PrintOp> ops, int charsPerLine) {
  final out = <String>[];
  for (final op in ops) {
    switch (op) {
      case PText(:final text, :final align, :final big):
        final width = big ? charsPerLine ~/ 2 : charsPerLine;
        for (final l in wrapText(text, width)) {
          out.add(big ? alignLine(l.split('').join(' '), charsPerLine, align) : alignLine(l, charsPerLine, align));
        }
      case PColumns(:final left, :final right, :final big):
        if (big) {
          final width = charsPerLine ~/ 2;
          out.addAll(columnsToLines(left, right, width).map((l) => l.split('').join(' ')));
        } else {
          out.addAll(columnsToLines(left, right, charsPerLine));
        }
      case PRule(:final char):
        out.add(char * charsPerLine);
      case PFeed(:final lines):
        for (var i = 0; i < lines; i++) {
          out.add('');
        }
      case PCut():
        out.add('✂ ${'- ' * (charsPerLine ~/ 2 - 1)}');
      case PDrawerPulse():
        break;
    }
  }
  return out;
}
