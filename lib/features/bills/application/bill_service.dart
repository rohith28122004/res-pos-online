import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/money/money.dart';
import '../../../core/pricing/tax.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';
import '../../orders/domain/order_models.dart';
import '../domain/payment_method.dart';

/// Restaurant identity frozen onto each bill so old receipts reproduce
/// exactly, whatever later happens to settings.
class RestaurantSnapshot {
  const RestaurantSnapshot({
    required this.name,
    required this.address,
    this.phone,
    this.taxRegistrationId,
    this.header,
    required this.footer,
  });

  final String name;
  final String address;
  final String? phone;
  final String? taxRegistrationId;
  final String? header;
  final String footer;

  static RestaurantSnapshot of(RestaurantSettingsRow s) => RestaurantSnapshot(
    name: s.name,
    address: s.address,
    phone: s.phone,
    taxRegistrationId: s.taxRegistrationId,
    header: s.receiptHeader,
    footer: s.receiptFooter,
  );

  String encode() => jsonEncode({
    'name': name,
    'address': address,
    'phone': phone,
    'taxId': taxRegistrationId,
    'header': header,
    'footer': footer,
  });

  static RestaurantSnapshot decode(String text) {
    final j = (jsonDecode(text) as Map).cast<String, Object?>();
    return RestaurantSnapshot(
      name: j['name']! as String,
      address: (j['address'] as String?) ?? '',
      phone: j['phone'] as String?,
      taxRegistrationId: j['taxId'] as String?,
      header: j['header'] as String?,
      footer: (j['footer'] as String?) ?? '',
    );
  }

  List<String> get headerLines => [
    ...address.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty),
    if (phone != null) 'Ph: $phone',
    if (taxRegistrationId != null) 'Tax ID: $taxRegistrationId',
    ?header,
  ];
}

class BillDetail {
  const BillDetail({
    required this.bill,
    required this.lines,
    required this.charges,
    required this.taxComponents,
    required this.payments,
    required this.refunds,
  });

  final BillRow bill;
  final List<BillLineRow> lines;
  final List<BillChargeRow> charges;
  final List<BillTaxComponentRow> taxComponents;
  final List<PaymentRow> payments;
  final List<RefundRow> refunds;

  int get refundedTotal => refunds.fold(0, (a, r) => a + r.total);
}

class BillSearchQuery {
  const BillSearchQuery({this.text, this.range, this.method, this.limit = 200});

  /// Receipt number fragment or table label.
  final String? text;
  final BusinessDateRange? range;
  final PaymentMethod? method;
  final int limit;
}

class BillListItem {
  const BillListItem({required this.bill, required this.methods, required this.refunded});
  final BillRow bill;
  final List<String> methods;
  final int refunded;
}

class BillService {
  BillService(this.ctx) : _printJobs = PrintJobWriter(ctx);

  final ServiceContext ctx;
  final PrintJobWriter _printJobs;
  AppDatabase get _db => ctx.db;

  Future<BillDetail> detail(String billId) async {
    final bill = await (_db.select(_db.bills)..where((b) => b.id.equals(billId))).getSingleOrNull();
    if (bill == null) throw const NotFoundException('Bill not found');
    return BillDetail(
      bill: bill,
      lines:
          await (_db.select(_db.billLines)
                ..where((l) => l.billId.equals(billId))
                ..orderBy([(l) => OrderingTerm(expression: l.sortOrder)]))
              .get(),
      charges: await (_db.select(_db.billCharges)..where((c) => c.billId.equals(billId))).get(),
      taxComponents: await (_db.select(_db.billTaxComponents)..where((c) => c.billId.equals(billId))).get(),
      payments: await (_db.select(_db.payments)..where((p) => p.billId.equals(billId))).get(),
      refunds:
          await (_db.select(_db.refunds)
                ..where((r) => r.billId.equals(billId))
                ..orderBy([(r) => OrderingTerm(expression: r.createdAt)]))
              .get(),
    );
  }

  Future<List<BillListItem>> search(Actor actor, BillSearchQuery query) async {
    actor.require(Permission.viewBills);
    final q = _db.select(_db.bills)
      ..orderBy([(b) => OrderingTerm(expression: b.createdAt, mode: OrderingMode.desc)])
      ..limit(query.limit);
    final text = query.text?.trim();
    q.where((b) {
      Expression<bool> cond = const Constant(true);
      if (text != null && text.isNotEmpty) {
        final like = '%${text.replaceAll('%', '').replaceAll('_', '')}%';
        cond = cond & (b.receiptNo.like(like) | b.tableLabel.like(like) | b.orderNo.cast<String>().equals(text));
      }
      if (query.range != null) {
        cond =
            cond &
            b.businessDate.isBiggerOrEqualValue(query.range!.start.key) &
            b.businessDate.isSmallerThanValue(query.range!.endExclusive.key);
      }
      if (query.method != null) {
        cond =
            cond &
            existsQuery(
              _db.select(_db.payments)..where((p) => p.billId.equalsExp(b.id) & p.method.equals(query.method!.code)),
            );
      }
      return cond;
    });
    final bills = await q.get();
    if (bills.isEmpty) return const [];
    final ids = bills.map((b) => b.id).toList();
    final payments = await (_db.select(_db.payments)..where((p) => p.billId.isIn(ids))).get();
    final refunds = await (_db.select(_db.refunds)..where((r) => r.billId.isIn(ids))).get();
    final methods = <String, Set<String>>{};
    for (final p in payments) {
      methods.putIfAbsent(p.billId, () => {}).add(PaymentMethod.parse(p.method).label);
    }
    final refunded = <String, int>{};
    for (final r in refunds) {
      refunded.update(r.billId, (v) => v + r.total, ifAbsent: () => r.total);
    }
    return [
      for (final b in bills)
        BillListItem(bill: b, methods: (methods[b.id] ?? {}).toList()..sort(), refunded: refunded[b.id] ?? 0),
    ];
  }

  /// Builds the receipt purely from the bill's immutable rows.
  Future<ReceiptDocument> receiptDocument(String billId, {String? copyLabel}) async {
    final d = await detail(billId);
    return buildReceiptDocument(d, copyLabel: copyLabel);
  }

  static ReceiptDocument buildReceiptDocument(BillDetail d, {String? copyLabel}) {
    final b = d.bill;
    final restaurant = RestaurantSnapshot.decode(b.restaurantJson);
    final calendar = BusinessCalendar(timeZone: b.timeZone, cutoffMinutes: 0);
    final lineModes = {for (final l in d.lines) l.id: l.taxMode};
    final chargeModes = {for (final c in d.charges) c.id: c.taxMode};

    final summary = <AmountRow>[AmountRow('Subtotal', b.itemsGrossEntered)];
    final lineDiscounts = d.lines.fold<int>(0, (a, l) => a + l.lineDiscountEntered);
    final billDiscount = d.lines.fold<int>(0, (a, l) => a + l.billDiscountEntered);
    if (lineDiscounts > 0) summary.add(AmountRow('Item discounts', -lineDiscounts));
    if (billDiscount > 0) summary.add(AmountRow('Bill discount', -billDiscount));
    for (final c in d.charges) {
      summary.add(AmountRow(c.label, c.amountEntered));
    }
    // Exclusive taxes are added to the total; inclusive taxes are shown for
    // information only because they are already inside the prices.
    final added = <(String, int), int>{};
    final included = <(String, int), int>{};
    for (final t in d.taxComponents) {
      final mode = t.billLineId != null ? lineModes[t.billLineId] : chargeModes[t.billChargeId];
      final target = mode == TaxMode.inclusive.name ? included : added;
      target.update((t.name, t.rateBps), (v) => v + t.amount, ifAbsent: () => t.amount);
    }
    for (final e in added.entries) {
      summary.add(AmountRow('${e.key.$1} ${formatBps(e.key.$2)}', e.value));
    }
    if (b.roundingAdjustment != 0) summary.add(AmountRow('Rounding', b.roundingAdjustment));

    final payments = <AmountRow>[];
    for (final p in d.payments) {
      payments.add(AmountRow(PaymentMethod.parse(p.method).label, p.applied));
      if (p.changeGiven > 0) {
        payments.add(AmountRow('Cash received', p.tendered));
        payments.add(AmountRow('Change', p.changeGiven));
      }
    }
    final footer = <String>[
      for (final e in included.entries)
        'Prices include ${e.key.$1} ${formatBps(e.key.$2)}: ${CurrencyFormat.forCode(b.currencyCode).plain(e.value)}',
      ...restaurant.footer.split('\n').where((l) => l.trim().isNotEmpty),
    ];

    return ReceiptDocument(
      title: 'RECEIPT',
      restaurantName: restaurant.name,
      headerLines: restaurant.headerLines,
      number: b.receiptNo,
      dateTime: calendar.formatLocal(DateTime.fromMillisecondsSinceEpoch(b.createdAt, isUtc: true)),
      infoLines: [
        [
          OrderType.parse(b.orderType).label,
          if (b.tableLabel != null) b.tableLabel!,
          'Order #${b.orderNo}',
        ].join(' · '),
        'Cashier: ${b.staffName}',
        if (b.customerName != null) 'Customer: ${b.customerName}',
        if (b.guestCount != null) 'Guests: ${b.guestCount}',
      ],
      lines: [
        for (final l in d.lines)
          ReceiptLineDoc(
            quantity: l.quantity,
            name: l.itemName,
            variant: l.variantName,
            // Modifier prices are already inside the unit price.
            modifiers: [for (final m in LineModifier.decodeList(l.modifiersJson)) '+ ${m.name}'],
            unitPrice: l.unitPriceEntered,
            amount: l.grossEntered,
            discount: l.lineDiscountEntered,
            note: l.note,
          ),
      ],
      summary: summary,
      total: b.total,
      payments: payments,
      footerLines: footer,
      currencyCode: b.currencyCode,
      copyLabel: copyLabel,
    );
  }

  /// Staff reprint: always marked COPY.
  Future<List<String>> reprint(Actor actor, String billId) async {
    actor.require(Permission.reprint);
    final doc = await receiptDocument(billId, copyLabel: CopyLabel.copy);
    return _db.transaction(() async {
      final ids = await _printJobs.enqueueForRole(
        role: PrinterRole.receipt,
        documentType: DocumentType.receipt,
        documentRef: billId,
        payloadJson: doc.encode(),
        copyLabel: CopyLabel.copy,
        createdBy: actor.staffId,
      );
      await ctx.audit(actor, 'bill.reprinted', entityType: 'bill', entityId: billId, details: {'jobs': ids.length});
      return ids;
    });
  }
}
