import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/sync/host_outbox.dart';

class TableStatus {
  const TableStatus({required this.table, this.openOrderId, this.openOrderNo, this.openSince});
  final DiningTableRow table;
  final String? openOrderId;
  final int? openOrderNo;
  final int? openSince;

  bool get occupied => openOrderId != null;
}

class TableService {
  TableService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  /// Occupancy comes from actual open orders, never a stored flag.
  Stream<List<TableStatus>> watchTableStatus() async* {
    yield await tableStatus();
    await for (final _ in _db.tableUpdates(TableUpdateQuery.onAllTables([_db.diningTables, _db.orders]))) {
      yield await tableStatus();
    }
  }

  Future<List<TableStatus>> tableStatus() async {
    final tables =
        await (_db.select(_db.diningTables)
              ..where((t) => t.archived.equals(false))
              ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.name)]))
            .get();
    final open = await (_db.select(_db.orders)..where((o) => o.status.equals('open') & o.tableId.isNotNull())).get();
    final byTable = {for (final o in open) o.tableId!: o};
    return [
      for (final t in tables)
        TableStatus(
          table: t,
          openOrderId: byTable[t.id]?.id,
          openOrderNo: byTable[t.id]?.orderNo,
          openSince: byTable[t.id]?.createdAt,
        ),
    ];
  }

  Stream<List<DiningTableRow>> watchTables({bool includeArchived = false}) {
    final q = _db.select(_db.diningTables)
      ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.name)]);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    return q.watch();
  }

  Future<String> createTable(Actor actor, {required String name, int? capacity}) async {
    actor.require(Permission.manageTables);
    final n = requireText(name, 'Table name', max: 20);
    if (capacity != null && (capacity < 1 || capacity > 100)) {
      throw const ValidationException('Capacity must be between 1 and 100');
    }
    final id = ctx.ids.newId();
    await _db.transaction(() async {
      final dup = await (_db.select(
        _db.diningTables,
      )..where((t) => t.name.lower().equals(n.toLowerCase()) & t.archived.equals(false))).getSingleOrNull();
      if (dup != null) throw ConflictException('A table named "$n" already exists');
      final count = (await _db.select(_db.diningTables).get()).length;
      await _db
          .into(_db.diningTables)
          .insert(DiningTablesCompanion.insert(id: id, name: n, capacity: Value(capacity), sortOrder: Value(count)));
      await ctx.audit(actor, 'table.created', entityType: 'table', entityId: id, details: {'name': n});
      await ctx.outbox.changed(Aggregate.tables, 'tables');
    });
    return id;
  }

  Future<void> updateTable(Actor actor, String id, {required String name, int? capacity}) async {
    actor.require(Permission.manageTables);
    final n = requireText(name, 'Table name', max: 20);
    if (capacity != null && (capacity < 1 || capacity > 100)) {
      throw const ValidationException('Capacity must be between 1 and 100');
    }
    await _db.transaction(() async {
      final updated = await (_db.update(
        _db.diningTables,
      )..where((t) => t.id.equals(id))).write(DiningTablesCompanion(name: Value(n), capacity: Value(capacity)));
      if (updated == 0) throw const NotFoundException('Table not found');
      await ctx.audit(
        actor,
        'table.updated',
        entityType: 'table',
        entityId: id,
        details: {'name': n, 'capacity': capacity},
      );
      await ctx.outbox.changed(Aggregate.tables, 'tables');
    });
  }

  Future<void> setArchived(Actor actor, String id, bool archived) async {
    actor.require(Permission.manageTables);
    await _db.transaction(() async {
      if (archived) {
        final open = await (_db.select(_db.orders)..where((o) => o.tableId.equals(id) & o.status.equals('open'))).get();
        if (open.isNotEmpty) throw const ConflictException('This table has an open order. Bill or move it first.');
      }
      await (_db.update(
        _db.diningTables,
      )..where((t) => t.id.equals(id))).write(DiningTablesCompanion(archived: Value(archived)));
      await ctx.audit(actor, archived ? 'table.archived' : 'table.restored', entityType: 'table', entityId: id);
      await ctx.outbox.changed(Aggregate.tables, 'tables');
    });
  }
}
