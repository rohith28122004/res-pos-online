import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/sync/device_sync.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_app.dart';
import '../../devices/presentation/device_providers.dart';
import 'order_builder.dart';
import 'order_detail.dart';
import 'sent_commands.dart';

/// Waiter phone: tables (with occupancy), open orders, and what this phone
/// sent and what the POS answered.
class WaiterHomeScreen extends ConsumerWidget {
  const WaiterHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(myCommandsProvider).value ?? const [];
    final open = commands.where((c) => CommandState.open.contains(c.state)).length;
    final attention = commands
        .where((c) => c.state == CommandState.rejected || c.state == CommandState.needsReview)
        .length;
    final restaurant = ref.watch(deviceLinkProvider).value?.restaurantName ?? 'Café';
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(restaurant),
          actions: const [DeviceMenuButton()],
          bottom: TabBar(
            tabs: [
              const Tab(text: 'Tables'),
              const Tab(text: 'Orders'),
              Tab(
                child: Badge(
                  isLabelVisible: open + attention > 0,
                  backgroundColor: attention > 0 ? AppColors.danger : AppColors.info,
                  label: Text('${attention > 0 ? attention : open}'),
                  child: const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('Sent')),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.shopping_bag_outlined),
          label: const Text('Takeaway'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const OrderBuilderScreen(orderType: 'takeaway')),
          ),
        ),
        body: const Column(
          children: [
            LinkBanner(),
            Expanded(child: TabBarView(children: [_TablesTab(), _OrdersTab(), SentCommandsList()])),
          ],
        ),
      ),
    );
  }
}

class _TablesTab extends ConsumerWidget {
  const _TablesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheViewProvider).value ?? const CacheView();
    final commands = ref.watch(myCommandsProvider).value ?? const [];
    if (cache.menu == null) {
      return EmptyState(
        icon: Icons.cloud_download_outlined,
        title: 'No menu yet',
        message: 'Connect to the POS once to load the menu and tables.',
        action: OutlinedButton(
          onPressed: () => guard(context, ref.read(deviceSyncProvider).refresh),
          child: const Text('Try now'),
        ),
      );
    }
    if (cache.tables.isEmpty) {
      return const EmptyState(
        icon: Icons.table_restaurant_outlined,
        title: 'No tables',
        message: 'Tables are set up on the POS. Takeaway orders work without them.',
      );
    }
    return GridView.extent(
      maxCrossAxisExtent: 180,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.25,
      children: [
        for (final t in cache.tables)
          Builder(
            builder: (context) {
              final tableId = t['tableId']! as String;
              final order = cache.openOrderForTable(tableId);
              final waiting = commands.any(
                (c) => CommandState.open.contains(c.state) && c.summary.startsWith('${t['name']}:'),
              );
              final busy = order != null;
              return Card(
                color: busy ? AppColors.accent.withValues(alpha: 0.10) : null,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => busy
                          ? OrderDetailScreen(orderId: order['orderId']! as String)
                          : OrderBuilderScreen(
                              orderType: 'dine_in',
                              tableId: tableId,
                              tableLabel: t['name']! as String,
                            ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['name']! as String, style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        if (busy)
                          Text(
                            '#${order['orderNo']} · ${order['createdByName']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          const Text('Free'),
                        if (waiting)
                          const Text('Sending from this phone…', style: TextStyle(color: AppColors.info, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheViewProvider).value ?? const CacheView();
    final orders = cache.openOrders;
    if (orders.isEmpty) {
      return const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'No open orders',
        message: 'Orders the POS accepted appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        for (final o in orders)
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text(o['orderRef']! as String),
            subtitle: Text(
              '${o['createdByName']} · ${(o['lines']! as List).length} line(s)'
              '${o['estimatedTotal'] == null ? '' : ' · about ${formatMoney(o['estimatedTotal']! as int)}'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => OrderDetailScreen(orderId: o['orderId']! as String)),
            ),
          ),
      ],
    );
  }
}
