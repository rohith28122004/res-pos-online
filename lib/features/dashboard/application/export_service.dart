import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/csv/csv.dart';
import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';
import '../../bills/domain/payment_method.dart';
import 'report_service.dart';

enum ExportKind {
  bills('bills', 'Bills'),
  lines('bill_lines', 'Bill line items'),
  payments('payments', 'Payments'),
  refunds('refunds', 'Refunds'),
  refundLines('refund_lines', 'Refund line items'),
  expenses('expenses', 'Expenses'),
  shifts('shifts', 'Shift summaries'),
  ledger('daily_ledger', 'Daily ledger');

  const ExportKind(this.fileStem, this.label);
  final String fileStem;
  final String label;
}

class CsvExport {
  const CsvExport({required this.fileName, required this.bytes, required this.rowCount});
  final String fileName;
  final Uint8List bytes;
  final int rowCount;
}

/// CSV exports for a business-date range. Amounts are decimal strings, dates
/// carry explicit business-date, local time and UTC columns, files are UTF-8
/// with BOM, and text cells are guarded against spreadsheet formulas.
/// Labelled as operational reports, not statutory tax documents.
class ExportService {
  ExportService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  Future<CsvExport> export(Actor actor, ExportKind kind, BusinessDateRange range) async {
    actor.require(Permission.exportData);
    final settings = await ctx.settings();
    final money = CurrencyFormat.forCode(settings.currencyCode);
    final calendar = await ctx.calendar();
    String m(int v) => money.plain(v);
    String local(int ms) =>
        calendar.formatLocal(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true), withSeconds: true);
    String utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toIso8601String();
    String offset(int ms) => calendar.offsetLabel(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
    final tzName = settings.timeZone;
    Expression<bool> dateFilter(GeneratedColumn<String> col) =>
        col.isBiggerOrEqualValue(range.start.key) & col.isSmallerThanValue(range.endExclusive.key);

    final rows = <List<Object?>>[];
    switch (kind) {
      case ExportKind.bills:
        rows.add([
          'receipt_no',
          'business_date',
          'created_local',
          'utc_offset',
          'time_zone',
          'created_utc',
          'order_no',
          'order_type',
          'table',
          'staff',
          'items',
          'items_gross_ex',
          'items_discount_ex',
          'items_net_ex',
          'charges_net_ex',
          'tax',
          'rounding',
          'total',
          'change_given',
          'currency',
        ]);
        final bills =
            await (_db.select(_db.bills)
                  ..where((b) => dateFilter(b.businessDate))
                  ..orderBy([(b) => OrderingTerm(expression: b.createdAt)]))
                .get();
        for (final b in bills) {
          rows.add([
            b.receiptNo,
            b.businessDate,
            local(b.createdAt),
            offset(b.createdAt),
            tzName,
            utc(b.createdAt),
            b.orderNo,
            b.orderType,
            b.tableLabel,
            b.staffName,
            b.itemCount,
            _n(m(b.itemsGrossEx)),
            _n(m(b.itemsDiscountEx)),
            _n(m(b.itemsNetEx)),
            _n(m(b.chargesNetEx)),
            _n(m(b.taxTotal)),
            _n(m(b.roundingAdjustment)),
            _n(m(b.total)),
            _n(m(b.changeTotal)),
            b.currencyCode,
          ]);
        }
      case ExportKind.lines:
        rows.add([
          'receipt_no',
          'business_date',
          'item',
          'variant',
          'category',
          'modifiers',
          'quantity',
          'unit_price_entered',
          'gross_entered',
          'line_discount_entered',
          'bill_discount_entered',
          'gross_ex',
          'discount_ex',
          'net_ex',
          'tax_mode',
          'tax_rate_percent',
          'tax',
          'line_total',
        ]);
        final q = _db.select(_db.billLines).join([innerJoin(_db.bills, _db.bills.id.equalsExp(_db.billLines.billId))])
          ..where(dateFilter(_db.bills.businessDate))
          ..orderBy([OrderingTerm(expression: _db.bills.createdAt), OrderingTerm(expression: _db.billLines.sortOrder)]);
        for (final r in await q.get()) {
          final b = r.readTable(_db.bills);
          final l = r.readTable(_db.billLines);
          final mods = (jsonDecode(l.modifiersJson) as List<Object?>).map((e) => (e! as Map)['name']).join('; ');
          rows.add([
            b.receiptNo,
            b.businessDate,
            l.itemName,
            l.variantName,
            l.categoryName,
            mods,
            l.quantity,
            _n(m(l.unitPriceEntered)),
            _n(m(l.grossEntered)),
            _n(m(l.lineDiscountEntered)),
            _n(m(l.billDiscountEntered)),
            _n(m(l.grossEx)),
            _n(m(l.discountEx)),
            _n(m(l.netEx)),
            l.taxMode,
            _n(_pct(l.taxRateBps)),
            _n(m(l.tax)),
            _n(m(l.total)),
          ]);
        }
      case ExportKind.payments:
        rows.add([
          'receipt_no',
          'business_date',
          'created_local',
          'utc_offset',
          'method',
          'applied',
          'tendered',
          'change',
          'confirmed_by',
          'note',
        ]);
        final q = _db.select(_db.payments).join([innerJoin(_db.bills, _db.bills.id.equalsExp(_db.payments.billId))])
          ..where(dateFilter(_db.bills.businessDate))
          ..orderBy([OrderingTerm(expression: _db.payments.createdAt)]);
        for (final r in await q.get()) {
          final b = r.readTable(_db.bills);
          final p = r.readTable(_db.payments);
          rows.add([
            b.receiptNo,
            b.businessDate,
            local(p.createdAt),
            offset(p.createdAt),
            PaymentMethod.parse(p.method).label,
            _n(m(p.applied)),
            _n(m(p.tendered)),
            _n(m(p.changeGiven)),
            p.confirmedByName,
            p.method == 'cash' ? '' : 'Recorded manually; not verified by the app',
          ]);
        }
      case ExportKind.refunds:
        rows.add([
          'refund_no',
          'original_receipt_no',
          'original_business_date',
          'business_date',
          'created_local',
          'utc_offset',
          'reason',
          'authorized_by',
          'processed_by',
          'items_net_ex',
          'items_discount_ex',
          'charges_net_ex',
          'tax_reversed',
          'rounding',
          'total',
          'refunded_cash',
          'refunded_upi',
          'refunded_card',
        ]);
        final q = _db.select(_db.refunds).join([innerJoin(_db.bills, _db.bills.id.equalsExp(_db.refunds.billId))])
          ..where(dateFilter(_db.refunds.businessDate))
          ..orderBy([OrderingTerm(expression: _db.refunds.createdAt)]);
        final list = await q.get();
        final ids = list.map((r) => r.readTable(_db.refunds).id).toList();
        final pays = ids.isEmpty
            ? <RefundPaymentRow>[]
            : await (_db.select(_db.refundPayments)..where((p) => p.refundId.isIn(ids))).get();
        for (final r in list) {
          final rf = r.readTable(_db.refunds);
          final b = r.readTable(_db.bills);
          int by(String method) =>
              pays.where((p) => p.refundId == rf.id && p.method == method).fold(0, (a, p) => a + p.amount);
          rows.add([
            rf.refundNo,
            b.receiptNo,
            b.businessDate,
            rf.businessDate,
            local(rf.createdAt),
            offset(rf.createdAt),
            rf.reason,
            rf.authorizedByName,
            rf.createdByName,
            _n(m(rf.itemsNetEx)),
            _n(m(rf.itemsDiscountEx)),
            _n(m(rf.chargesNetEx)),
            _n(m(rf.taxTotal)),
            _n(m(rf.roundingAdjustment)),
            _n(m(rf.total)),
            _n(m(by('cash'))),
            _n(m(by('upi'))),
            _n(m(by('card'))),
          ]);
        }
      case ExportKind.refundLines:
        rows.add([
          'refund_no',
          'original_receipt_no',
          'business_date',
          'item',
          'variant',
          'quantity',
          'gross_ex',
          'discount_ex',
          'net_ex',
          'tax',
          'total',
        ]);
        final q =
            _db.select(_db.refundLines).join([
                innerJoin(_db.refunds, _db.refunds.id.equalsExp(_db.refundLines.refundId)),
                innerJoin(_db.billLines, _db.billLines.id.equalsExp(_db.refundLines.billLineId)),
                innerJoin(_db.bills, _db.bills.id.equalsExp(_db.refunds.billId)),
              ])
              ..where(dateFilter(_db.refunds.businessDate))
              ..orderBy([OrderingTerm(expression: _db.refunds.createdAt)]);
        for (final r in await q.get()) {
          final rf = r.readTable(_db.refunds);
          final rl = r.readTable(_db.refundLines);
          final bl = r.readTable(_db.billLines);
          final b = r.readTable(_db.bills);
          rows.add([
            rf.refundNo,
            b.receiptNo,
            rf.businessDate,
            bl.itemName,
            bl.variantName,
            rl.quantity,
            _n(m(rl.grossEx)),
            _n(m(rl.discountEx)),
            _n(m(rl.netEx)),
            _n(m(rl.tax)),
            _n(m(rl.total)),
          ]);
        }
      case ExportKind.expenses:
        rows.add([
          'business_date',
          'created_local',
          'utc_offset',
          'category',
          'amount',
          'paid_from_drawer',
          'note',
          'recorded_by',
          'voided',
          'void_reason',
        ]);
        final list =
            await (_db.select(_db.expenses)
                  ..where((e) => dateFilter(e.businessDate))
                  ..orderBy([(e) => OrderingTerm(expression: e.createdAt)]))
                .get();
        for (final e in list) {
          rows.add([
            e.businessDate,
            local(e.createdAt),
            offset(e.createdAt),
            e.category,
            _n(m(e.amount)),
            e.paidFromDrawer,
            e.note,
            e.createdByName,
            e.voidedAt != null,
            e.voidReason,
          ]);
        }
      case ExportKind.shifts:
        rows.add([
          'shift_business_date',
          'opened_local',
          'opened_by',
          'closed_local',
          'closed_by',
          'opening_float',
          'expected_cash',
          'counted_cash',
          'variance',
          'carried_open_orders',
          'note',
        ]);
        final shifts =
            await (_db.select(_db.shifts)
                  ..where((s) => dateFilter(s.businessDate))
                  ..orderBy([(s) => OrderingTerm(expression: s.openedAt)]))
                .get();
        for (final s in shifts) {
          final closures =
              await (_db.select(_db.shiftClosures)
                    ..where((c) => c.shiftId.equals(s.id))
                    ..orderBy([(c) => OrderingTerm(expression: c.closedAt)]))
                  .get();
          if (closures.isEmpty) {
            rows.add([
              s.businessDate,
              local(s.openedAt),
              s.openedByName,
              'open',
              '',
              _n(m(s.openingFloat)),
              '',
              '',
              '',
              '',
              '',
            ]);
          }
          for (final c in closures) {
            rows.add([
              s.businessDate,
              local(s.openedAt),
              s.openedByName,
              local(c.closedAt),
              c.closedByName,
              _n(m(s.openingFloat)),
              _n(m(c.expectedCash)),
              _n(m(c.countedCash)),
              _n(m(c.variance)),
              c.carriedOpenOrders,
              c.note,
            ]);
          }
        }
      case ExportKind.ledger:
        rows.add([
          'business_date',
          'bills',
          'bills_total',
          'net_item_sales_ex',
          'charges_ex',
          'tax_collected',
          'refunds_total',
          'tax_reversed',
          'net_billed_value',
          'cash_receipts',
          'upi_receipts',
          'card_receipts',
          'cash_refunds',
          'upi_refunds',
          'card_refunds',
          'expenses',
          'drawer_expenses',
          'drawer_cash_in',
          'drawer_cash_out',
          'net_cash_movement',
        ]);
        final ledger = await ReportService(ctx).ledger(actor, range);
        for (final l in ledger) {
          rows.add([
            l.date.key,
            l.billCount,
            _n(m(l.billsTotal)),
            _n(m(l.itemsNetEx - l.refundItemsNetEx)),
            _n(m(l.chargesNetEx)),
            _n(m(l.taxCollected)),
            _n(m(l.refundsTotal)),
            _n(m(l.taxReversed)),
            _n(m(l.netBilled)),
            _n(m(l.receiptsByMethod['cash'] ?? 0)),
            _n(m(l.receiptsByMethod['upi'] ?? 0)),
            _n(m(l.receiptsByMethod['card'] ?? 0)),
            _n(m(l.refundsByMethod['cash'] ?? 0)),
            _n(m(l.refundsByMethod['upi'] ?? 0)),
            _n(m(l.refundsByMethod['card'] ?? 0)),
            _n(m(l.expenses)),
            _n(m(l.drawerExpenses)),
            _n(m(l.cashIn)),
            _n(m(l.cashOut)),
            _n(m(l.netCash)),
          ]);
        }
    }
    // Header rows identify the report and its range.
    final out = <List<Object?>>[
      ['CaféDesk operational report — not a statutory tax document'],
      [
        'report',
        kind.label,
        'range_start',
        range.start.key,
        'range_end_exclusive',
        range.endExclusive.key,
        'time_zone',
        tzName,
      ],
      ...rows,
    ];
    await ctx.audit(
      actor,
      'export.csv',
      details: {'kind': kind.fileStem, 'from': range.start.key, 'to': range.endExclusive.key},
    );
    return CsvExport(
      fileName: 'cafedesk_${kind.fileStem}_${range.start.key}_to_${range.lastDay.key}.csv',
      bytes: encodeCsvBytes(out),
      rowCount: rows.length - 1,
    );
  }

  static CsvNumber _n(String decimal) => CsvNumber(decimal);

  static String _pct(int bps) {
    final whole = bps ~/ 100;
    final frac = (bps % 100).toString().padLeft(2, '0');
    return '$whole.$frac';
  }
}
