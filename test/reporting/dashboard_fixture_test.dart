import 'dart:convert';

import 'package:cafedesk/core/csv/csv.dart';
import 'package:cafedesk/core/pricing/pricing_engine.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/dashboard/application/export_service.dart';
import 'package:cafedesk/features/dashboard/application/report_service.dart';
import 'package:cafedesk/features/expenses/application/expense_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/refunds/application/refund_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Builds the hand-calculated fixture from docs/REPORT_DEFINITIONS.md through
/// the real services and checks every documented number.
void main() {
  late Harness h;
  late ReportService reports;
  late String shiftId;
  late String b4Id;

  setUpAll(() async {
    h = await Harness.create(); // 2026-10-05 09:00 IST
    reports = ReportService(h.ctx);
    final excl = await h.taxProfile('GST 5%', TaxMode.exclusive);
    final incl = await h.taxProfile('GST 5% incl', TaxMode.inclusive);
    final cat = await h.category('Cafe');
    final bakery = await h.category('Bakery');
    final coffee = await h.item(cat, 'Coffee', 10000, taxProfileId: excl);
    final sandwich = await h.item(cat, 'Sandwich', 20000);
    final cake = await h.item(bakery, 'Cake', 10500, taxProfileId: incl);
    shiftId = await h.openShift(float: 100000);
    final expenses = ExpenseService(h.ctx);

    // B1 — 2026-10-05 10:00, dine-in, 10% bill discount, cash 500 → change 131.
    h.setIst(2026, 10, 5, 10);
    final o1 = await h.orderWith({coffee: 2, sandwich: 1}, type: OrderType.dineIn);
    await h.orders.setBillDiscount(h.owner, o1, const Discount.percent(1000));
    final b1 = await h.pay(o1, [const TenderInput(method: PaymentMethod.cash, applied: 36900, tendered: 50000)]);

    // A cancelled order (nothing sent to the kitchen).
    h.setIst(2026, 10, 5, 11);
    final cancelled = await h.orderWith({sandwich: 1});
    await h.orders.cancelOrder(h.cashier, cancelled, reason: 'Customer left');

    // E1 drawer expense, drawer cash out.
    h.setIst(2026, 10, 5, 12);
    await expenses.addExpense(h.cashier, category: 'Milk & dairy', amount: 15000, paidFromDrawer: true);
    h.setIst(2026, 10, 5, 13);
    await h.shifts.recordCashMovement(h.cashier, cashIn: false, amount: 10000, reason: 'Bank deposit');

    // B2 — 23:30, takeaway, inclusive cake, UPI + card split.
    h.setIst(2026, 10, 5, 23, 30);
    final o2 = await h.orderWith({cake: 1});
    await h.pay(o2, [
      const TenderInput(method: PaymentMethod.upi, applied: 5500),
      const TenderInput(method: PaymentMethod.card, applied: 5000),
    ]);

    // B3 — 2026-10-06 02:30 local, before the 04:00 cutoff → business 10-05.
    h.setIst(2026, 10, 6, 2, 30);
    final o3 = await h.orderWith({sandwich: 1});
    await h.pay(o3, [const TenderInput(method: PaymentMethod.cash, applied: 20000)]);

    // B4 — 2026-10-06 11:00 delivery with ₹40 delivery charge, card.
    h.setIst(2026, 10, 6, 11);
    final o4 = await h.orderWith({coffee: 3}, type: OrderType.delivery);
    await h.orders.setDeliveryCharge(h.cashier, o4, 4000);
    b4Id = (await h.pay(o4, [const TenderInput(method: PaymentMethod.card, applied: 35500)])).billId;

    // R1 — 12:00, refund 1 of the 2 coffees on B1 (an older sale), cash.
    h.setIst(2026, 10, 6, 12);
    final refunds = RefundService(h.ctx);
    final state = await refunds.refundableState(b1.billId);
    final coffeeLine = state.lines.firstWhere((l) => l.line.itemName == 'Coffee').line.id;
    await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: b1.billId, operationId: 'r1', lineQuantities: {coffeeLine: 1}, reason: 'Spilled'),
    );

    // E2 rent (not drawer), E3 voided, drawer cash in.
    h.setIst(2026, 10, 6, 13);
    await expenses.addExpense(h.owner, category: 'Rent', amount: 50000, paidFromDrawer: false);
    h.setIst(2026, 10, 6, 13, 30);
    final e3 = await expenses.addExpense(
      h.cashier,
      category: 'Other',
      amount: 8000,
      paidFromDrawer: false,
      note: '=HYPERLINK("http://x")',
    );
    await expenses.voidExpense(h.owner, e3, reason: 'Duplicate');
    h.setIst(2026, 10, 6, 14);
    await h.shifts.recordCashMovement(h.cashier, cashIn: true, amount: 5000, reason: 'Change top-up');
  });
  tearDownAll(() => h.dispose());

  BusinessDateRange day(int d) => BusinessDateRange(BusinessDate(2026, 10, d), BusinessDate(2026, 10, d + 1));

  test('2026-10-05 matches the hand calculation', () async {
    final d = await reports.dashboard(h.owner, day(5));
    expect(d.billCount, 3);
    expect(d.billsTotal, 67400);
    expect(d.averageBill, 22467);
    expect(d.itemsGrossEx, 70000);
    expect(d.itemsDiscountEx, 4000);
    expect(d.netItemSales, 66000);
    expect(d.chargesNetEx, 0);
    expect(d.taxCollected, 1400);
    expect(d.taxReversed, 0);
    expect(d.netBilledValue, 67400);
    expect(d.receiptsByMethod, {'cash': 56900, 'upi': 5500, 'card': 5000});
    expect(d.refundsByMethod, isEmpty);
    expect(d.expensesTotal, 15000);
    expect(d.drawerExpenses, 15000);
    expect(d.operatingSurplusEstimate, 51000);
    expect(d.netCashMovement, 31900);
    expect(d.cancellations, 1);
    expect(
      {for (final t in d.orderTypes) t.orderType: (t.count, t.total)},
      {'dine_in': (1, 36900), 'takeaway': (2, 30500)},
    );
    expect(d.hourly[2], 20000);
    expect(d.hourly[10], 36900);
    expect(d.hourly[23], 10500);
    final top = {for (final i in d.topItems) i.name: (i.netQuantity, i.netSales)};
    expect(top, {'Sandwich': (2, 38000), 'Coffee': (2, 18000), 'Cake': (1, 10000)});
  });

  test('2026-10-06: an old-sale refund lands on its issue date', () async {
    final d = await reports.dashboard(h.owner, day(6));
    expect(d.billCount, 1);
    expect(d.billsTotal, 35500);
    expect(d.averageBill, 35500);
    expect(d.itemsGrossEx, 30000);
    expect(d.itemsDiscountEx, 0);
    expect(d.refundDiscountEx, 1000);
    expect(d.netItemSales, 21000);
    expect(d.chargesNetEx, 4000);
    expect(d.refundChargesNetEx, 0);
    expect(d.taxCollected, 1500);
    expect(d.taxReversed, 450);
    expect(d.refundCount, 1);
    expect(d.refundsTotal, 9450);
    expect(d.netBilledValue, 26050);
    expect(d.receiptsByMethod, {'card': 35500});
    expect(d.refundsByMethod, {'cash': 9450});
    expect(d.expensesTotal, 50000);
    expect(d.drawerExpenses, 0);
    expect(d.operatingSurplusEstimate, -25000);
    expect(d.netCashMovement, -4450);
    expect(d.topItems.single.name, 'Coffee');
    expect(d.topItems.single.netQuantity, 2);
    expect(d.topItems.single.netSales, 21000);
    expect(d.refunds.single.receiptNo, 'TST-000001');
  });

  test('both days', () async {
    final d = await reports.dashboard(h.owner, BusinessDateRange(BusinessDate(2026, 10, 5), BusinessDate(2026, 10, 7)));
    expect(d.billCount, 4);
    expect(d.billsTotal, 102900);
    expect(d.averageBill, 25725);
    expect(d.netItemSales, 87000);
    expect(d.netBilledValue, 93450);
    expect(d.operatingSurplusEstimate, 26000);
    expect(d.daily.map((p) => p.netBilled), [67400, 26050]);
  });

  test('shift drawer expected cash', () async {
    final s = await h.shifts.summary(shiftId);
    expect(s.expectedCash, 127450);
    expect(s.cashReceipts, 56900);
    expect(s.cashRefunds, 9450);
    expect(s.cashIn, 5000);
    expect(s.cashOut, 10000);
    expect(s.drawerExpenses, 15000);
  });

  test('empty and negative periods are honest', () async {
    final empty = await reports.dashboard(h.owner, day(20));
    expect(empty.isEmpty, isTrue);
    expect(empty.averageBill, 0);

    h.setIst(2026, 10, 7, 10);
    final refunds = RefundService(h.ctx);
    final st = await refunds.refundableState(b4Id);
    await refunds.issueRefund(
      h.owner,
      RefundRequest(
        billId: b4Id,
        operationId: 'r-b4',
        lineQuantities: {for (final l in st.lines) l.line.id: l.remaining},
        chargeIds: [for (final c in st.charges) c.charge.id],
        reason: 'Order never arrived',
      ),
    );
    final d = await reports.dashboard(h.owner, day(7));
    expect(d.billCount, 0);
    expect(d.netBilledValue, -35500);
    expect(d.refundChargesNetEx, 4000);
  });

  test('ledger rows per day reconcile with the dashboard', () async {
    final rows = await reports.ledger(h.owner, BusinessDateRange(BusinessDate(2026, 10, 5), BusinessDate(2026, 10, 7)));
    expect(rows.length, 2);
    expect(rows[0].billsTotal, 67400);
    expect(rows[1].netBilled, 26050);
    expect(rows[1].netCash, -4450);
  });

  test('CSV exports follow the date filter and neutralise formulas', () async {
    final exports = ExportService(h.ctx);
    final bills = await exports.export(h.owner, ExportKind.bills, day(5));
    final text = utf8.decode(bills.bytes.sublist(3));
    expect(bills.rowCount, 3);
    expect(text, contains('TST-000001'));
    expect(text, isNot(contains('TST-000004')));
    expect(text, contains('369.00'));
    final exp = await exports.export(h.owner, ExportKind.expenses, day(6));
    final expText = utf8.decode(exp.bytes.sublist(3));
    expect(expText, contains("\"'=HYPERLINK(\"\"http://x\"\")\""));
    expect(expText, isNot(contains(',=HYPERLINK')));
    final refundsCsv = utf8.decode((await exports.export(h.owner, ExportKind.refunds, day(6))).bytes.sublist(3));
    expect(refundsCsv, contains('94.50'));
    expect(refundsCsv, contains('2026-10-05'), reason: 'original sale date column');
  });

  test('every export kind produces well-formed CSV for the range', () async {
    final exports = ExportService(h.ctx);
    final both = BusinessDateRange(BusinessDate(2026, 10, 5), BusinessDate(2026, 10, 7));
    for (final kind in ExportKind.values) {
      final f = await exports.export(h.owner, kind, both);
      final rows = parseCsv(utf8.decode(f.bytes.sublist(3)));
      expect(rows.first.single, contains('not a statutory tax document'), reason: kind.name);
      expect(
        rows[1],
        containsAll(['range_start', '2026-10-05', 'range_end_exclusive', '2026-10-07']),
        reason: kind.name,
      );
      final header = rows[2];
      for (final r in rows.skip(3)) {
        expect(r.length, header.length, reason: '${kind.name} row width');
      }
      expect(f.fileName, startsWith('cafedesk_${kind.fileStem}_2026-10-05_to_2026-10-06'));
    }
  });

  test('cashiers cannot read reports or export', () async {
    await expectLater(() => reports.dashboard(h.cashier, day(5)), throwsA(anything));
    await expectLater(() => ExportService(h.ctx).export(h.cashier, ExportKind.bills, day(5)), throwsA(anything));
  });
}
