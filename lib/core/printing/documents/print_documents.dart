/// Printer-independent document models. These are what print jobs persist
/// (as JSON); layout and encoding happen at send time for the chosen printer.
/// They carry only data already decided by the pricing engine — native and
/// encoder code never calculates money.
library;

import 'dart:convert';

abstract final class DocumentType {
  static const receipt = 'receipt';
  static const kot = 'kot';
  static const refund = 'refund';
  static const test = 'test';
}

/// "COPY" for staff reprints, "REPRINT" for retries of an uncertain job.
abstract final class CopyLabel {
  static const copy = 'COPY';
  static const reprint = 'REPRINT';
}

class ReceiptLineDoc {
  const ReceiptLineDoc({
    required this.quantity,
    required this.name,
    required this.unitPrice,
    required this.amount,
    this.variant,
    this.modifiers = const [],
    this.discount = 0,
    this.note,
  });

  final int quantity;
  final String name;
  final String? variant;
  final List<String> modifiers;
  final int unitPrice;

  /// Line gross as entered (before discounts).
  final int amount;
  final int discount;
  final String? note;

  String get displayName => variant == null ? name : '$name ($variant)';

  Map<String, Object?> toJson() => {
    'q': quantity,
    'n': name,
    'v': variant,
    'm': modifiers,
    'u': unitPrice,
    'a': amount,
    'd': discount,
    'note': note,
  };

  static ReceiptLineDoc fromJson(Map<String, Object?> j) => ReceiptLineDoc(
    quantity: j['q']! as int,
    name: j['n']! as String,
    variant: j['v'] as String?,
    modifiers: [for (final m in (j['m'] as List<Object?>? ?? const [])) m! as String],
    unitPrice: j['u']! as int,
    amount: j['a']! as int,
    discount: (j['d'] as int?) ?? 0,
    note: j['note'] as String?,
  );
}

/// A label/amount row such as "Subtotal", "CGST 2.5%", "Rounding".
class AmountRow {
  const AmountRow(this.label, this.amount, {this.emphasis = false});
  final String label;
  final int amount;
  final bool emphasis;

  Map<String, Object?> toJson() => {'l': label, 'a': amount, if (emphasis) 'e': true};
  static AmountRow fromJson(Map<String, Object?> j) =>
      AmountRow(j['l']! as String, j['a']! as int, emphasis: (j['e'] as bool?) ?? false);
}

class ReceiptDocument {
  const ReceiptDocument({
    required this.title,
    required this.restaurantName,
    required this.headerLines,
    required this.number,
    required this.dateTime,
    required this.infoLines,
    required this.lines,
    required this.summary,
    required this.total,
    required this.payments,
    required this.footerLines,
    required this.currencyCode,
    this.copyLabel,
    this.referenceLine,
  });

  /// "RECEIPT" or "REFUND".
  final String title;
  final String restaurantName;
  final List<String> headerLines;
  final String number;
  final String dateTime;

  /// e.g. "Dine-in · T4", "Cashier: Asha".
  final List<String> infoLines;
  final List<ReceiptLineDoc> lines;
  final List<AmountRow> summary;
  final int total;

  /// Payments and change; for refunds, refund tenders.
  final List<AmountRow> payments;
  final List<String> footerLines;
  final String currencyCode;
  final String? copyLabel;

  /// For refunds: "Against receipt K7Q-000123".
  final String? referenceLine;

  ReceiptDocument withCopyLabel(String? label) => ReceiptDocument(
    title: title,
    restaurantName: restaurantName,
    headerLines: headerLines,
    number: number,
    dateTime: dateTime,
    infoLines: infoLines,
    lines: lines,
    summary: summary,
    total: total,
    payments: payments,
    footerLines: footerLines,
    currencyCode: currencyCode,
    copyLabel: label,
    referenceLine: referenceLine,
  );

  Map<String, Object?> toJson() => {
    'type': 'receipt',
    'title': title,
    'restaurant': restaurantName,
    'header': headerLines,
    'number': number,
    'dateTime': dateTime,
    'info': infoLines,
    'lines': [for (final l in lines) l.toJson()],
    'summary': [for (final s in summary) s.toJson()],
    'total': total,
    'payments': [for (final p in payments) p.toJson()],
    'footer': footerLines,
    'currency': currencyCode,
    'copy': copyLabel,
    'ref': referenceLine,
  };

  String encode() => jsonEncode(toJson());

  static ReceiptDocument fromJson(Map<String, Object?> j) => ReceiptDocument(
    title: j['title']! as String,
    restaurantName: j['restaurant']! as String,
    headerLines: _strings(j['header']),
    number: j['number']! as String,
    dateTime: j['dateTime']! as String,
    infoLines: _strings(j['info']),
    lines: [for (final l in j['lines']! as List<Object?>) ReceiptLineDoc.fromJson(_map(l))],
    summary: [for (final s in j['summary']! as List<Object?>) AmountRow.fromJson(_map(s))],
    total: j['total']! as int,
    payments: [for (final p in j['payments']! as List<Object?>) AmountRow.fromJson(_map(p))],
    footerLines: _strings(j['footer']),
    currencyCode: j['currency']! as String,
    copyLabel: j['copy'] as String?,
    referenceLine: j['ref'] as String?,
  );
}

class KotLineDoc {
  const KotLineDoc({
    required this.quantity,
    required this.name,
    this.variant,
    this.modifiers = const [],
    this.note,
    this.unitPrice,
  });

  /// Negative for cancellations on a correction ticket.
  final int quantity;
  final String name;
  final String? variant;
  final List<String> modifiers;
  final String? note;
  final int? unitPrice;

  String get displayName => variant == null ? name : '$name ($variant)';

  Map<String, Object?> toJson() => {
    'q': quantity,
    'n': name,
    'v': variant,
    'm': modifiers,
    'note': note,
    'u': unitPrice,
  };

  static KotLineDoc fromJson(Map<String, Object?> j) => KotLineDoc(
    quantity: j['q']! as int,
    name: j['n']! as String,
    variant: j['v'] as String?,
    modifiers: _strings(j['m']),
    note: j['note'] as String?,
    unitPrice: j['u'] as int?,
  );
}

class KotDocument {
  const KotDocument({
    required this.ticketNo,
    required this.kind,
    required this.orderRef,
    required this.orderTypeLabel,
    required this.dateTime,
    required this.staffName,
    required this.lines,
    required this.currencyCode,
    this.tableLabel,
    this.reason,
    this.showPrices = false,
    this.copyLabel,
  });

  final int ticketNo;

  /// "order" or "correction".
  final String kind;
  final String orderRef;
  final String orderTypeLabel;
  final String? tableLabel;
  final String dateTime;
  final String staffName;
  final String? reason;
  final List<KotLineDoc> lines;
  final bool showPrices;
  final String currencyCode;
  final String? copyLabel;

  bool get isCorrection => kind == 'correction';

  KotDocument withCopyLabel(String? label) => KotDocument(
    ticketNo: ticketNo,
    kind: kind,
    orderRef: orderRef,
    orderTypeLabel: orderTypeLabel,
    tableLabel: tableLabel,
    dateTime: dateTime,
    staffName: staffName,
    reason: reason,
    lines: lines,
    showPrices: showPrices,
    currencyCode: currencyCode,
    copyLabel: label,
  );

  Map<String, Object?> toJson() => {
    'type': 'kot',
    'ticketNo': ticketNo,
    'kind': kind,
    'orderRef': orderRef,
    'orderType': orderTypeLabel,
    'table': tableLabel,
    'dateTime': dateTime,
    'staff': staffName,
    'reason': reason,
    'lines': [for (final l in lines) l.toJson()],
    'showPrices': showPrices,
    'currency': currencyCode,
    'copy': copyLabel,
  };

  String encode() => jsonEncode(toJson());

  static KotDocument fromJson(Map<String, Object?> j) => KotDocument(
    ticketNo: j['ticketNo']! as int,
    kind: j['kind']! as String,
    orderRef: j['orderRef']! as String,
    orderTypeLabel: j['orderType']! as String,
    tableLabel: j['table'] as String?,
    dateTime: j['dateTime']! as String,
    staffName: j['staff']! as String,
    reason: j['reason'] as String?,
    lines: [for (final l in j['lines']! as List<Object?>) KotLineDoc.fromJson(_map(l))],
    showPrices: (j['showPrices'] as bool?) ?? false,
    currencyCode: (j['currency'] as String?) ?? 'INR',
    copyLabel: j['copy'] as String?,
  );
}

/// A printer self-test page.
class TestPageDocument {
  const TestPageDocument({required this.printerName, required this.dateTime, required this.paperWidthMm});
  final String printerName;
  final String dateTime;
  final int paperWidthMm;

  Map<String, Object?> toJson() => {
    'type': 'test',
    'printer': printerName,
    'dateTime': dateTime,
    'paper': paperWidthMm,
  };
  String encode() => jsonEncode(toJson());
  static TestPageDocument fromJson(Map<String, Object?> j) => TestPageDocument(
    printerName: j['printer']! as String,
    dateTime: j['dateTime']! as String,
    paperWidthMm: j['paper']! as int,
  );
}

/// Decodes any persisted payload.
Object decodeDocument(String payload) {
  final j = _map(jsonDecode(payload));
  return switch (j['type']) {
    'receipt' => ReceiptDocument.fromJson(j),
    'kot' => KotDocument.fromJson(j),
    'test' => TestPageDocument.fromJson(j),
    _ => throw FormatException('Unknown print document type ${j['type']}'),
  };
}

Map<String, Object?> _map(Object? o) => (o! as Map).cast<String, Object?>();
List<String> _strings(Object? o) => [for (final s in (o as List<Object?>? ?? const [])) s! as String];
