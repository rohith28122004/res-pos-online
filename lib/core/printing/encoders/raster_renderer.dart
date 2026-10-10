import 'dart:typed_data';
import 'dart:ui' as ui;

import '../documents/layout.dart';
import 'escpos.dart';

/// Result of rasterising a document: the bitmap plus the trailing paper
/// handling that the encoder applies after the image.
class RasterDocument {
  const RasterDocument({required this.bitmap, required this.feedLines, required this.cut, required this.drawerPulse});
  final MonoBitmap bitmap;
  final int feedLines;
  final bool cut;
  final bool drawerPulse;
}

/// Renders print ops to a 1-bit bitmap [dotsWidth] wide using the platform's
/// fonts. Used for scripts and symbols the printer code page lacks (₹, Tamil,
/// Devanagari...) and for the Windows driver-rendered path.
Future<RasterDocument> renderRaster(List<PrintOp> ops, {required int dotsWidth, String? fontFamily}) async {
  final width = (dotsWidth ~/ 8) * 8;
  final scale = width / 384.0;
  final baseSize = 21.0 * scale;
  final margin = 4.0 * scale;
  final contentWidth = width - margin * 2;

  // Split trailing paper handling from content.
  var end = ops.length;
  var feed = 0;
  var cut = false;
  var pulse = false;
  while (end > 0) {
    final op = ops[end - 1];
    if (op is PFeed) {
      feed += op.lines;
    } else if (op is PCut) {
      cut = true;
    } else if (op is PDrawerPulse) {
      pulse = true;
    } else {
      break;
    }
    end--;
  }

  ui.Paragraph para(
    String text, {
    required bool bold,
    required bool big,
    required ui.TextAlign align,
    required double maxWidth,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: align,
              fontFamily: fontFamily,
              fontSize: big ? baseSize * 1.6 : baseSize,
              fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
              height: 1.15,
            ),
          )
          ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF000000)))
          ..addText(text);
    return builder.build()..layout(ui.ParagraphConstraints(width: maxWidth));
  }

  final placed = <(ui.Paragraph, double, double)>[];
  final rules = <(double, String)>[];
  var y = margin;
  final lineGap = baseSize * 0.25;
  for (final op in ops.take(end)) {
    switch (op) {
      case PText(:final text, :final align, :final bold, :final big):
        final p = para(text, bold: bold, big: big, align: _align(align), maxWidth: contentWidth);
        placed.add((p, margin, y));
        y += p.height;
      case PColumns(:final left, :final right, :final bold, :final big):
        if (right.isEmpty) {
          final p = para(left, bold: bold, big: big, align: ui.TextAlign.left, maxWidth: contentWidth);
          placed.add((p, margin, y));
          y += p.height;
          break;
        }
        final r = para(right, bold: bold, big: big, align: ui.TextAlign.right, maxWidth: contentWidth);
        final rightWidth = r.longestLine.ceilToDouble();
        final leftWidth = contentWidth - rightWidth - baseSize * 0.6;
        if (leftWidth < contentWidth * 0.35) {
          final l = para(left, bold: bold, big: big, align: ui.TextAlign.left, maxWidth: contentWidth);
          placed.add((l, margin, y));
          y += l.height;
          placed.add((r, margin, y));
          y += r.height;
        } else {
          final l = para(left, bold: bold, big: big, align: ui.TextAlign.left, maxWidth: leftWidth);
          placed.add((l, margin, y));
          placed.add((r, margin, y));
          y += l.height > r.height ? l.height : r.height;
        }
      case PRule(:final char):
        rules.add((y + lineGap, char));
        y += lineGap * 2 + (char == '=' ? 3 * scale : 1.5 * scale);
      case PFeed(:final lines):
        y += lines * baseSize * 1.15;
      case PCut():
      case PDrawerPulse():
        break;
    }
  }
  final height = (y + margin).ceil();

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFFFFFFFF),
  );
  for (final (p, x, py) in placed) {
    canvas.drawParagraph(p, ui.Offset(x, py));
  }
  final black = ui.Paint()..color = const ui.Color(0xFF000000);
  for (final (ry, char) in rules) {
    final thickness = char == '=' ? 3 * scale : 1.5 * scale;
    if (char == '-') {
      // Dashed rule.
      for (var x = margin; x < width - margin; x += 8 * scale) {
        canvas.drawRect(ui.Rect.fromLTWH(x, ry, 5 * scale, thickness), black);
      }
    } else {
      canvas.drawRect(ui.Rect.fromLTWH(margin, ry, contentWidth, thickness), black);
    }
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  final rgba = Uint8List.view(bytes!.buffer);
  return RasterDocument(
    bitmap: MonoBitmap.fromRgba(rgba, width, height, targetWidth: width),
    feedLines: feed,
    cut: cut,
    drawerPulse: pulse,
  );
}

ui.TextAlign _align(PAlign a) => switch (a) {
  PAlign.left => ui.TextAlign.left,
  PAlign.center => ui.TextAlign.center,
  PAlign.right => ui.TextAlign.right,
};
