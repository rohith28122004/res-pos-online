import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/common.dart';
import '../../tables/application/table_service.dart';
import '../domain/order_models.dart';
import 'pos_screen.dart';

class SellScreen extends ConsumerWidget {
  const SellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('New takeaway'),
                onPressed: () => startOrder(context, ref, OrderType.takeaway),
              ),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.table_restaurant_outlined),
                label: const Text('New dine-in'),
                onPressed: () => startDineIn(context, ref),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.delivery_dining_outlined),
                label: const Text('New delivery'),
                onPressed: () => startOrder(context, ref, OrderType.delivery),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: StreamView<List<OpenOrderSummary>>(
            stream: services.orders.watchOpenOrders(),
            builder: (context, orders) {
              if (orders.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_outlined,
                  title: 'No open orders',
                  message:
                      'Start a takeaway, dine-in or delivery order. Orders are saved as you go and survive restarts.',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 320,
                  mainAxisExtent: scaledExtent(context, 128),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: orders.length,
                itemBuilder: (context, i) => _OrderCard(summary: orders[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.summary});
  final OpenOrderSummary summary;

  /// Open this long, an order is shown in amber so it is not forgotten.
  static const _longOpen = Duration(minutes: 45);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final order = summary.order;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(order.createdAt));
    final long = age >= _longOpen;
    final type = OrderType.parse(order.orderType);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openPos(context, order.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(orderTypeIcon(type), size: 20, color: AppColors.accent, semanticLabel: type.label),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(summary.reference, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (summary.hasUnsent) const StatusChip(label: 'Not sent', color: AppColors.warning),
                ],
              ),
              Text(
                '${summary.itemCount} item(s) · by ${order.createdByName}',
                style: t.bodyMedium?.copyWith(color: Colors.black54),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      formatMoney(summary.total),
                      style: t.titleLarge?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.schedule, size: 16, color: long ? AppColors.warning : Colors.black45),
                  const SizedBox(width: 4),
                  Text(
                    _age(age),
                    style: t.bodyMedium?.copyWith(
                      color: long ? AppColors.warning : Colors.black54,
                      fontWeight: long ? FontWeight.w600 : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData orderTypeIcon(OrderType type) => switch (type) {
  OrderType.takeaway => Icons.shopping_bag_outlined,
  OrderType.dineIn => Icons.table_restaurant_outlined,
  OrderType.delivery => Icons.delivery_dining_outlined,
};

String _age(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes < 0 ? 0 : d.inMinutes} min';
  if (d.inHours < 48) return '${d.inHours} h ${d.inMinutes % 60} min';
  return '${d.inDays} days';
}

Future<void> openPos(BuildContext context, String orderId, {bool waiter = false}) =>
    Navigator.of(
      context,
    ).push(
      MaterialPageRoute<void>(
        builder: (_) => PosScreen(orderId: orderId, waiter: waiter),
      ),
    );

Future<void> startOrder(
  BuildContext context,
  WidgetRef ref,
  OrderType type, {
  String? tableId,
  bool waiter = false,
}) async {
  final services = ref.read(servicesProvider);
  final id = await guard(context, () => services.orders.createOrder(requireActor(ref), type: type, tableId: tableId));
  if (id != null && context.mounted) await openPos(context, id, waiter: waiter);
}

Future<void> startDineIn(BuildContext context, WidgetRef ref) async {
  final services = ref.read(servicesProvider);
  final tables = await services.tables.tableStatus();
  if (!context.mounted) return;
  if (tables.isEmpty) {
    await startOrder(context, ref, OrderType.dineIn);
    return;
  }
  final picked = await showDialog<TableStatus>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Choose a table'),
      content: SizedBox(
        width: 420,
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tables)
              SizedBox(
                width: 96,
                height: 64,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(c, t),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: t.occupied ? AppColors.warning.withValues(alpha: 0.1) : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(t.table.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(t.occupied ? 'Occupied' : 'Free', style: const TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
    ),
  );
  if (picked == null || !context.mounted) return;
  if (picked.occupied) {
    await openPos(context, picked.openOrderId!);
  } else {
    await startOrder(context, ref, OrderType.dineIn, tableId: picked.table.id);
  }
}
