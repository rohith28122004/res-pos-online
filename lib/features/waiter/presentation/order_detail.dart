import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/protocol/protocol.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_app.dart';
import '../../devices/presentation/device_providers.dart';
import 'order_builder.dart';

/// An order the POS accepted, as this phone last saw it: lines, who added
/// them, what the kitchen has, and kitchen progress.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;

  static String ticketLabel(String status) => switch (status) {
    'pending' => 'Waiting',
    'preparing' => 'Preparing',
    'ready' => 'Ready',
    _ => status,
  };

  static Color ticketColor(String status) => switch (status) {
    'ready' => AppColors.success,
    'preparing' => AppColors.info,
    _ => AppColors.warning,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheViewProvider).value ?? const CacheView();
    final order = cache.orders[orderId];
    if (order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Order')),
        body: const EmptyState(icon: Icons.receipt_long_outlined, title: 'This order is not on this phone yet'),
      );
    }
    final open = order['status'] == 'open';
    final lines = [for (final l in order['lines']! as List) (l! as Map).cast<String, Object?>()];
    final unsent = lines.any((l) => (l['quantity']! as int) > (l['sentQuantity']! as int));
    final tickets = cache.tickets.values.where((t) => t['orderId'] == orderId).toList()
      ..sort((a, b) => (a['ticketNo']! as int).compareTo(b['ticketNo']! as int));
    return Scaffold(
      appBar: AppBar(title: Text(order['orderRef']! as String)),
      body: Column(
        children: [
          const LinkBanner(),
          if (!open)
            Material(
              color: AppColors.info.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  order['status'] == 'finalized' ? 'This order has been billed.' : 'This order was cancelled.',
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                ListTile(
                  title: Text('Opened by ${order['createdByName']}'),
                  subtitle: Text(
                    [
                      if (order['guestCount'] != null) '${order['guestCount']} guests',
                      if (order['estimatedTotal'] != null) 'about ${formatMoney(order['estimatedTotal']! as int)}',
                    ].join(' · '),
                  ),
                ),
                if (tickets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final t in tickets)
                          StatusChip(
                            label: 'KOT #${t['ticketNo']} · ${ticketLabel(t['status']! as String)}',
                            color: ticketColor(t['status']! as String),
                            icon: t['kind'] == 'correction' ? Icons.undo : Icons.soup_kitchen_outlined,
                          ),
                      ],
                    ),
                  ),
                const Divider(),
                for (final l in lines)
                  ListTile(
                    title: Text(
                      [
                        l['itemName'],
                        if (l['variantName'] != null) '(${l['variantName']})',
                        if ((l['modifiers']! as List).isNotEmpty) '+ ${(l['modifiers']! as List).join(', ')}',
                      ].join(' '),
                    ),
                    subtitle: Text(
                      [
                        if (l['createdByName'] != null) 'by ${l['createdByName']}',
                        if ((l['sentQuantity']! as int) < (l['quantity']! as int))
                          '${(l['quantity']! as int) - (l['sentQuantity']! as int)} not sent to the kitchen yet',
                        if (l['note'] != null) 'Note: ${l['note']}',
                      ].join(' · '),
                    ),
                    trailing: Text('× ${l['quantity']}', style: Theme.of(context).textTheme.titleMedium),
                    onTap: open ? () => _changeQuantity(context, ref, order, l) : null,
                  ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: !open
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    if (unsent)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => guard(
                            context,
                            () => ref
                                .read(deviceSyncProvider)
                                .enqueue(
                                  action: CommandAction.orderSendToKitchen,
                                  aggregateId: orderId,
                                  payload: const {},
                                  summary: '${order['orderRef']}: send to kitchen',
                                ),
                            success: 'Sent to the POS',
                          ),
                          child: const Text('Send unsent items'),
                        ),
                      ),
                    if (unsent) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add items'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => OrderBuilderScreen(
                              orderType: order['orderType']! as String,
                              tableId: order['tableId'] as String?,
                              tableLabel: order['tableLabel'] as String?,
                              orderId: orderId,
                              orderRef: order['orderRef']! as String,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _changeQuantity(
    BuildContext context,
    WidgetRef ref,
    Map<String, Object?> order,
    Map<String, Object?> line,
  ) async {
    final current = line['quantity']! as int;
    final sent = line['sentQuantity']! as int;
    var qty = current;
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(line['itemName']! as String),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: qty <= 0 ? null : () => setLocal(() => qty--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$qty', style: Theme.of(c).textTheme.headlineSmall),
                  IconButton(
                    onPressed: qty >= 99 ? null : () => setLocal(() => qty++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              if (qty < sent) ...[
                const Text('The kitchen already has some of these. Cancelling them needs a reason and the owner.'),
                TextField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: qty == current ? null : () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) {
      reason.dispose();
      return;
    }
    String? approvalId;
    if (qty < sent) {
      approvalId = await _askOwner(context, ref);
      if (approvalId == null || !context.mounted) {
        reason.dispose();
        return;
      }
    }
    await guard(
      context,
      () => ref
          .read(deviceSyncProvider)
          .enqueue(
            action: CommandAction.orderChangeQuantity,
            aggregateId: orderId,
            expectedRevision: order['revision']! as int,
            payload: {
              'lineId': line['lineId'],
              'quantity': qty,
              if (reason.text.trim().isNotEmpty) 'reason': reason.text.trim(),
              'approvalId': ?approvalId,
            },
            summary: '${order['orderRef']}: ${line['itemName']} → $qty',
          ),
      success: 'Sent to the POS',
    );
    reason.dispose();
  }

  /// The owner types their email and password on this phone; it goes sealed
  /// to the POS, which returns a single-use approval.
  static Future<String?> _askOwner(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final password = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Owner approval'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The owner signs here to approve. The password goes only to the POS.'),
            const SizedBox(height: 12),
            EmailField(controller: email, label: 'Owner email'),
            const SizedBox(height: 8),
            PasswordField(controller: password, label: 'Owner password'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Approve')),
        ],
      ),
    );
    String? id;
    if (ok == true && context.mounted) {
      id = await guard(
        context,
        () =>
            ref.read(deviceSyncProvider).requestApproval(email.text, password.text, 'cancel items sent to the kitchen'),
      );
    }
    email.dispose();
    password.dispose();
    return id;
  }
}
