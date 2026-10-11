import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_providers.dart';

/// What this phone sent and what the POS answered. Nothing is shown as
/// accepted unless the POS said so.
class SentCommandsList extends ConsumerWidget {
  const SentCommandsList({super.key});

  static (String, Color, IconData) describe(PendingCommandRow c) => switch (c.state) {
    CommandState.queued => ('Saved on this phone — waiting for the POS', AppColors.warning, Icons.schedule),
    CommandState.sending => ('Sending to the POS…', AppColors.info, Icons.upload_outlined),
    CommandState.relayed => ('Waiting in the cloud — the POS has not answered yet', AppColors.info, Icons.cloud_queue),
    CommandState.accepted => ('Accepted by the POS', AppColors.success, Icons.check_circle_outline),
    CommandState.rejected => ('Not accepted', AppColors.danger, Icons.error_outline),
    CommandState.needsReview => ('Check before sending again', AppColors.warning, Icons.rate_review_outlined),
    _ => (c.state, AppColors.ink, Icons.help_outline),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commands = ref.watch(myCommandsProvider).value ?? const [];
    if (commands.isEmpty) {
      return const EmptyState(
        icon: Icons.outbox_outlined,
        title: 'Nothing sent yet',
        message: 'Orders you send appear here with the POS answer.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: commands.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _CommandTile(command: commands[i]),
    );
  }
}

class _CommandTile extends ConsumerWidget {
  const _CommandTile({required this.command});
  final PendingCommandRow command;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = command;
    final (label, color, icon) = SentCommandsList.describe(c);
    final result = c.resultJson == null
        ? null
        : CommandResult.fromJson((jsonDecode(c.resultJson!) as Map).cast<String, Object?>());
    final sync = ref.read(deviceSyncProvider);
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(c.createdAt)).format(context);
    final actions = <Widget>[
      if (c.errorCode == ErrorCode.priceChanged)
        FilledButton(
          onPressed: () => _confirmPrices(context, ref, result),
          child: const Text('See new prices'),
        ),
      if (c.errorCode == ErrorCode.tableOccupied)
        FilledButton(
          onPressed: () => guard(context, () => sync.addToExistingOrder(c.commandId), success: 'Adding to that order'),
          child: Text('Add to order #${result?.error?.details?['orderNo'] ?? ''}'),
        ),
      if (c.state == CommandState.needsReview)
        FilledButton(
          onPressed: () => guard(context, () => sync.resend(c.commandId), success: 'Sending again'),
          child: const Text('Send again'),
        ),
      if (c.state != CommandState.accepted && c.state != CommandState.sending)
        TextButton(
          onPressed: () async {
            final ok = await confirm(
              context,
              title: 'Remove this?',
              message: c.state == CommandState.relayed
                  ? 'It is waiting in the cloud. If the POS receives it later it may still be accepted; check the '
                        'order on the POS.'
                  : 'It will not be sent.',
              confirmLabel: 'Remove',
              destructive: true,
            );
            if (ok && context.mounted) await guard(context, () => sync.discard(c.commandId));
          },
          child: const Text('Remove'),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(c.summary, style: Theme.of(context).textTheme.titleSmall)),
              Text(time, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
          if (result?.result?['ticketNo'] != null)
            Text('Order ${result!.result!['orderRef']} · kitchen ticket #${result.result!['ticketNo']}'),
          if (c.errorMessage != null) Text(c.errorMessage!),
          if (c.lastRoute == 'cloud' && c.state == CommandState.accepted)
            Text('Sent through the cloud', style: Theme.of(context).textTheme.bodySmall),
          if (actions.isNotEmpty) Wrap(spacing: 8, runSpacing: 4, children: actions),
        ],
      ),
    );
  }

  Future<void> _confirmPrices(BuildContext context, WidgetRef ref, CommandResult? result) async {
    final lines = [
      for (final l in (result?.error?.details?['lines'] as List?) ?? const []) (l! as Map).cast<String, Object?>(),
    ];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Prices changed on the POS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final l in lines)
              Text('${l['itemName']}: ${formatMoney(l['expected']! as int)} → ${formatMoney(l['current']! as int)}'),
            const SizedBox(height: 12),
            const Text('Send the order with the new prices?'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send with new prices')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await guard(context, () => ref.read(deviceSyncProvider).confirmNewPrices(command.commandId), success: 'Sending');
    }
  }
}
