import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_errors.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/sync/host_outbox.dart';
import '../../bills/domain/payment_method.dart';
import '../../orders/domain/order_models.dart';

class ShiftSummary {
  const ShiftSummary({
    required this.shift,
    required this.billCount,
    required this.salesTotal,
    required this.receiptsByMethod,
    required this.refundsByMethod,
    required this.cashIn,
    required this.cashOut,
    required this.drawerExpenses,
    required this.otherExpenses,
    required this.openOrders,
  });

  final ShiftRow shift;
  final int billCount;
  final int salesTotal;
  final Map<String, int> receiptsByMethod;
  final Map<String, int> refundsByMethod;
  final int cashIn;
  final int cashOut;
  final int drawerExpenses;
  final int otherExpenses;
  final int openOrders;

  int get cashReceipts => receiptsByMethod[PaymentMethod.cash.code] ?? 0;
  int get cashRefunds => refundsByMethod[PaymentMethod.cash.code] ?? 0;

  /// opening float + cash receipts − cash refunds + cash in − cash out −
  /// drawer-paid expenses. Drawer expenses are not also recorded as cash
  /// out, so nothing is subtracted twice.
  int get expectedCash => shift.openingFloat + cashReceipts - cashRefunds + cashIn - cashOut - drawerExpenses;

  Map<String, Object?> toJson() => {
    'openingFloat': shift.openingFloat,
    'billCount': billCount,
    'salesTotal': salesTotal,
    'receiptsByMethod': receiptsByMethod,
    'refundsByMethod': refundsByMethod,
    'cashIn': cashIn,
    'cashOut': cashOut,
    'drawerExpenses': drawerExpenses,
    'otherExpenses': otherExpenses,
    'expectedCash': expectedCash,
    'openOrders': openOrders,
  };
}

class ShiftService {
  ShiftService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  Future<ShiftRow?> currentShift() => (_db.select(_db.shifts)..where((s) => s.status.equals('open'))).getSingleOrNull();

  Stream<ShiftRow?> watchCurrentShift() =>
      (_db.select(_db.shifts)..where((s) => s.status.equals('open'))).watchSingleOrNull();

  Future<String> openShift(Actor actor, {required int openingFloat}) async {
    actor.require(Permission.ownShift);
    if (openingFloat < 0) throw const ValidationException('Opening float cannot be negative');
    final now = ctx.now();
    final calendar = await ctx.calendar();
    final id = ctx.ids.newId();
    try {
      await _db.transaction(() async {
        if (await currentShift() != null) throw const ConflictException('A shift is already open');
        await _db
            .into(_db.shifts)
            .insert(
              ShiftsCompanion.insert(
                id: id,
                openedBy: actor.staffId,
                openedByName: actor.name,
                openedAt: now.millisecondsSinceEpoch,
                openingFloat: openingFloat,
                status: 'open',
                businessDate: calendar.businessDateOf(now).key,
              ),
            );
        await ctx.audit(
          actor,
          'shift.opened',
          entityType: 'shift',
          entityId: id,
          details: {'openingFloat': openingFloat},
        );
        await ctx.outbox.changed(Aggregate.shift, id);
      });
    } on Object catch (e) {
      if (isUniqueViolation(e)) throw const ConflictException('A shift is already open');
      rethrow;
    }
    return id;
  }

  Future<String> recordCashMovement(
    Actor actor, {
    required bool cashIn,
    required int amount,
    required String reason,
  }) async {
    actor.require(Permission.ownShift);
    if (amount <= 0) throw const ValidationException('Amount must be more than zero');
    final why = requireText(reason, 'Reason', max: 140);
    final now = ctx.now();
    final calendar = await ctx.calendar();
    final id = ctx.ids.newId();
    await _db.transaction(() async {
      final shift = await currentShift();
      if (shift == null) throw const ConflictException('Open a shift first');
      await _db
          .into(_db.cashMovements)
          .insert(
            CashMovementsCompanion.insert(
              id: id,
              shiftId: shift.id,
              direction: cashIn ? 'in' : 'out',
              amount: amount,
              reason: why,
              createdBy: actor.staffId,
              createdByName: actor.name,
              createdAt: now.millisecondsSinceEpoch,
              businessDate: calendar.businessDateOf(now).key,
            ),
          );
      await ctx.audit(
        actor,
        cashIn ? 'drawer.cash_in' : 'drawer.cash_out',
        entityType: 'shift',
        entityId: shift.id,
        details: {'amount': amount, 'reason': why},
      );
      await ctx.outbox.changed(Aggregate.cashMovement, id);
    });
    return id;
  }

  Future<List<CashMovementRow>> movements(String shiftId) =>
      (_db.select(_db.cashMovements)
            ..where((m) => m.shiftId.equals(shiftId))
            ..orderBy([(m) => OrderingTerm(expression: m.createdAt)]))
          .get();

  Future<ShiftSummary> summary(String shiftId) async {
    final shift = await (_db.select(_db.shifts)..where((s) => s.id.equals(shiftId))).getSingleOrNull();
    if (shift == null) throw const NotFoundException('Shift not found');
    Future<Map<String, int>> byMethod(String sql) async {
      final rows = await _db.customSelect(sql, variables: [Variable.withString(shiftId)]).get();
      return {for (final r in rows) r.read<String>('method'): r.read<int>('amount')};
    }

    final receipts = await byMethod(
      'SELECT method, SUM(applied) AS amount FROM payments WHERE shift_id = ? GROUP BY method',
    );
    final refunds = await byMethod(
      'SELECT method, SUM(amount) AS amount FROM refund_payments WHERE shift_id = ? GROUP BY method',
    );
    final bills = await _db
        .customSelect(
          'SELECT COUNT(*) AS n, COALESCE(SUM(total), 0) AS total FROM bills WHERE shift_id = ?',
          variables: [Variable.withString(shiftId)],
        )
        .getSingle();
    final moves = await _db
        .customSelect(
          "SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END), 0) AS cash_in, "
          "COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END), 0) AS cash_out "
          'FROM cash_movements WHERE shift_id = ?',
          variables: [Variable.withString(shiftId)],
        )
        .getSingle();
    final expenses = await _db
        .customSelect(
          'SELECT COALESCE(SUM(CASE WHEN paid_from_drawer = 1 THEN amount ELSE 0 END), 0) AS drawer, '
          'COALESCE(SUM(CASE WHEN paid_from_drawer = 0 THEN amount ELSE 0 END), 0) AS other '
          'FROM expenses WHERE shift_id = ? AND voided_at IS NULL',
          variables: [Variable.withString(shiftId)],
        )
        .getSingle();
    final open = await (_db.select(_db.orders)..where((o) => o.status.equals(OrderStatus.open))).get();
    return ShiftSummary(
      shift: shift,
      billCount: bills.read<int>('n'),
      salesTotal: bills.read<int>('total'),
      receiptsByMethod: receipts,
      refundsByMethod: refunds,
      cashIn: moves.read<int>('cash_in'),
      cashOut: moves.read<int>('cash_out'),
      drawerExpenses: expenses.read<int>('drawer'),
      otherExpenses: expenses.read<int>('other'),
      openOrders: shift.status == 'open' ? open.length : 0,
    );
  }

  /// Closes the active shift with a counted-cash snapshot. Open orders block
  /// closing unless an owner explicitly carries them into the next shift.
  Future<String> closeShift(
    Actor actor, {
    required int countedCash,
    String? note,
    bool carryOpenOrders = false,
    OwnerApproval? approval,
  }) async {
    actor.require(Permission.ownShift);
    if (countedCash < 0) throw const ValidationException('Counted cash cannot be negative');
    final closureId = ctx.ids.newId();
    await _db.transaction(() async {
      final shift = await currentShift();
      if (shift == null) throw const ConflictException('No shift is open');
      final s = await summary(shift.id);
      if (s.openOrders > 0) {
        if (!carryOpenOrders) {
          throw ConflictException(
            '${s.openOrders} order(s) are still open. Bill or cancel them, or ask an admin to carry them to the next shift.',
          );
        }
        await ctx.requireOwnerOrApproval(actor, approval, 'close the shift with open orders');
      }
      final now = ctx.nowMs();
      await _db
          .into(_db.shiftClosures)
          .insert(
            ShiftClosuresCompanion.insert(
              id: closureId,
              shiftId: shift.id,
              closedBy: actor.staffId,
              closedByName: actor.name,
              closedAt: now,
              countedCash: countedCash,
              expectedCash: s.expectedCash,
              variance: countedCash - s.expectedCash,
              summaryJson: jsonEncode(s.toJson()),
              note: Value(optionalText(note, max: 300)),
              carriedOpenOrders: Value(s.openOrders),
              approvedBy: Value(approval?.ownerId),
            ),
          );
      await (_db.update(_db.shifts)..where((x) => x.id.equals(shift.id))).write(
        ShiftsCompanion(status: const Value('closed'), lastClosedAt: Value(now)),
      );
      await ctx.audit(
        actor,
        'shift.closed',
        entityType: 'shift',
        entityId: shift.id,
        approval: approval,
        details: {
          'countedCash': countedCash,
          'expectedCash': s.expectedCash,
          'variance': countedCash - s.expectedCash,
          'carriedOpenOrders': s.openOrders,
        },
      );
      await ctx.outbox.changed(Aggregate.shift, shift.id);
    });
    return closureId;
  }

  /// Reopens the most recent closed shift. Its closure snapshot stays as an
  /// immutable record; closing again adds a new snapshot.
  Future<void> reopenShift(Actor actor, String shiftId, {OwnerApproval? approval, required String reason}) async {
    actor.require(Permission.ownShift);
    final why = requireText(reason, 'Reason', max: 140);
    await ctx.requireOwnerOrApproval(actor, approval, 'reopen a closed shift');
    try {
      await _db.transaction(() async {
        if (await currentShift() != null) throw const ConflictException('Close the current shift first');
        final latest =
            await (_db.select(_db.shifts)
                  ..orderBy([(s) => OrderingTerm(expression: s.openedAt, mode: OrderingMode.desc)])
                  ..limit(1))
                .getSingleOrNull();
        if (latest == null || latest.id != shiftId) {
          throw const ConflictException('Only the most recent shift can be reopened');
        }
        await (_db.update(
          _db.shifts,
        )..where((s) => s.id.equals(shiftId))).write(const ShiftsCompanion(status: Value('open')));
        await ctx.audit(
          actor,
          'shift.reopened',
          entityType: 'shift',
          entityId: shiftId,
          approval: approval,
          details: {'reason': why},
        );
        await ctx.outbox.changed(Aggregate.shift, shiftId);
      });
    } on Object catch (e) {
      if (isUniqueViolation(e)) throw const ConflictException('Close the current shift first');
      rethrow;
    }
  }

  Future<List<ShiftRow>> recentShifts({int limit = 30}) =>
      (_db.select(_db.shifts)
            ..orderBy([(s) => OrderingTerm(expression: s.openedAt, mode: OrderingMode.desc)])
            ..limit(limit))
          .get();

  Future<List<ShiftClosureRow>> closures(String shiftId) =>
      (_db.select(_db.shiftClosures)
            ..where((c) => c.shiftId.equals(shiftId))
            ..orderBy([(c) => OrderingTerm(expression: c.closedAt)]))
          .get();
}
