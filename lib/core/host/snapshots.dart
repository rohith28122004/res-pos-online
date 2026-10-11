import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/orders/domain/order_models.dart';
import '../database/app_database.dart';
import '../protocol/protocol.dart';
import '../service_context.dart';
import '../sync/host_outbox.dart';

/// Device snapshots and event reads (docs/PROTOCOL.md §5.3, §7.1). Each read
/// runs in one transaction, so the cursor and the data always match.
class HostReads {
  HostReads(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  static const kitchenReadyWindow = Duration(hours: 2);

  Future<int> _latest(int epoch) async {
    final max = _db.hostEvents.sequence.max();
    final q = _db.selectOnly(_db.hostEvents)
      ..addColumns([max])
      ..where(_db.hostEvents.hostEpoch.equals(epoch));
    return (await q.getSingle()).read(max) ?? 0;
  }

  Future<Map<String, Object?>> snapshot(String scope) => _db.transaction(() async {
    final epoch = await ctx.outbox.currentEpoch();
    final cursor = await _latest(epoch);
    final settings = await ctx.settings();
    final views = EventViews(ctx);
    final out = <String, Object?>{
      'hostEpoch': epoch,
      'cursor': cursor,
      'generatedAt': ctx.nowMs(),
      'restaurantName': settings.name,
      'scope': scope,
    };
    if (scope == 'waiter') {
      out['menu'] = await _menu();
      final tables =
          await (_db.select(_db.diningTables)
                ..where((t) => t.archived.equals(false))
                ..orderBy([(t) => OrderingTerm(expression: t.sortOrder), (t) => OrderingTerm(expression: t.name)]))
              .get();
      final open =
          await (_db.select(_db.orders)
                ..where((o) => o.status.equals(OrderStatus.open))
                ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
              .get();
      final byTable = {for (final o in open) ?o.tableId: o};
      out['tables'] = [
        for (final t in tables)
          {
            'tableId': t.id,
            'name': t.name,
            'capacity': t.capacity,
            'openOrderId': byTable[t.id]?.id,
            'openOrderNo': byTable[t.id]?.orderNo,
          },
      ];
      out['orders'] = [for (final o in open) await views.orderView(o.id)];
    } else {
      final since = ctx.nowMs() - kitchenReadyWindow.inMilliseconds;
      final tickets =
          await (_db.select(_db.kitchenTickets)
                ..where((t) => t.status.isNotValue(TicketStatus.ready) | t.updatedAt.isBiggerThanValue(since))
                ..orderBy([(t) => OrderingTerm(expression: t.createdAt)])
                ..limit(200))
              .get();
      final lines = tickets.isEmpty
          ? <KitchenTicketLineRow>[]
          : await (_db.select(_db.kitchenTicketLines)..where((l) => l.ticketId.isIn(tickets.map((t) => t.id)))).get();
      out['tickets'] = [
        for (final t in tickets) EventViews.ticketViewOf(t, lines.where((l) => l.ticketId == t.id).toList()),
      ];
    }
    return out;
  });

  Future<Map<String, Object?>> _menu() async {
    final cats =
        await (_db.select(_db.categories)
              ..where((c) => c.archived.equals(false))
              ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
            .get();
    final items =
        await (_db.select(_db.menuItems)
              ..where((i) => i.archived.equals(false))
              ..orderBy([(i) => OrderingTerm(expression: i.sortOrder), (i) => OrderingTerm(expression: i.name)]))
            .get();
    final variants = await (_db.select(_db.itemVariants)..where((v) => v.archived.equals(false))).get();
    final mods = await (_db.select(_db.itemModifiers)..where((m) => m.archived.equals(false))).get();
    return {
      'categories': [
        for (final c in cats) {'categoryId': c.id, 'name': c.name},
      ],
      'items': [
        for (final i in items)
          {
            'itemId': i.id,
            'categoryId': i.categoryId,
            'name': i.name,
            'price': i.price,
            'available': i.available,
            'variants': [
              for (final v
                  in variants.where((v) => v.itemId == i.id).toList()
                    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                {'variantId': v.id, 'name': v.name, 'price': v.price},
            ],
            'modifiers': [
              for (final m
                  in mods.where((m) => m.itemId == i.id).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
                {'modifierId': m.id, 'name': m.name, 'price': m.price},
            ],
          },
      ],
    };
  }

  /// Device-audience events after [after] in [epoch], and the watermark the
  /// device may advance its cursor to (it also covers cloud-only events).
  /// `snapshotRequired` when the epoch changed or the events were pruned.
  Future<Map<String, Object?>> eventsAfter(int epoch, int after, {int limit = 200}) => _db.transaction(() async {
    final current = await ctx.outbox.currentEpoch();
    final latest = await _latest(current);
    if (epoch != current || after > latest) {
      return {'events': const <Object?>[], 'through': latest, 'hostEpoch': current, 'snapshotRequired': true};
    }
    final firstKept = _db.hostEvents.sequence.min();
    final q = _db.selectOnly(_db.hostEvents)
      ..addColumns([firstKept])
      ..where(_db.hostEvents.hostEpoch.equals(current));
    final first = (await q.getSingle()).read(firstKept);
    if (first != null && after < first - 1) {
      return {'events': const <Object?>[], 'through': latest, 'hostEpoch': current, 'snapshotRequired': true};
    }
    final rows =
        await (_db.select(_db.hostEvents)
              ..where(
                (e) =>
                    e.hostEpoch.equals(current) &
                    e.sequence.isBiggerThanValue(after) &
                    e.audience.equals(EventAudience.devices),
              )
              ..orderBy([(e) => OrderingTerm(expression: e.sequence)])
              ..limit(limit))
            .get();
    final complete = rows.length < limit;
    return {
      'events': [for (final r in rows) jsonDecode(r.eventJson)],
      // If the page is full, only promise up to the last event returned.
      'through': complete ? latest : rows.last.sequence,
      'hostEpoch': current,
      'snapshotRequired': false,
    };
  });
}
