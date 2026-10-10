import 'dart:convert';

import 'package:cafedesk/core/database/app_database.dart';

import 'package:cafedesk/core/protocol/canonical_json.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/checkout/application/checkout_service.dart';
import 'package:cafedesk/features/expenses/application/expense_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/refunds/application/refund_service.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/connected.dart';
import '../support/harness.dart';

void main() {
  late Harness h;
  late String coffee;

  setUp(() async {
    h = await Harness.create();
    final cat = await h.category('Coffee');
    coffee = await h.item(cat, 'Filter coffee', 4000);
  });
  tearDown(() => h.dispose());

  Map<String, Object?> decode(HostEventRow e) => (jsonDecode(e.eventJson) as Map).cast<String, Object?>();

  test('every change writes an event in its transaction; sequences are gap-free', () async {
    final before = (await events(h)).length;
    final orderId = await h.orders.createOrder(h.cashier, type: OrderType.takeaway);
    await h.orders.addItem(h.cashier, orderId, itemId: coffee, quantity: 2);
    final ticketId = await h.orders.sendToKitchen(h.cashier, orderId, operationId: 'op-1');
    await h.orders.setTicketStatus(h.cashier, ticketId!, TicketStatus.preparing);

    final all = await events(h);
    final mine = all.skip(before).toList();
    expect(mine.map((e) => e.type), [
      EventType.orderUpdated, // created
      EventType.orderUpdated, // item added
      EventType.ticketUpdated, // KOT
      EventType.orderUpdated, // sent quantities
      EventType.ticketUpdated, // preparing
    ]);
    for (var i = 0; i < all.length; i++) {
      expect(all[i].sequence, i + 1, reason: 'contiguous from 1');
      expect(all[i].hostEpoch, 1);
    }
    for (final e in mine) {
      final env = decode(e);
      expect(canonicalJson(env), e.eventJson, reason: 'stored canonical');
      expect(sha256Hex(e.eventJson), e.contentHash);
      expect(env['sequence'], e.sequence);
      expect(e.audience, EventAudience.devices);
    }
    final ticket = decode(mine.last)['payload']! as Map;
    expect(ticket['status'], 'preparing');
    expect(ticket['revision'], 2);
    final order = decode(mine[3])['payload']! as Map;
    expect((order['lines']! as List).single, containsPair('sentQuantity', 2));
    expect(order['createdByName'], 'Cara Cashier');
  });

  test('a rolled-back sale leaves no event and no gap in the sequence', () async {
    await h.openShift();
    final orderId = await h.orderWith({coffee: 1});
    final before = await events(h);
    final crashing = CheckoutService(h.ctx)..debugBeforeCommit = () async => throw StateError('crash before commit');
    await expectLater(
      crashing.finalize(
        h.cashier,
        FinalizeRequest(
          orderId: orderId,
          operationId: 'crashing',
          tenders: const [TenderInput(method: PaymentMethod.cash, applied: 4000)],
          paymentConfirmed: true,
        ),
      ),
      throwsA(isA<StateError>()),
    );
    expect((await events(h)).length, before.length, reason: 'nothing committed');
    expect(await h.count(h.db.bills), 0);
    await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 4000)]);
    final after = await events(h);
    for (var i = 0; i < after.length; i++) {
      expect(after[i].sequence, i + 1);
    }
    final bill = after.lastWhere((e) => e.type == EventType.billFinalized);
    expect(bill.audience, EventAudience.cloud);
    final p = decode(bill)['payload']! as Map;
    expect((p['bill']! as Map)['total'], 4000);
    expect((p['bill']! as Map)['businessDate'], isNotNull);
    expect((p['lines']! as List).single, containsPair('netEx', 4000));
    expect((p['payments']! as List).single, allOf(containsPair('method', 'cash'), containsPair('applied', 4000)));
    expect(
      after.any((e) => e.type == EventType.orderUpdated && (decode(e)['payload']! as Map)['status'] == 'finalized'),
      isTrue,
    );
  });

  test('refunds, expenses, shifts and drawer movements are replicated for reports', () async {
    final shiftId = await h.openShift();
    final orderId = await h.orderWith({coffee: 2});
    final bill = await h.pay(orderId, [const TenderInput(method: PaymentMethod.upi, applied: 8000)]);
    final state = await RefundService(h.ctx).refundableState(bill.billId);
    await RefundService(h.ctx).issueRefund(
      h.owner,
      RefundRequest(
        billId: bill.billId,
        operationId: 'refund-1',
        lineQuantities: {state.lines.single.line.id: 1},
        reason: 'cold',
      ),
    );
    final expenses = ExpenseService(h.ctx);
    final expenseId = await expenses.addExpense(h.cashier, category: 'Milk', amount: 1500, paidFromDrawer: true);
    await expenses.voidExpense(h.owner, expenseId, reason: 'duplicate');
    await h.shifts.recordCashMovement(h.cashier, cashIn: true, amount: 500, reason: 'change');
    await h.shifts.closeShift(h.cashier, countedCash: 100500);

    final all = await events(h);
    final types = all.map((e) => e.type).toList();
    expect(
      types,
      containsAll([
        EventType.refundCreated,
        EventType.expenseRecorded,
        EventType.expenseVoided,
        EventType.cashMovementRecorded,
        EventType.shiftUpdated,
      ]),
    );
    final refund = decode(all.firstWhere((e) => e.type == EventType.refundCreated))['payload']! as Map;
    expect((refund['refund']! as Map)['total'], 4000);
    expect((refund['payments']! as List).single, containsPair('method', 'upi'));
    final shiftEvents = all.where((e) => e.type == EventType.shiftUpdated && e.aggregateId == shiftId).toList();
    expect(shiftEvents.map((e) => e.revision), [1, 2], reason: 'opened, then closed');
    expect(((decode(shiftEvents.last)['payload']! as Map)['closures']! as List), hasLength(1));
    final voided = all.firstWhere((e) => e.type == EventType.expenseVoided);
    expect(voided.revision, 2);
  });

  test('menu and table edits notify devices; staff changes revoke sessions', () async {
    await h.menu.setItemAvailable(h.owner, coffee, false);
    await TableService(h.ctx).createTable(h.owner, name: 'T9');
    final deviceId = await pairDeviceRow(h, 'waiter');
    final now = h.ctx.nowMs();
    await h.db
        .into(h.db.staffSessions)
        .insert(
          StaffSessionsCompanion.insert(
            id: 'sid-1',
            staffId: h.cashier.staffId,
            deviceId: deviceId,
            createdAt: now,
            expiresAt: now + 3600000,
          ),
        );
    await h.auth.updateStaff(h.owner, h.cashier.staffId, disabled: true);

    final all = await events(h);
    expect(all.map((e) => e.type), containsAll([EventType.menuChanged, EventType.tablesChanged]));
    final access = decode(all.firstWhere((e) => e.type == EventType.staffAccessChanged))['payload']! as Map;
    expect(access, {'staffId': h.cashier.staffId, 'role': StaffRole.cashier.name, 'disabled': true});
    final revoked = all.firstWhere((e) => e.type == EventType.sessionRevoked);
    expect((decode(revoked)['payload']! as Map)['sid'], 'sid-1');
    final session = await (h.db.select(h.db.staffSessions)..where((s) => s.id.equals('sid-1'))).getSingle();
    expect(session.revokedAt, isNotNull);
    // Renaming alone changes no access.
    final count = (await events(h)).length;
    await h.auth.updateStaff(h.owner, h.kitchen.staffId, name: 'Ken K');
    expect((await events(h)).length, count);
  });

  test('events carry no password hashes or audit details', () async {
    await h.openShift();
    final orderId = await h.orderWith({coffee: 1});
    await h.pay(orderId, [const TenderInput(method: PaymentMethod.cash, applied: 4000)]);
    for (final e in await events(h)) {
      expect(e.eventJson, isNot(contains(r'$argon2id$')));
      expect(e.eventJson, isNot(contains('passwordHash')));
    }
  });
}
