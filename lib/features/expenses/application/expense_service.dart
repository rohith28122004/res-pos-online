import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/sync/host_outbox.dart';
import '../../../core/time/business_time.dart';

const expenseCategorySuggestions = [
  'Supplies',
  'Milk & dairy',
  'Vegetables',
  'Gas',
  'Utilities',
  'Rent',
  'Wages',
  'Maintenance',
  'Packaging',
  'Other',
];

class ExpenseService {
  ExpenseService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  /// Expenses are separate from sales and refunds. Drawer-paid expenses are
  /// tied to the open shift and reduce its expected cash.
  Future<String> addExpense(
    Actor actor, {
    required String category,
    required int amount,
    String? note,
    required bool paidFromDrawer,
  }) async {
    actor.require(Permission.recordExpense);
    final cat = requireText(category, 'Category', max: 40);
    if (amount <= 0) throw const ValidationException('Amount must be more than zero');
    final now = ctx.now();
    final calendar = await ctx.calendar();
    final id = ctx.ids.newId();
    await _db.transaction(() async {
      final shift = await (_db.select(_db.shifts)..where((s) => s.status.equals('open'))).getSingleOrNull();
      if (paidFromDrawer && shift == null) {
        throw const ConflictException('Open a shift before paying an expense from the cash drawer');
      }
      await _db
          .into(_db.expenses)
          .insert(
            ExpensesCompanion.insert(
              id: id,
              category: cat,
              amount: amount,
              note: Value(optionalText(note, max: 200)),
              createdBy: actor.staffId,
              createdByName: actor.name,
              createdAt: now.millisecondsSinceEpoch,
              businessDate: calendar.businessDateOf(now).key,
              paidFromDrawer: paidFromDrawer,
              shiftId: Value(shift?.id),
            ),
          );
      await ctx.audit(
        actor,
        'expense.added',
        entityType: 'expense',
        entityId: id,
        details: {'category': cat, 'amount': amount, 'drawer': paidFromDrawer},
      );
      await ctx.outbox.changed(Aggregate.expense, id);
    });
    return id;
  }

  Future<void> voidExpense(Actor actor, String id, {required String reason}) async {
    actor.require(Permission.voidExpense);
    final why = requireText(reason, 'Reason', max: 140);
    await _db.transaction(() async {
      final e = await (_db.select(_db.expenses)..where((x) => x.id.equals(id))).getSingleOrNull();
      if (e == null) throw const NotFoundException('Expense not found');
      if (e.voidedAt != null) throw const ConflictException('This expense is already void');
      if (e.paidFromDrawer && e.shiftId != null) {
        final shift = await (_db.select(_db.shifts)..where((s) => s.id.equals(e.shiftId!))).getSingle();
        if (shift.status != 'open') {
          throw const ConflictException('This expense belongs to a closed shift. Reopen the shift to void it.');
        }
      }
      await (_db.update(_db.expenses)..where((x) => x.id.equals(id))).write(
        ExpensesCompanion(
          voidedAt: Value(ctx.nowMs()),
          voidedBy: Value(actor.staffId),
          voidReason: Value(why),
        ),
      );
      await ctx.audit(
        actor,
        'expense.voided',
        entityType: 'expense',
        entityId: id,
        details: {'reason': why, 'amount': e.amount},
      );
      await ctx.outbox.changed(Aggregate.expense, id);
    });
  }

  Stream<List<ExpenseRow>> watchExpenses(BusinessDateRange range) =>
      (_db.select(_db.expenses)
            ..where(
              (e) =>
                  e.businessDate.isBiggerOrEqualValue(range.start.key) &
                  e.businessDate.isSmallerThanValue(range.endExclusive.key),
            )
            ..orderBy([(e) => OrderingTerm(expression: e.createdAt, mode: OrderingMode.desc)]))
          .watch();
}
