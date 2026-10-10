import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/common.dart';
import '../application/order_service.dart';
import '../domain/order_models.dart';

/// Kitchen ticket board for this installation. Tickets are immutable; only
/// their status moves (pending → preparing → ready).
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});
  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  bool _showReady = false;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Expanded(child: Text('Newest first. Corrections are shown in red.')),
              FilterChip(
                label: const Text('Show ready'),
                selected: _showReady,
                onSelected: (v) => setState(() => _showReady = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamView<List<KitchenTicketView>>(
            key: ValueKey(_showReady),
            stream: services.orders.watchTickets(includeReady: _showReady),
            builder: (context, tickets) {
              if (tickets.isEmpty) {
                return const EmptyState(
                  icon: Icons.soup_kitchen_outlined,
                  title: 'No kitchen tickets',
                  message: 'Tickets appear when a cashier taps "Send to kitchen".',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 360,
                  mainAxisExtent: scaledExtent(context, 300),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: tickets.length,
                itemBuilder: (context, i) => _TicketCard(view: tickets[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.view});
  final KitchenTicketView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tk = view.ticket;
    final t = Theme.of(context).textTheme;
    final correction = tk.kind == TicketKind.correction;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(tk.createdAt));
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    final (statusColor, next) = switch (tk.status) {
      TicketStatus.pending => (AppColors.warning, TicketStatus.preparing),
      TicketStatus.preparing => (AppColors.info, TicketStatus.ready),
      _ => (AppColors.success, null),
    };
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: correction ? AppColors.danger : const Color(0xFFE6DED3), width: correction ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(tk.orderRef, style: t.titleLarge, overflow: TextOverflow.ellipsis),
                ),
                StatusChip(label: TicketStatus.label(tk.status), color: statusColor),
              ],
            ),
            Text('KOT #${tk.ticketNo} · ${age.inMinutes} min ago · ${tk.createdByName}', style: t.bodySmall),
            if (correction)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'CORRECTION: ${tk.reason ?? ''}',
                  style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700),
                ),
              ),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final l in view.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${l.quantityDelta < 0 ? 'CANCEL ${-l.quantityDelta}' : l.quantityDelta} × ${l.itemName}${l.variantName == null ? '' : ' (${l.variantName})'}',
                            style: t.titleMedium?.copyWith(
                              color: l.quantityDelta < 0 ? AppColors.danger : null,
                              decoration: l.quantityDelta < 0 ? TextDecoration.lineThrough : null,
                            ),
                          ),
                          if (l.modifiersText != null) Text('+ ${l.modifiersText}'),
                          if (l.note != null) Text('>> ${l.note}', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Reprint ticket',
                  icon: const Icon(Icons.print_outlined),
                  onPressed: () => guard(
                    context,
                    () => services.orders.reprintKot(actor, tk.id),
                    success: 'Reprint queued (marked COPY)',
                  ),
                ),
                // Buttons stack vertically when the card is too narrow.
                Expanded(
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 4,
                    children: [
                      if (tk.status != TicketStatus.pending)
                        TextButton(
                          onPressed: () => guard(
                            context,
                            () => services.orders.setTicketStatus(
                              actor,
                              tk.id,
                              tk.status == TicketStatus.ready ? TicketStatus.preparing : TicketStatus.pending,
                            ),
                          ),
                          child: const Text('Undo'),
                        ),
                      if (next != null)
                        FilledButton(
                          onPressed: () => guard(context, () => services.orders.setTicketStatus(actor, tk.id, next)),
                          child: Text(next == TicketStatus.preparing ? 'Start preparing' : 'Mark ready'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
