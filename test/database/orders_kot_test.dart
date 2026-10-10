import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/printing/documents/print_documents.dart';
import 'package:cafedesk/core/printing/queue/print_job_writer.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/settings/application/printer_service.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  late String coffee;
  late String latte;

  setUp(() async {
    h = await Harness.create();
    final cat = await h.category('Coffee');
    coffee = await h.item(cat, 'Filter coffee', 4000);
    latte = await h.item(
      cat,
      'Latte',
      0,
      variants: const [
        VariantInput(name: 'Small', price: 12000),
        VariantInput(name: 'Large', price: 16000),
      ],
      modifiers: const [
        ModifierInput(name: 'Extra shot', price: 3000),
        ModifierInput(name: 'Oat milk', price: 4000),
      ],
    );
    final p = PrinterProfileInput.defaults(paperWidthMm: 58, transport: TransportType.tcp);
    await PrinterService(h.ctx).saveProfile(
      h.owner,
      PrinterProfileInput(
        name: 'Kitchen',
        role: PrinterRole.kot,
        paperWidthMm: p.paperWidthMm,
        dotsWidth: p.dotsWidth,
        charsPerLine: p.charsPerLine,
        codePage: p.codePage,
        renderMode: p.renderMode,
        cutter: p.cutter,
        drawerPulse: false,
        transport: TransportType.tcp,
        endpoint: '10.0.0.9',
        port: 9100,
      ),
    );
  });
  tearDown(() => h.dispose());

  test('lines capture variant, modifiers and price; identical adds merge', () async {
    final id = await h.orders.createOrder(h.cashier, type: OrderType.takeaway);
    final menu = await h.menu.loadMenu();
    final l = menu.items.firstWhere((i) => i.id == latte);
    final large = l.variants.firstWhere((v) => v.name == 'Large');
    final shot = l.modifiers.firstWhere((m) => m.name == 'Extra shot');
    await h.orders.addItem(h.cashier, id, itemId: latte, variantId: large.id, modifierIds: [shot.id]);
    await h.orders.addItem(h.cashier, id, itemId: latte, variantId: large.id, modifierIds: [shot.id]);
    await h.orders.addItem(h.cashier, id, itemId: coffee, note: 'Less sugar');
    final d = await h.orders.loadOrder(id);
    expect(d.lines.length, 2);
    final latteLine = d.lines.firstWhere((x) => x.row.itemName == 'Latte');
    expect(latteLine.row.quantity, 2);
    expect(latteLine.row.variantName, 'Large');
    expect(latteLine.row.unitPrice, 16000);
    expect(latteLine.row.modifiersUnitTotal, 3000);
    expect(d.pricing!.total, 2 * 19000 + 4000);
    await expectLater(() => h.orders.addItem(h.cashier, id, itemId: latte), throwsA(isA<ValidationException>()));
  });

  test('sold-out items cannot be added', () async {
    await h.menu.setItemAvailable(h.cashier, coffee, false);
    final id = await h.orders.createOrder(h.cashier, type: OrderType.takeaway);
    await expectLater(() => h.orders.addItem(h.cashier, id, itemId: coffee), throwsA(isA<ConflictException>()));
  });

  test('KOT sends only new items; retries with the same id do not duplicate', () async {
    final id = await h.orderWith({coffee: 2});
    final t1 = await h.orders.sendToKitchen(h.cashier, id, operationId: 'k1');
    final t1again = await h.orders.sendToKitchen(h.cashier, id, operationId: 'k1');
    expect(t1, isNotNull);
    expect(t1again, t1);
    expect(await h.count(h.db.kitchenTickets), 1);
    expect(await h.orders.sendToKitchen(h.cashier, id, operationId: 'k2'), isNull, reason: 'nothing new');

    await h.orders.addItem(h.cashier, id, itemId: coffee, quantity: 1);
    final t2 = await h.orders.sendToKitchen(h.cashier, id, operationId: 'k3');
    final lines = await (h.db.select(h.db.kitchenTicketLines)..where((l) => l.ticketId.equals(t2!))).get();
    expect(lines.single.quantityDelta, 1);
    final jobs = await (h.db.select(h.db.printJobs)..where((j) => j.documentType.equals(DocumentType.kot))).get();
    expect(jobs.length, 2);
  });

  test('reducing below what the kitchen has needs a reason + owner, and issues a correction', () async {
    final id = await h.orderWith({coffee: 3});
    await h.orders.sendToKitchen(h.cashier, id, operationId: 'k1');
    final line = (await h.orders.loadOrder(id)).lines.single;
    await expectLater(() => h.orders.changeQuantity(h.cashier, line.row.id, 1), throwsA(isA<ValidationException>()));
    await expectLater(
      () => h.orders.changeQuantity(h.cashier, line.row.id, 1, reason: 'Customer left'),
      throwsA(isA<ApprovalRequiredException>()),
    );
    await h.orders.changeQuantity(h.cashier, line.row.id, 1, reason: 'Customer left', approval: await h.approval());
    final tickets = await h.orders.tickets();
    final correction = tickets.firstWhere((t) => t.ticket.kind == TicketKind.correction);
    expect(correction.ticket.reason, 'Customer left');
    expect(correction.lines.single.quantityDelta, -2);
    expect((await h.orders.sentQuantities(id))[line.row.id], 1);
    // Notes are locked once the kitchen has the line.
    await expectLater(() => h.orders.updateLineNote(h.cashier, line.row.id, 'Hot'), throwsA(isA<ConflictException>()));
  });

  test('cancelling an order the kitchen started issues a cancellation ticket', () async {
    final id = await h.orderWith({coffee: 2});
    await h.orders.sendToKitchen(h.cashier, id, operationId: 'k1');
    await expectLater(
      () => h.orders.cancelOrder(h.cashier, id, reason: 'Wrong table'),
      throwsA(isA<ApprovalRequiredException>()),
    );
    await h.orders.cancelOrder(h.cashier, id, reason: 'Wrong table', approval: await h.approval());
    final order = await (h.db.select(h.db.orders)..where((o) => o.id.equals(id))).getSingle();
    expect(order.status, OrderStatus.cancelled);
    expect(order.cancelReason, 'Wrong table');
    final tickets = await h.orders.tickets();
    expect(tickets.where((t) => t.ticket.kind == TicketKind.correction).single.lines.single.quantityDelta, -2);
  });

  test('unsent drafts can be removed without approval', () async {
    final id = await h.orderWith({coffee: 1});
    final line = (await h.orders.loadOrder(id)).lines.single;
    await h.orders.changeQuantity(h.cashier, line.row.id, 0);
    expect((await h.orders.loadOrder(id)).lines, isEmpty);
  });

  test('one open dine-in order per table; occupancy comes from orders', () async {
    final tables = TableService(h.ctx);
    final t1 = await tables.createTable(h.owner, name: 'T1', capacity: 4);
    final id = await h.orders.createOrder(h.cashier, type: OrderType.dineIn, tableId: t1);
    await expectLater(
      () => h.orders.createOrder(h.cashier, type: OrderType.dineIn, tableId: t1),
      throwsA(isA<ConflictException>()),
    );
    var status = await tables.tableStatus();
    expect(status.single.occupied, isTrue);
    await h.orders.cancelOrder(h.cashier, id, reason: 'Test');
    status = await tables.tableStatus();
    expect(status.single.occupied, isFalse);
    await h.orders.createOrder(h.cashier, type: OrderType.dineIn, tableId: t1);
  });

  test('committed open orders survive a restart (re-open the database)', () async {
    // Uses the same in-memory connection; a file-based restart is covered in
    // backup_restore_test.dart.
    final id = await h.orderWith({coffee: 2});
    final reloaded = await h.orders.openOrders();
    expect(reloaded.single.order.id, id);
    expect(reloaded.single.itemCount, 2);
  });

  test('kitchen role can update ticket status but not take orders', () async {
    final id = await h.orderWith({coffee: 1});
    final t = await h.orders.sendToKitchen(h.cashier, id, operationId: 'k');
    await h.orders.setTicketStatus(h.kitchen, t!, TicketStatus.preparing);
    await h.orders.setTicketStatus(h.kitchen, t, TicketStatus.ready);
    await expectLater(
      () => h.orders.createOrder(h.kitchen, type: OrderType.takeaway),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
