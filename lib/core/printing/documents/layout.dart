/// Turns documents into device-neutral print operations. Text and raster
/// encoders both consume these, so a receipt looks the same either way.
library;

import '../../money/money.dart';
import 'print_documents.dart';

enum PAlign { left, center, right }

sealed class PrintOp {
  const PrintOp();
}

class PText extends PrintOp {
  const PText(this.text, {this.align = PAlign.left, this.bold = false, this.big = false});
  final String text;
  final PAlign align;
  final bool bold;

  /// Double width + height.
  final bool big;
}

/// Left text (wrapped) with a right-aligned value on the first line.
class PColumns extends PrintOp {
  const PColumns(this.left, this.right, {this.bold = false, this.big = false});
  final String left;
  final String right;
  final bool bold;
  final bool big;
}

class PRule extends PrintOp {
  const PRule({this.char = '-'});
  final String char;
}

class PFeed extends PrintOp {
  const PFeed(this.lines);
  final int lines;
}

class PCut extends PrintOp {
  const PCut();
}

class PDrawerPulse extends PrintOp {
  const PDrawerPulse();
}

class LayoutOptions {
  const LayoutOptions({
    required this.charsPerLine,
    this.currencyLabel = 'INR',
    this.feedLines = 3,
    this.cut = true,
    this.drawerPulse = false,
  });

  final int charsPerLine;

  /// "INR" for code-page text, "₹" when rendering raster.
  final String currencyLabel;
  final int feedLines;
  final bool cut;
  final bool drawerPulse;
}

List<PrintOp> layoutReceipt(ReceiptDocument d, LayoutOptions o) {
  final money = CurrencyFormat.forCode(d.currencyCode);
  String amt(int v) => money.format(v, withSymbol: false);
  final ops = <PrintOp>[];
  if (d.copyLabel != null) ops.add(PText('*** ${d.copyLabel} ***', align: PAlign.center, bold: true));
  ops.add(PText(d.restaurantName, align: PAlign.center, bold: true, big: true));
  for (final h in d.headerLines) {
    ops.add(PText(h, align: PAlign.center));
  }
  ops.add(const PRule());
  ops.add(PText(d.title, align: PAlign.center, bold: true));
  ops.add(PColumns(d.number, d.dateTime));
  if (d.referenceLine != null) ops.add(PText(d.referenceLine!));
  for (final i in d.infoLines) {
    ops.add(PText(i));
  }
  ops.add(const PRule());
  for (final l in d.lines) {
    ops.add(PColumns('${l.quantity} x ${l.displayName}', amt(l.amount)));
    if (l.quantity > 1) ops.add(PText('    @ ${amt(l.unitPrice)}'));
    for (final m in l.modifiers) {
      ops.add(PText('    $m'));
    }
    if (l.note != null) ops.add(PText('    Note: ${l.note}'));
    if (l.discount > 0) ops.add(PColumns('    Discount', '-${amt(l.discount)}'));
  }
  ops.add(const PRule());
  for (final s in d.summary) {
    ops.add(PColumns(s.label, amt(s.amount), bold: s.emphasis));
  }
  ops.add(const PRule(char: '='));
  ops.add(PColumns('TOTAL ${o.currencyLabel}', amt(d.total), bold: true, big: true));
  ops.add(const PRule(char: '='));
  for (final p in d.payments) {
    ops.add(PColumns(p.label, amt(p.amount)));
  }
  if (d.footerLines.isNotEmpty) {
    ops.add(const PFeed(1));
    for (final f in d.footerLines) {
      ops.add(PText(f, align: PAlign.center));
    }
  }
  if (d.copyLabel != null) ops.add(PText('*** ${d.copyLabel} ***', align: PAlign.center, bold: true));
  _finish(ops, o);
  return ops;
}

List<PrintOp> layoutKot(KotDocument d, LayoutOptions o) {
  final money = CurrencyFormat.forCode(d.currencyCode);
  final ops = <PrintOp>[];
  if (d.copyLabel != null) ops.add(PText('*** ${d.copyLabel} ***', align: PAlign.center, bold: true));
  ops.add(PText(d.isCorrection ? 'KOT CORRECTION' : 'KITCHEN ORDER', align: PAlign.center, bold: true, big: true));
  ops.add(PColumns('KOT #${d.ticketNo}', d.dateTime));
  ops.add(PText(d.orderRef, bold: true, big: true));
  ops.add(PText('${d.orderTypeLabel} · ${d.staffName}'));
  if (d.reason != null) ops.add(PText('Reason: ${d.reason}', bold: true));
  ops.add(const PRule());
  for (final l in d.lines) {
    final qty = l.quantity < 0 ? 'CANCEL ${-l.quantity}' : '${l.quantity}';
    final price = d.showPrices && l.unitPrice != null
        ? money.format(l.unitPrice! * l.quantity.abs(), withSymbol: false)
        : '';
    ops.add(PColumns('$qty x ${l.displayName}', price, bold: true));
    for (final m in l.modifiers) {
      ops.add(PText('   + $m'));
    }
    if (l.note != null) ops.add(PText('   >> ${l.note}', bold: true));
  }
  ops.add(const PRule());
  if (d.copyLabel != null) ops.add(PText('*** ${d.copyLabel} ***', align: PAlign.center, bold: true));
  _finish(ops, o.copyWithoutDrawer());
  return ops;
}

List<PrintOp> layoutTestPage(TestPageDocument d, LayoutOptions o) {
  final ops = <PrintOp>[
    const PText('CaféDesk printer test', align: PAlign.center, bold: true, big: true),
    PText(d.printerName, align: PAlign.center),
    PText(d.dateTime, align: PAlign.center),
    PText('Paper ${d.paperWidthMm} mm · ${o.charsPerLine} characters per line'),
    const PRule(),
    PText('0123456789' * ((o.charsPerLine / 10).ceil())),
    const PColumns('Left column', 'Right'),
    const PColumns('A long item name that needs to wrap onto the next line', '1,234.50'),
    const PText('Bold text', bold: true),
    const PText('Big', big: true),
    PText('Currency: ${o.currencyLabel} 120.00'),
    const PRule(char: '='),
    const PText('If this page printed cleanly, the printer works.', align: PAlign.center),
  ];
  _finish(ops, o.copyWithoutDrawer());
  return ops;
}

void _finish(List<PrintOp> ops, LayoutOptions o) {
  ops.add(PFeed(o.feedLines));
  if (o.cut) ops.add(const PCut());
  if (o.drawerPulse) ops.add(const PDrawerPulse());
}

extension on LayoutOptions {
  LayoutOptions copyWithoutDrawer() => LayoutOptions(
    charsPerLine: charsPerLine,
    currencyLabel: currencyLabel,
    feedLines: feedLines,
    cut: cut,
    drawerPulse: false,
  );
}

List<PrintOp> layoutDocument(Object doc, LayoutOptions o) => switch (doc) {
  final ReceiptDocument r => layoutReceipt(r, o),
  final KotDocument k => layoutKot(k, o),
  final TestPageDocument t => layoutTestPage(t, o),
  _ => throw ArgumentError('Unknown document $doc'),
};

// ---- Plain-text wrapping (monospace) ----------------------------------------

/// Wraps [text] to [width] characters on word boundaries, splitting words
/// longer than a line.
List<String> wrapText(String text, int width) {
  if (width <= 0) return [text];
  final out = <String>[];
  for (final paragraph in text.split('\n')) {
    final leading = RegExp(r'^ *').stringMatch(paragraph)!;
    // Continuation lines keep a short indent (modifiers, notes).
    final indent = leading.length < width ~/ 2 ? leading : '';
    final words = paragraph.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) {
      out.add('');
      continue;
    }
    var line = indent;
    var hasWord = false;
    for (var w in words) {
      while (w.isNotEmpty) {
        final sep = hasWord ? ' ' : '';
        if (line.length + sep.length + w.length <= width) {
          line = '$line$sep$w';
          hasWord = true;
          w = '';
        } else if (hasWord) {
          out.add(line);
          line = indent;
          hasWord = false;
        } else {
          final room = width - line.length;
          out.add('$line${w.substring(0, room)}');
          w = w.substring(room);
          line = indent;
        }
      }
    }
    if (hasWord) out.add(line);
  }
  return out;
}

/// Monospace rendering of a two-column row: the right value sits on the first
/// line if it fits, otherwise on its own right-aligned line.
List<String> columnsToLines(String left, String right, int width) {
  if (right.isEmpty) return wrapText(left, width);
  final leftWidth = width - right.length - 1;
  if (leftWidth < 8) {
    return [...wrapText(left, width), right.padLeft(width)];
  }
  final lines = wrapText(left, leftWidth);
  final first = lines.first.padRight(leftWidth);
  return ['$first ${right.padLeft(width - leftWidth - 1)}', ...lines.skip(1)];
}

String alignLine(String text, int width, PAlign align) {
  if (text.length >= width) return text;
  return switch (align) {
    PAlign.left => text,
    PAlign.right => text.padLeft(width),
    PAlign.center => ' ' * ((width - text.length) ~/ 2) + text,
  };
}
