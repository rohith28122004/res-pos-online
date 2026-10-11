import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';

final deviceSyncProvider = Provider<DeviceSync>((ref) => ref.watch(deviceRuntimeProvider).sync);

final deviceLinkProvider = StreamProvider<ClientLinkRow?>((ref) {
  final db = ref.watch(deviceRuntimeProvider).db;
  return db.select(db.clientLink).watchSingleOrNull();
});

final deviceSessionProvider = StreamProvider<ClientSessionRow?>(
  (ref) => ref.watch(deviceSyncProvider).watchSession(),
);

final linkStatusProvider = StreamProvider<LinkStatus>((ref) async* {
  final sync = ref.watch(deviceSyncProvider);
  yield sync.currentStatus;
  yield* sync.status;
});

/// The phone's cached copy of the POS: menu, tables, open orders, tickets.
class CacheView {
  const CacheView({
    this.meta,
    this.menu,
    this.tables = const [],
    this.orders = const {},
    this.tickets = const {},
    this.updatedAt,
  });

  final Map<String, Object?>? meta;
  final Map<String, Object?>? menu;
  final List<Map<String, Object?>> tables;
  final Map<String, Map<String, Object?>> orders;
  final Map<String, Map<String, Object?>> tickets;
  final int? updatedAt;

  List<Map<String, Object?>> get categories => [
    for (final c in (menu?['categories'] as List?) ?? const []) (c! as Map).cast<String, Object?>(),
  ];

  List<Map<String, Object?>> get items => [
    for (final i in (menu?['items'] as List?) ?? const []) (i! as Map).cast<String, Object?>(),
  ];

  Map<String, Object?>? item(String id) => items.where((i) => i['itemId'] == id).firstOrNull;

  /// False when the café has no kitchen: waiters prepare orders themselves.
  bool get kitchenEnabled => meta?['kitchenEnabled'] as bool? ?? true;

  /// Open order on a table, from the accepted orders the POS sent.
  Map<String, Object?>? openOrderForTable(String tableId) =>
      orders.values.where((o) => o['tableId'] == tableId && o['status'] == 'open').firstOrNull;

  List<Map<String, Object?>> get openOrders =>
      orders.values.where((o) => o['status'] == 'open').toList()
        ..sort((a, b) => (a['orderNo']! as int).compareTo(b['orderNo']! as int));

  static CacheView of(List<CacheEntryRow> rows) {
    Map<String, Object?>? meta;
    Map<String, Object?>? menu;
    var tables = <Map<String, Object?>>[];
    final orders = <String, Map<String, Object?>>{};
    final tickets = <String, Map<String, Object?>>{};
    int? updated;
    for (final r in rows) {
      updated = updated == null || r.updatedAt > updated ? r.updatedAt : updated;
      final v = jsonDecode(r.json);
      switch (r.kind) {
        case 'meta':
          meta = (v as Map).cast<String, Object?>();
        case 'menu':
          menu = (v as Map).cast<String, Object?>();
        case 'tables':
          tables = [for (final t in v as List) (t! as Map).cast<String, Object?>()];
        case 'order':
          final o = (v as Map).cast<String, Object?>();
          orders[o['orderId']! as String] = o;
        case 'ticket':
          final t = (v as Map).cast<String, Object?>();
          tickets[t['ticketId']! as String] = t;
      }
    }
    return CacheView(meta: meta, menu: menu, tables: tables, orders: orders, tickets: tickets, updatedAt: updated);
  }
}

final cacheViewProvider = StreamProvider<CacheView>(
  (ref) => ref.watch(deviceSyncProvider).watchCache().map(CacheView.of),
);

final myCommandsProvider = StreamProvider<List<PendingCommandRow>>((ref) {
  final session = ref.watch(deviceSessionProvider).value;
  if (session == null) return Stream.value(const []);
  return ref.watch(deviceSyncProvider).watchCommands(session.staffId);
});
