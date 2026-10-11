import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/security/permissions.dart';
import '../../../shared/widgets/common.dart';
import '../../orders/domain/order_models.dart';
import '../../orders/presentation/sell_screen.dart';
import '../application/table_service.dart';

class TablesScreen extends ConsumerWidget {
  const TablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = ref.watch(sessionProvider)!;
    final editButton = actor.can(Permission.manageTables)
        ? OutlinedButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit tables'),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const TablesAdminScreen())),
          )
        : null;
    return StreamView<List<TableStatus>>(
      stream: services.tables.watchTableStatus(),
      builder: (context, tables) {
        if (tables.isEmpty) {
          return EmptyState(
            icon: Icons.table_restaurant_outlined,
            title: 'No tables yet',
            message:
                'Tables are optional. Owners can add them with "Edit tables". Takeaway and delivery work without tables.',
            action: editButton,
          );
        }
        final busy = tables.where((t) => t.occupied).length;
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      StatusChip(
                        label: '${tables.length - busy} free',
                        color: AppColors.success,
                        icon: Icons.event_seat_outlined,
                      ),
                      StatusChip(label: '$busy occupied', color: AppColors.warning, icon: Icons.people_alt_outlined),
                    ],
                  ),
                  ?editButton,
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  mainAxisExtent: scaledExtent(context, 120),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: tables.length,
                itemBuilder: (context, i) => _TableTile(status: tables[i]),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TableTile extends ConsumerWidget {
  const _TableTile({required this.status});
  final TableStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = status;
    final text = Theme.of(context).textTheme;
    final since = t.openSince == null
        ? null
        : DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t.openSince!)).inMinutes;
    return Card(
      color: t.occupied ? const Color(0xFFFFF4E0) : Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => t.occupied
            ? openPos(context, t.openOrderId!)
            : startOrder(context, ref, OrderType.dineIn, tableId: t.table.id),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.table.name, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (t.occupied && since != null)
                Text('Open ${since < 0 ? 0 : since} min', style: text.bodyMedium?.copyWith(color: Colors.black54))
              else if (t.table.capacity != null)
                Text('${t.table.capacity} seats', style: text.bodyMedium?.copyWith(color: Colors.black54)),
              const Spacer(),
              StatusChip(
                label: t.occupied ? 'Occupied · #${t.openOrderNo}' : 'Free',
                color: t.occupied ? AppColors.warning : AppColors.success,
                icon: t.occupied ? Icons.people_alt_outlined : Icons.event_seat_outlined,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TablesAdminScreen extends ConsumerWidget {
  const TablesAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Scaffold(
      appBar: AppBar(title: const Text('Edit tables')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add table'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: StreamView<List<DiningTableRow>>(
        stream: services.tables.watchTables(),
        builder: (context, tables) => tables.isEmpty
            ? const EmptyState(icon: Icons.table_restaurant_outlined, title: 'No tables')
            : ListView(
                children: [
                  for (final t in tables)
                    ListTile(
                      title: Text(t.name),
                      subtitle: Text(t.capacity == null ? 'Capacity not set' : '${t.capacity} seats'),
                      trailing: Wrap(
                        children: [
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _edit(context, ref, t),
                          ),
                          IconButton(
                            tooltip: 'Archive',
                            icon: const Icon(Icons.archive_outlined),
                            onPressed: () async {
                              if (await confirm(
                                    context,
                                    title: 'Archive ${t.name}?',
                                    message: 'It will disappear from the tables view. Past bills keep its name.',
                                  ) &&
                                  context.mounted) {
                                await guard(context, () => services.tables.setArchived(actor, t.id, true));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, DiningTableRow? t) async {
    final name = TextEditingController(text: t?.name ?? '');
    final cap = TextEditingController(text: t?.capacity?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t == null ? 'Add table' : 'Edit table'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Name (e.g. T1, Patio 2)'),
            ),
            TextField(
              controller: cap,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Seats (optional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      final services = ref.read(servicesProvider);
      final actor = requireActor(ref);
      final capacity = int.tryParse(cap.text.trim());
      await guard(context, () async {
        if (t == null) {
          await services.tables.createTable(actor, name: name.text, capacity: capacity);
        } else {
          await services.tables.updateTable(actor, t.id, name: name.text, capacity: capacity);
        }
      });
    }
    name.dispose();
    cap.dispose();
  }
}
