import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/pricing/pricing_engine.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/core/printing/documents/print_documents.dart';
import 'package:cafedesk/core/printing/queue/print_job_writer.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/features/bills/application/bill_service.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/checkout/application/checkout_service.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/settings/application/printer_service.dart';
import 'package:cafedesk/features/settings/application/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  late String coffee;
  late String sandwich;

  setUp(() async {
    h = await Harness.create();
    final excl = await h.taxProfile('GST 5%', TaxMode.exclusive);
    final cat = await h.category('Cafe');
    coffee = await h.item(cat, 'Coffee', 10000, taxProfileId: excl);
    sandwich = await h.item(cat, 'Sandwich', 20000);
    await h.openShift();
    await PrinterService(h.ctx).saveProfile(
      h.owner,
      PrinterProfileInput.defaults(
        paperWidthMm: 80,
        transport: TransportType.tcp,
      ).copyWithName('Counter', '192.168.1.50'),
    );
  });
  tearDown(() => h.dispose());

  test('finalizes atomically: bill, lines, payments, order closed, one print job', () async {
    final orderId = await h.orderWith({coffee: 2, sandwich: 1});
    await h.orders.setBillDiscount(h.owner, orderId, const Discount.percent(1000), reason: 'Regular');
    final r = await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 36900, tendered: 50000)]);
    expect(r.receiptNo, 'TST-000001');
    expect(r.total, 36900);
    expect(r.change, 13100);
    expect(r.printJobIds.length, 1);

    final detail = await BillService(h.ctx).detail(r.billId);
    expect(detail.lines.length, 2);
    expect(detail.bill.itemsNetEx, 36000);
    expect(detail.bill.taxTotal, 900);
    expect(detail.payments.single.applied, 36900);
    expect(detail.payments.single.tendered, 50000);
    expect(detail.taxComponents.map((c) => c.amount).toList()..sort(), [450, 450]);
    final order = await (h.db.select(h.db.orders)..where((o) => o.id.equals(orderId))).getSingle();
    expect(order.status, OrderStatus.finalized);
  });

  test('double tap / retry with the same operation id produces exactly one bill', () async {
    final orderId = await h.orderWith({coffee: 1});
    const tender = [TenderInput(method: PaymentMethod.upi, applied: 10500)];
    final results = await Future.wait([
      h.pay(orderId, tender, operationId: 'op-1'),
      h.pay(orderId, tender, operationId: 'op-1'),
    ]);
    final again = await h.pay(orderId, tender, operationId: 'op-1');
    expect(results.map((r) => r.billId).toSet().length, 1);
    expect(again.billId, results.first.billId);
    expect(again.alreadyFinalized, isTrue);
    expect(await h.count(h.db.bills), 1);
    expect(await h.count(h.db.payments), 1);
    final originals = await (h.db.select(
      h.db.printJobs,
    )..where((j) => j.documentType.equals(DocumentType.receipt))).get();
    expect(originals.length, 1);
    expect(await h.db.peekSequenceValue('receipt'), 2);
  });

  test('a different operation on an already billed order is rejected', () async {
    final orderId = await h.orderWith({coffee: 1});
    await h.pay(orderId, [const TenderInput(method: PaymentMethod.card, applied: 10500)]);
    await expectLater(
      () => h.pay(orderId, [const TenderInput(method: PaymentMethod.card, applied: 10500)]),
      throwsA(isA<ConflictException>()),
    );
  });

  test('a failure inside the transaction leaves nothing behind', () async {
    final orderId = await h.orderWith({coffee: 1});
    final service = CheckoutService(h.ctx)..debugBeforeCommit = () async => throw StateError('power cut');
    await expectLater(
      service.finalize(
        h.cashier,
        FinalizeRequest(
          orderId: orderId,
          operationId: 'op-x',
          tenders: const [TenderInput(method: PaymentMethod.cash, applied: 10500)],
          paymentConfirmed: true,
        ),
      ),
      throwsStateError,
    );
    expect(await h.count(h.db.bills), 0);
    expect(await h.count(h.db.billLines), 0);
    expect(await h.count(h.db.payments), 0);
    expect(await h.count(h.db.printJobs), 0);
    expect(await h.db.peekSequenceValue('receipt'), 1);
    expect(await h.ctx.completedOperation('finalize:op-x'), isNull);
    final order = await (h.db.select(h.db.orders)..where((o) => o.id.equals(orderId))).getSingle();
    expect(order.status, OrderStatus.open);
    // And it can still be billed normally afterwards.
    final r = await h.pay(orderId, [
      const TenderInput(method: PaymentMethod.cash, applied: 10500),
    ], operationId: 'op-x');
    expect(r.receiptNo, 'TST-000001');
  });

  test('split tender must equal the total; only cash gives change', () async {
    final orderId = await h.orderWith({sandwich: 1});
    await expectLater(
      () => h.pay(orderId, [const TenderInput(method: PaymentMethod.upi, applied: 10000)]),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      () => h.pay(orderId, [const TenderInput(method: PaymentMethod.card, applied: 20000, tendered: 25000)]),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(
      () => h.pay(orderId, [
        const TenderInput(method: PaymentMethod.upi, applied: 15000),
        const TenderInput(method: PaymentMethod.cash, applied: 10000),
      ]),
      throwsA(isA<ValidationException>()),
    );
    final r = await h.pay(orderId, [
      const TenderInput(method: PaymentMethod.upi, applied: 15000),
      const TenderInput(method: PaymentMethod.cash, applied: 5000, tendered: 10000),
    ]);
    expect(r.change, 5000);
    final pays = await (h.db.select(h.db.payments)..where((p) => p.billId.equals(r.billId))).get();
    expect(pays.fold<int>(0, (a, p) => a + p.applied), 20000);
  });

  test('payment must be confirmed and a shift must be open', () async {
    final orderId = await h.orderWith({sandwich: 1});
    await expectLater(
      () => h.checkout.finalize(
        h.cashier,
        FinalizeRequest(
          orderId: orderId,
          operationId: 'x',
          tenders: const [TenderInput(method: PaymentMethod.cash, applied: 20000)],
          paymentConfirmed: false,
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    await expectLater(() => h.shifts.closeShift(h.cashier, countedCash: 100000), throwsA(isA<ConflictException>()));
    await h.shifts.closeShift(h.owner, countedCash: 100000, carryOpenOrders: true);
    await expectLater(
      () => h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 20000)]),
      throwsA(isA<ConflictException>()),
    );
  });

  test('kitchen staff cannot take payment (enforced in the service)', () async {
    final orderId = await h.orderWith({sandwich: 1});
    await expectLater(
      () => h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 20000)], actor: h.kitchen),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('cashier discount above the limit needs owner approval', () async {
    final orderId = await h.orderWith({sandwich: 1});
    await expectLater(
      () => h.orders.setBillDiscount(h.cashier, orderId, const Discount.percent(2000)),
      throwsA(isA<ApprovalRequiredException>()),
    );
    // Rolled back: no discount stored.
    final order = await (h.db.select(h.db.orders)..where((o) => o.id.equals(orderId))).getSingle();
    expect(order.billDiscountType, 'none');
    await h.orders.setBillDiscount(h.cashier, orderId, const Discount.percent(2000), approval: await h.approval());
    final r = await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 16000)]);
    expect(r.total, 16000);
  });

  test('menu and settings edits never change open lines or old receipts', () async {
    final orderId = await h.orderWith({coffee: 1});
    final menu = await h.menu.loadMenu();
    final coffeeView = menu.items.firstWhere((i) => i.id == coffee);
    await h.menu.saveItem(
      h.owner,
      ItemInput(
        id: coffee,
        categoryId: coffeeView.row.categoryId,
        name: 'Coffee (new)',
        price: 15000,
        taxProfileId: null,
      ),
    );
    final open = await h.orders.loadOrder(orderId);
    expect(open.lines.single.row.unitPrice, 10000);
    expect(open.lines.single.row.itemName, 'Coffee');
    expect(open.pricing!.total, 10500);

    final r = await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 10500)]);
    final before = (await BillService(h.ctx).receiptDocument(r.billId)).encode();
    final profiles = await h.settings.taxProfiles();
    await h.settings.updateTaxProfile(
      h.owner,
      profiles.first.id,
      const TaxProfileInput(name: 'GST 18%', mode: TaxMode.exclusive, rateBps: 1800),
    );
    await h.settings.updateBusinessDetails(
      h.owner,
      const BusinessDetailsInput(name: 'Renamed Café', address: 'Elsewhere', receiptFooter: 'Bye'),
    );
    final after = (await BillService(h.ctx).receiptDocument(r.billId)).encode();
    expect(after, before);
    expect(after, contains('Test Café'));
  });
}

extension on PrinterProfileInput {
  PrinterProfileInput copyWithName(String name, String host) => PrinterProfileInput(
    name: name,
    role: PrinterRole.both,
    paperWidthMm: paperWidthMm,
    dotsWidth: dotsWidth,
    charsPerLine: charsPerLine,
    codePage: codePage,
    renderMode: renderMode,
    cutter: cutter,
    drawerPulse: drawerPulse,
    transport: transport,
    endpoint: host,
    port: 9100,
  );
}
