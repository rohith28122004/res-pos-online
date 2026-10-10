import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/pricing/pricing_engine.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/refunds/application/refund_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  late String coffee;
  late String sandwich;
  late RefundService refunds;

  setUp(() async {
    h = await Harness.create();
    final excl = await h.taxProfile('GST 5%', TaxMode.exclusive);
    final cat = await h.category('Cafe');
    coffee = await h.item(cat, 'Coffee', 10000, taxProfileId: excl);
    sandwich = await h.item(cat, 'Sandwich', 20000);
    await h.openShift();
    refunds = RefundService(h.ctx);
  });
  tearDown(() => h.dispose());

  Future<String> billB1() async {
    final id = await h.orderWith({coffee: 2, sandwich: 1});
    await h.orders.setBillDiscount(h.owner, id, const Discount.percent(1000));
    return (await h.pay(id, [const TenderInput(method: PaymentMethod.cash, applied: 36900, tendered: 50000)])).billId;
  }

  test('partial refund reverses captured, discounted amounts', () async {
    final billId = await billB1();
    final state = await refunds.refundableState(billId);
    final coffeeLine = state.lines.firstWhere((l) => l.line.itemName == 'Coffee');
    final r = await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: billId, operationId: 'r1', lineQuantities: {coffeeLine.line.id: 1}, reason: 'Spilled'),
    );
    expect(r.total, 9450);
    final row = await (h.db.select(h.db.refunds)..where((x) => x.id.equals(r.refundId))).getSingle();
    expect(row.itemsNetEx, 9000);
    expect(row.itemsDiscountEx, 1000);
    expect(row.taxTotal, 450);
    expect(row.billId, billId);
    final pays = await (h.db.select(h.db.refundPayments)..where((p) => p.refundId.equals(r.refundId))).get();
    expect(pays.single.method, 'cash');
    expect(pays.single.amount, 9450);
  });

  test('cumulative refunds can never exceed quantities or the total', () async {
    final billId = await billB1();
    var state = await refunds.refundableState(billId);
    final coffeeLine = state.lines.firstWhere((l) => l.line.itemName == 'Coffee').line.id;
    final sandwichLine = state.lines.firstWhere((l) => l.line.itemName == 'Sandwich').line.id;
    await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: billId, operationId: 'a', lineQuantities: {coffeeLine: 1}, reason: 'x'),
    );
    await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: billId, operationId: 'b', lineQuantities: {coffeeLine: 1}, reason: 'x'),
    );
    await expectLater(
      () => refunds.issueRefund(
        h.owner,
        RefundRequest(billId: billId, operationId: 'c', lineQuantities: {coffeeLine: 1}, reason: 'x'),
      ),
      throwsA(isA<ValidationException>()),
    );
    await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: billId, operationId: 'd', lineQuantities: {sandwichLine: 1}, reason: 'x'),
    );
    state = await refunds.refundableState(billId);
    expect(state.refundedTotal, 36900, reason: 'full refund matches the bill exactly');
    expect(state.fullyRefunded, isTrue);
    expect(state.refundableByMethod['cash'], 0);
  });

  test('retrying the same refund operation does not refund twice', () async {
    final billId = await billB1();
    final line = (await refunds.refundableState(billId)).lines.first.line.id;
    final req = RefundRequest(billId: billId, operationId: 'same', lineQuantities: {line: 1}, reason: 'x');
    final a = await refunds.issueRefund(h.owner, req);
    final b = await refunds.issueRefund(h.owner, req);
    expect(b.refundId, a.refundId);
    expect(b.alreadyIssued, isTrue);
    expect(await h.count(h.db.refunds), 1);
  });

  test('cashier needs owner approval; kitchen cannot refund at all', () async {
    final billId = await billB1();
    final line = (await refunds.refundableState(billId)).lines.first.line.id;
    await expectLater(
      () => refunds.issueRefund(
        h.cashier,
        RefundRequest(billId: billId, operationId: 'x', lineQuantities: {line: 1}, reason: 'x'),
      ),
      throwsA(isA<ApprovalRequiredException>()),
    );
    await expectLater(
      () => refunds.issueRefund(
        h.kitchen,
        RefundRequest(billId: billId, operationId: 'y', lineQuantities: {line: 1}, reason: 'x'),
      ),
      throwsA(isA<PermissionDeniedException>()),
    );
    final r = await refunds.issueRefund(
      h.cashier,
      RefundRequest(
        billId: billId,
        operationId: 'z',
        lineQuantities: {line: 1},
        reason: 'x',
        approval: await h.approval(),
      ),
    );
    final row = await (h.db.select(h.db.refunds)..where((x) => x.id.equals(r.refundId))).getSingle();
    expect(row.authorizedByName, 'Olivia Owner');
    expect(row.createdByName, 'Cara Cashier');
  });

  test('refund tender cannot exceed what each method paid', () async {
    final id = await h.orderWith({sandwich: 2});
    final billId = (await h.pay(id, [
      const TenderInput(method: PaymentMethod.upi, applied: 30000),
      const TenderInput(method: PaymentMethod.card, applied: 10000),
    ])).billId;
    final line = (await refunds.refundableState(billId)).lines.single.line.id;
    await expectLater(
      () => refunds.issueRefund(
        h.owner,
        RefundRequest(
          billId: billId,
          operationId: 'q',
          lineQuantities: {line: 1},
          tenders: const {'card': 20000},
          reason: 'x',
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    final ok = await refunds.issueRefund(
      h.owner,
      RefundRequest(
        billId: billId,
        operationId: 'q2',
        lineQuantities: {line: 1},
        tenders: const {'upi': 15000, 'card': 5000},
        reason: 'x',
      ),
    );
    expect(ok.total, 20000);
  });

  test('original bill is untouched by refunds', () async {
    final billId = await billB1();
    final before = await (h.db.select(h.db.bills)..where((b) => b.id.equals(billId))).getSingle();
    final line = (await refunds.refundableState(billId)).lines.first.line.id;
    await refunds.issueRefund(
      h.owner,
      RefundRequest(billId: billId, operationId: 'r', lineQuantities: {line: 1}, reason: 'x'),
    );
    final after = await (h.db.select(h.db.bills)..where((b) => b.id.equals(billId))).getSingle();
    expect(after, before);
  });
}
