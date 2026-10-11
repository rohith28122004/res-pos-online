import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../kitchen/presentation/kitchen_ui.dart';
import '../../orders/application/order_service.dart';
import '../../orders/domain/order_models.dart';
import '../../orders/presentation/kitchen_screen.dart';
import '../../orders/presentation/sell_screen.dart';
import '../../tables/application/table_service.dart';

/// What a waiter sees when signing in on the POS itself: tables, open orders
/// and — when the café has no kitchen — the orders to prepare. No payments,
/// reports or settings.
class WaiterTillHome extends ConsumerStatefulWidget {
  const WaiterTillHome({super.key, required this.menu});

  /// Account menu (sign out, password).
  final Widget menu;

  @override
  ConsumerState<WaiterTillHome> createState() => _WaiterTillHomeState();
}

class _WaiterTillHomeState extends ConsumerState<WaiterTillHome> {
  @override
  Widget build(BuildContext context) {
    final actor = requireActor(ref);
    final settings = ref.watch(settingsStreamProvider).value;
    final kitchen = settings?.kitchenEnabled ?? true;
    final tabs = [
      const Tab(icon: Icon(Icons.table_restaurant_outlined), text: 'Tables'),
      const Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
      if (!kitchen) const Tab(icon: Icon(Icons.outdoor_grill_outlined), text: 'To prepare'),
    ];
    return DefaultTabController(
      key: ValueKey(kitchen),
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Waiter · ${actor.name}'),
              if (settings != null) Text(settings.name, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          actions: [widget.menu],
          bottom: TabBar(tabs: tabs),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.shopping_bag_outlined),
          label: const Text('Takeaway order'),
          onPressed: () => startOrder(context, ref, OrderType.takeaway, waiter: true),
        ),
        // Each tab owns its live list, so tabs can come and go (kitchen
        // switched on or off) without re-listening to a used stream.
        body: TabBarView(
          children: [
            _Live(
              watch: () => ref.read(servicesProvider).tables.watchTableStatus(),
              builder: (stream) => _TablesTab(stream: stream),
            ),
            _Live(
              watch: () => ref.read(servicesProvider).orders.watchOpenOrders(),
              builder: (stream) => _OrdersTab(stream: stream, staffId: actor.staffId),
            ),
            if (!kitchen)
              _Live(
                watch: () => ref.read(servicesProvider).orders.watchTickets(limit: 60),
                builder: (stream) => _ToPrepareTab(stream: stream),
              ),
          ],
        ),
      ),
    );
  }
}

/// Creates [watch]'s stream once for the life of this widget.
class _Live<T> extends StatefulWidget {
  const _Live({required this.watch, required this.builder});
  final Stream<T> Function() watch;
  final Widget Function(Stream<T> stream) builder;

  @override
  State<_Live<T>> createState() => _LiveState<T>();
}

class _LiveState<T> extends State<_Live<T>> {
  late final Stream<T> _stream = widget.watch();

  @override
  Widget build(BuildContext context) => widget.builder(_stream);
}

class _TablesTab extends ConsumerWidget {
  const _TablesTab({required this.stream});
  final Stream<List<TableStatus>> stream;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamView<List<TableStatus>>(
    stream: stream,
    builder: (context, tables) {
      if (tables.isEmpty) {
        return const EmptyState(
          icon: Icons.table_restaurant_outlined,
          title: 'No tables yet',
          message: 'The admin adds tables in Settings → Tables. Takeaway orders work without them.',
        );
      }
      final free = tables.where((t) => !t.occupied).length;
      return ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Tap a free table to start an order, or a busy one to add to it. $free of ${tables.length} free.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: scaledExtent(context, 112),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: tables.length,
            itemBuilder: (context, i) => _TableTile(status: tables[i]),
          ),
        ],
      );
    },
  );
}

class _TableTile extends ConsumerWidget {
  const _TableTile({required this.status});
  final TableStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = status;
    final text = Theme.of(context).textTheme;
    final minutes = t.openSince == null
        ? null
        : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t.openSince!)).inMinutes;
    final busy = t.occupied;
    return Material(
      color: busy ? const Color(0xFFFFF1D6) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: busy ? AppColors.warning : const Color(0xFFE6DED3), width: busy ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => busy
            ? openPos(context, t.openOrderId!, waiter: true)
            : startOrder(context, ref, OrderType.dineIn, tableId: t.table.id, waiter: true),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t.table.name,
                      style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    busy ? Icons.people_alt : Icons.add_circle_outline,
                    color: busy ? AppColors.warning : AppColors.success,
                  ),
                ],
              ),
              const Spacer(),
              Text(
                busy
                    ? 'Order #${t.openOrderNo}${minutes == null ? '' : ' · ${minutes < 0 ? 0 : minutes} min'}'
                    : 'Free',
                style: text.bodyLarge?.copyWith(
                  color: busy ? AppColors.warning : AppColors.success,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({required this.stream, required this.staffId});
  final Stream<List<OpenOrderSummary>> stream;
  final String staffId;

  @override
  Widget build(BuildContext context) => StreamView<List<OpenOrderSummary>>(
    stream: stream,
    builder: (context, orders) {
      if (orders.isEmpty) {
        return const EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No open orders',
          message: 'Orders you start appear here until they are paid at the till.',
        );
      }
      final text = Theme.of(context).textTheme;
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
        itemCount: orders.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final o = orders[i];
          final mine = o.order.createdBy == staffId;
          return Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: Icon(orderTypeIcon(OrderType.parse(o.order.orderType)), color: AppColors.accent),
              ),
              title: Text(o.reference, style: text.titleMedium),
              subtitle: Text(
                '${o.itemCount} item(s) · ${formatMoney(o.total)}${mine ? ' · yours' : ' · ${o.order.createdByName}'}',
              ),
              trailing: o.hasUnsent
                  ? const StatusChip(label: 'Not sent', color: AppColors.warning)
                  : const Icon(Icons.chevron_right),
              onTap: () => openPos(context, o.order.id, waiter: true),
            ),
          );
        },
      );
    },
  );
}

/// No kitchen: the waiter makes what was ordered and marks it ready.
class _ToPrepareTab extends ConsumerWidget {
  const _ToPrepareTab({required this.stream});
  final Stream<List<KitchenTicketView>> stream;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    Future<void> set(KitchenCardData t, String to) =>
        guard(context, () => services.orders.setTicketStatus(actor, t.id, to));
    final actions = KitchenActions(
      onMove: set,
      onUndo: (t) => set(t, t.status == TicketStatus.ready ? TicketStatus.preparing : TicketStatus.pending),
    );
    return StreamView<List<KitchenTicketView>>(
      stream: stream,
      builder: (context, views) {
        final cards = [for (final v in views) kitchenCardOf(v)]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        final todo = cards.where((c) => c.status != TicketStatus.ready).toList();
        final done = cards.where((c) => c.status == TicketStatus.ready).toList().reversed.take(5).toList();
        if (todo.isEmpty && done.isEmpty) {
          return const EmptyState(
            icon: Icons.outdoor_grill_outlined,
            title: 'Nothing to prepare',
            message: 'Confirmed orders appear here. Make them, then tap Ready.',
          );
        }
        final text = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
          children: [
            if (todo.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: Text('All orders are ready.')),
              ),
            for (final c in todo) KitchenTicketCard(data: c, actions: actions, palette: KitchenPalette.light),
            if (done.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text('Ready recently', style: text.titleMedium),
              ),
              for (final c in done) KitchenTicketCard(data: c, actions: actions, palette: KitchenPalette.light),
            ],
          ],
        );
      },
    );
  }
}
