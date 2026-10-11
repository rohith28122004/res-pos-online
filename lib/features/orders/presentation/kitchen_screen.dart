import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/widgets/common.dart';
import '../../kitchen/presentation/kitchen_ui.dart';
import '../application/order_service.dart';
import '../domain/order_models.dart';

/// The kitchen board on the POS itself (dark, New → Cooking → Ready). Tickets
/// never change; only their status moves, and here it can also move back.
class KitchenScreen extends ConsumerStatefulWidget {
  const KitchenScreen({super.key});
  @override
  ConsumerState<KitchenScreen> createState() => _KitchenScreenState();
}

class _KitchenScreenState extends ConsumerState<KitchenScreen> {
  late final Stream<List<KitchenTicketView>> _tickets = ref.read(servicesProvider).orders.watchTickets(limit: 80);

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    Future<void> set(KitchenCardData t, String to) =>
        guard(context, () => services.orders.setTicketStatus(actor, t.id, to));
    return Theme(
      data: kitchenTheme(Theme.of(context)),
      child: ColoredBox(
        color: KitchenPalette.dark.background,
        child: StreamView<List<KitchenTicketView>>(
          stream: _tickets,
          builder: (context, tickets) => KitchenBoard(
            tickets: [for (final t in tickets) kitchenCardOf(t)],
            emptyMessage: 'Orders appear here when they are sent to the kitchen.',
            actions: KitchenActions(
              onMove: set,
              onUndo: (t) => set(t, t.status == TicketStatus.ready ? TicketStatus.preparing : TicketStatus.pending),
              onReprint: (t) =>
                  guard(context, () => services.orders.reprintKot(actor, t.id), success: 'Printing a copy'),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kitchen staff signed in on the POS see only the kitchen.
class KitchenHomePage extends ConsumerWidget {
  const KitchenHomePage({super.key, required this.menu});

  /// Account menu (sign out, password).
  final Widget menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(settingsStreamProvider).value?.name ?? '';
    return Theme(
      data: kitchenTheme(Theme.of(context)),
      child: Scaffold(
        appBar: AppBar(
          title: Text(name.isEmpty ? 'Kitchen' : 'Kitchen · $name'),
          actions: [menu],
        ),
        body: const KitchenScreen(),
      ),
    );
  }
}

KitchenCardData kitchenCardOf(KitchenTicketView v) {
  final t = v.ticket;
  return KitchenCardData(
    id: t.id,
    status: t.status,
    orderRef: t.orderRef,
    ticketNo: t.ticketNo,
    createdAt: t.createdAt,
    byName: t.createdByName,
    correction: t.kind == TicketKind.correction,
    reason: t.reason,
    lines: [
      for (final l in v.lines)
        KitchenLineData(
          quantity: l.quantityDelta,
          name: l.itemName,
          variant: l.variantName,
          modifiers: l.modifiersText,
          note: l.note,
        ),
    ],
  );
}
