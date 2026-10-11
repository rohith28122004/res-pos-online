import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/host/approvals.dart';
import 'package:cafedesk/core/host/command_dispatcher.dart';
import 'package:cafedesk/core/pricing/pricing_engine.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/connected.dart';
import '../support/harness.dart';

void main() {
  late Harness h;
  late CommandDispatcher d;
  late ApprovalRegistry approvals;
  late Actor waiter;
  late String waiterPhone;
  late String kitchenTablet;
  late String coffee;
  late String latte;
  late String latteLarge;
  late String oatMilk;
  late String t1;

  setUp(() async {
    h = await Harness.create();
    await installHostIdentity(h);
    await addKotPrinter(h);
    waiter = await addStaff(h, 'Wendy Waiter', StaffRole.waiter);
    waiterPhone = await pairDeviceRow(h, DeviceRole.waiter);
    kitchenTablet = await pairDeviceRow(h, DeviceRole.kitchen);
    final cat = await h.category('Coffee');
    coffee = await h.item(cat, 'Filter coffee', 4000);
    latte = await h.item(
      cat,
      'Latte',
      0,
      variants: const [
        VariantInput(name: 'Regular', price: 12000),
        VariantInput(name: 'Large', price: 16000),
      ],
      modifiers: const [ModifierInput(name: 'Oat milk', price: 3000)],
    );
    final menu = await h.menu.loadMenu();
    final l = menu.items.firstWhere((i) => i.id == latte);
    latteLarge = l.variants.firstWhere((v) => v.name == 'Large').id;
    oatMilk = l.modifiers.single.id;
    t1 = await TableService(h.ctx).createTable(h.owner, name: 'T1');
    approvals = ApprovalRegistry(h.clock);
    d = CommandDispatcher(h.ctx, approvals: approvals);
  });
  tearDown(() => h.dispose());

  RemoteCaller asWaiter() => caller(waiterPhone, DeviceRole.waiter, waiter);
  RemoteCaller asKitchen() => caller(kitchenTablet, DeviceRole.kitchen, h.kitchen);

  Map<String, Object?> place({String? tableId, List<Map<String, Object?>>? lines, String? id}) => command(
    h,
    deviceId: waiterPhone,
    actor: waiter,
    action: CommandAction.orderPlace,
    commandId: id,
    payload: {
      'orderType': tableId == null ? 'takeaway' : 'dine_in',
      'tableId': ?tableId,
      'lines': lines ?? [line(coffee, 4000, quantity: 2)],
      'sendToKitchen': true,
    },
  );

  Future<ProtocolException> thrown(Future<Object?> f) async {
    try {
      await f;
    } on ProtocolException catch (e) {
      return e;
    }
    fail('expected a ProtocolException');
  }

  test('placing a table order creates one order, one ticket and one print job — even when repeated', () async {
    final body = place(
      tableId: t1,
      lines: [
        line(coffee, 4000, quantity: 2),
        line(latte, 19000, variantId: latteLarge, modifierIds: [oatMilk], note: 'hot'),
      ],
    );
    final r = await d.handle(asWaiter(), body);
    expect(r.state, ResultState.accepted, reason: r.error?.message);
    expect(r.result!['orderRef'], startsWith('T1'));
    expect(r.result!['ticketNo'], isNotNull);
    expect(r.result!['estimatedTotal'], 2 * 4000 + 19000);
    expect(r.eventSequence, greaterThan(0));
    final ticketsAfterFirst = await h.count(h.db.kitchenTickets);
    final jobsAfterFirst = await h.count(h.db.printJobs);
    final eventsAfterFirst = (await events(h)).length;
    expect(ticketsAfterFirst, 1);
    expect(jobsAfterFirst, 1);

    // The same command again (timeout + retry, or LAN and cloud both delivered).
    final again = await d.handle(asWaiter(), body);
    expect(again.toJson(), r.toJson());
    expect(await h.count(h.db.orders), 1);
    expect(await h.count(h.db.kitchenTickets), ticketsAfterFirst);
    expect(await h.count(h.db.printJobs), jobsAfterFirst);
    expect((await events(h)).length, eventsAfterFirst);

    // Attribution: the order and ticket name the waiter; audit records the device.
    final order = await (h.db.select(h.db.orders)).getSingle();
    expect(order.createdByName, 'Wendy Waiter');
    final ticket = await (h.db.select(h.db.kitchenTickets)).getSingle();
    expect(ticket.createdByName, 'Wendy Waiter');
    final audit = await (h.db.select(
      h.db.auditEvents,
    )..where((a) => a.action.equals('remote.order.place'))).getSingle();
    expect(audit.detailsJson, contains(waiterPhone));
  });

  test('same command id with a different body is refused and changes nothing', () async {
    final id = h.ctx.ids.newId();
    await d.handle(asWaiter(), place(id: id));
    final e = await thrown(d.handle(asWaiter(), place(id: id, lines: [line(coffee, 4000, quantity: 3)])));
    expect(e.code, ErrorCode.commandIdReused);
    expect(await h.count(h.db.orders), 1);
    expect(await h.count(h.db.orderLines), 1);
  });

  test('two phones racing for one table: exactly one wins, the other gets the existing order', () async {
    final results = await Future.wait([
      d.handle(asWaiter(), place(tableId: t1)),
      d.handle(caller(waiterPhone, DeviceRole.waiter, waiter), place(tableId: t1)),
    ]);
    final accepted = results.where((r) => r.accepted).toList();
    final rejected = results.where((r) => !r.accepted).toList();
    expect(accepted, hasLength(1));
    expect(rejected.single.error!.code, ErrorCode.tableOccupied);
    expect(rejected.single.error!.details!['orderId'], accepted.single.resultId);
    expect(await h.count(h.db.orders), 1);
  });

  test('a stored rejection is returned again for the same command', () async {
    await d.handle(asWaiter(), place(tableId: t1));
    final body = place(tableId: t1);
    final first = await d.handle(asWaiter(), body);
    final second = await d.handle(asWaiter(), body);
    expect(first.error!.code, ErrorCode.tableOccupied);
    expect(second.toJson(), first.toJson());
  });

  test('price changes and sold-out items are reported, nothing is written', () async {
    final r = await d.handle(asWaiter(), place(lines: [line(coffee, 3500)]));
    expect(r.error!.code, ErrorCode.priceChanged);
    final changed = (r.error!.details!['lines']! as List).single as Map;
    expect(changed, containsPair('expected', 3500));
    expect(changed, containsPair('current', 4000));
    expect(await h.count(h.db.orders), 0);

    await h.menu.setItemAvailable(h.owner, coffee, false);
    final r2 = await d.handle(asWaiter(), place());
    expect(r2.error!.code, ErrorCode.itemUnavailable);
    expect(((r2.error!.details!['lines']! as List).single as Map)['reason'], 'sold_out');

    final r3 = await d.handle(asWaiter(), place(lines: [line(latte, 12000)]));
    expect(r3.error!.code, ErrorCode.itemUnavailable, reason: 'two variants, none chosen');
    expect(await h.count(h.db.orders), 0);
    expect(await h.count(h.db.kitchenTickets), 0);
  });

  test('additions append to an accepted order; stale edits are refused with the current order', () async {
    final placed = await d.handle(asWaiter(), place(tableId: t1));
    final orderId = placed.resultId!;
    final add = await d.handle(
      asWaiter(),
      command(
        h,
        deviceId: waiterPhone,
        actor: waiter,
        action: CommandAction.orderAdd,
        aggregateId: orderId,
        payload: {
          'lines': [line(coffee, 4000)],
          'sendToKitchen': true,
        },
      ),
    );
    expect(add.state, ResultState.accepted);
    expect(await h.count(h.db.kitchenTickets), 2, reason: 'only the new item goes to the kitchen');

    // A cashier edits the order on the POS; the phone's revision is now stale.
    final lineId = (await h.orders.linesOf(orderId)).first.id;
    await h.orders.updateDetails(h.cashier, orderId, guestCount: 3);
    final stale = await d.handle(
      asWaiter(),
      command(
        h,
        deviceId: waiterPhone,
        actor: waiter,
        action: CommandAction.orderChangeQuantity,
        aggregateId: orderId,
        expectedRevision: add.revision,
        payload: {'lineId': lineId, 'quantity': 5},
      ),
    );
    expect(stale.error!.code, ErrorCode.staleRevision);
    expect(stale.error!.details!['currentRevision'], greaterThan(add.revision!));
    expect((stale.error!.details!['order']! as Map)['orderId'], orderId);
  });

  test('cancelling items the kitchen has needs an owner approval, used once', () async {
    final placed = await d.handle(asWaiter(), place(lines: [line(coffee, 4000, quantity: 2)]));
    final orderId = placed.resultId!;
    final lineId = (await h.orders.linesOf(orderId)).single.id;
    Map<String, Object?> reduce(int revision, {String? approvalId}) => command(
      h,
      deviceId: waiterPhone,
      actor: waiter,
      action: CommandAction.orderChangeQuantity,
      aggregateId: orderId,
      expectedRevision: revision,
      payload: {'lineId': lineId, 'quantity': 1, 'reason': 'customer changed mind', 'approvalId': ?approvalId},
    );
    final denied = await d.handle(asWaiter(), reduce(placed.revision!));
    expect(denied.error!.code, ErrorCode.approvalRequired);

    final approvalId = approvals.grant(await h.approval(), waiterPhone);
    final ok = await d.handle(asWaiter(), reduce(placed.revision!, approvalId: approvalId));
    expect(ok.state, ResultState.accepted, reason: ok.error?.message);
    expect(ok.result!['ticketId'], isNotNull, reason: 'correction ticket');
    final correction = await (h.db.select(
      h.db.kitchenTickets,
    )..where((t) => t.kind.equals(TicketKind.correction))).getSingle();
    expect(correction.reason, 'customer changed mind');

    final reused = await d.handle(asWaiter(), reduce(ok.revision!, approvalId: approvalId));
    expect(reused.error!.code, ErrorCode.approvalRequired, reason: 'approvals are single-use');
  });

  test('kitchen moves tickets forward only, with revision checks', () async {
    await d.handle(asWaiter(), place());
    final ticket = await (h.db.select(h.db.kitchenTickets)).getSingle();
    Map<String, Object?> status(String s, int revision) => command(
      h,
      deviceId: kitchenTablet,
      actor: h.kitchen,
      action: CommandAction.ticketSetStatus,
      aggregateId: ticket.id,
      expectedRevision: revision,
      payload: {'status': s},
    );
    final preparing = await d.handle(asKitchen(), status(TicketStatus.preparing, 1));
    expect(preparing.result, {'ticketId': ticket.id, 'status': 'preparing', 'revision': 2});

    // A phone that was offline still holds revision 1.
    final stale = await d.handle(asKitchen(), status(TicketStatus.ready, 1));
    expect(stale.error!.code, ErrorCode.staleRevision);
    expect((stale.error!.details!['ticket']! as Map)['status'], 'preparing');

    // The POS marks it ready; a queued "preparing" can't regress it.
    await h.orders.setTicketStatus(h.cashier, ticket.id, TicketStatus.ready);
    final back = await d.handle(asKitchen(), status(TicketStatus.preparing, 3));
    expect(back.error!.code, ErrorCode.transitionNotAllowed);
    final now = await (h.db.select(h.db.kitchenTickets)).getSingle();
    expect(now.status, TicketStatus.ready);
  });

  test('roles, devices, identities and epochs are enforced and never stored', () async {
    // A waiter phone cannot change kitchen tickets.
    await d.handle(asWaiter(), place());
    final ticket = await (h.db.select(h.db.kitchenTickets)).getSingle();
    final kitchenCmd = command(
      h,
      deviceId: waiterPhone,
      actor: waiter,
      action: CommandAction.ticketSetStatus,
      aggregateId: ticket.id,
      expectedRevision: 1,
      payload: {'status': 'ready'},
    );
    expect((await thrown(d.handle(asWaiter(), kitchenCmd))).code, ErrorCode.forbidden);
    // Kitchen staff cannot place orders even on a waiter phone.
    final asKitchenStaffOnPhone = caller(waiterPhone, DeviceRole.waiter, h.kitchen);
    final kitchenPlace = command(
      h,
      deviceId: waiterPhone,
      actor: h.kitchen,
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
    );
    expect((await thrown(d.handle(asKitchenStaffOnPhone, kitchenPlace))).code, ErrorCode.forbidden);
    // A body naming someone else (forged actor) is refused.
    final forged = command(
      h,
      deviceId: waiterPhone,
      actor: h.owner,
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
    );
    expect((await thrown(d.handle(asWaiter(), forged))).code, ErrorCode.forbidden);
    // Another device's id in the body is refused.
    final otherDevice = command(
      h,
      deviceId: kitchenTablet,
      actor: waiter,
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
    );
    expect((await thrown(d.handle(asWaiter(), otherDevice))).code, ErrorCode.forbidden);
    // A command made before a restore (old epoch) is held for review.
    final oldEpoch = place();
    await installHostIdentity(h, epoch: 2);
    expect((await thrown(d.handle(asWaiter(), oldEpoch))).code, ErrorCode.epochChanged);
    expect(await h.count(h.db.commandReceipts), 1, reason: 'only the first, accepted command');
  });

  test('protocol version, unknown actions and malformed bodies', () async {
    final v2 = {...place(), 'protocolVersion': 2};
    expect((await thrown(d.handle(asWaiter(), v2))).code, ErrorCode.updateRequired);
    final unknown = {...place(), 'action': 'bill.pay'};
    expect((await thrown(d.handle(asWaiter(), unknown))).code, ErrorCode.updateRequired);
    final extra = {...place(), 'role': 'owner'};
    expect((await thrown(d.handle(asWaiter(), extra))).code, ErrorCode.validation);
    final float = place(
      lines: [
        {...line(coffee, 4000), 'quantity': 1.5},
      ],
    );
    expect((await thrown(d.handle(asWaiter(), float))).code, ErrorCode.validation);
    final tooMany = place(lines: [for (var i = 0; i < 51; i++) line(coffee, 4000)]);
    expect((await thrown(d.handle(asWaiter(), tooMany))).code, ErrorCode.tooLarge);
    expect(await h.count(h.db.orders), 0);
  });

  test('billed orders are closed to waiters; results can be looked up by the sender only', () async {
    await h.openShift();
    final placed = await d.handle(asWaiter(), place());
    final orderId = placed.resultId!;
    await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 8000)]);
    final late = await d.handle(
      asWaiter(),
      command(
        h,
        deviceId: waiterPhone,
        actor: waiter,
        action: CommandAction.orderAdd,
        aggregateId: orderId,
        payload: {
          'lines': [line(coffee, 4000)],
          'sendToKitchen': true,
        },
      ),
    );
    expect(late.error!.code, ErrorCode.orderClosed);

    final found = await d.lookup(asWaiter(), placed.commandId);
    expect(found!.toJson(), placed.toJson());
    expect(await d.lookup(asKitchen(), placed.commandId), isNull);
    expect(await d.lookup(asWaiter(), 'never-sent'), isNull);
  });

  test('waiters cannot discount without approval, take payment or refund', () async {
    final orderId = await h.orderWith({coffee: 1}, actor: waiter);
    final lineId = (await h.orders.linesOf(orderId)).single.id;
    await expectLater(
      h.orders.setLineDiscount(waiter, lineId, const Discount.amount(100)),
      throwsA(isA<ApprovalRequiredException>()),
    );
    await h.orders.setLineDiscount(
      waiter,
      lineId,
      const Discount.amount(100),
      approval: await h.approval(),
    );
    expect(waiter.can(Permission.checkout), isFalse);
    expect(waiter.can(Permission.refund), isFalse);
    expect(waiter.can(Permission.viewReports), isFalse);
    expect(waiter.can(Permission.manageStaff), isFalse);
    await expectLater(
      h.orders.setServiceCharge(waiter, orderId, enabled: false),
      throwsA(isA<PermissionDeniedException>()),
    );
    await h.openShift();
    await expectLater(
      h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 3900)], actor: waiter),
      throwsA(isA<PermissionDeniedException>()),
    );
  });
}
