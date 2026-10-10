import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/permissions.dart';
import '../features/auth/presentation/lock_screen.dart';
import '../features/auth/presentation/staff_screen.dart';
import '../features/bills/presentation/bills_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/expenses/presentation/expenses_screen.dart';
import '../features/menu/presentation/menu_admin_screen.dart';
import '../features/orders/presentation/kitchen_screen.dart';
import '../features/orders/presentation/sell_screen.dart';
import '../features/settings/presentation/print_queue_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/shifts/presentation/shift_screen.dart';
import '../features/tables/presentation/tables_screen.dart';
import '../shared/widgets/common.dart';
import 'providers.dart';
import 'runtime.dart';
import 'theme.dart';

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon, this.builder, this.permission);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final WidgetBuilder builder;
  final Permission permission;
}

final _destinations = <_Destination>[
  _Destination(
    'Sell',
    Icons.point_of_sale_outlined,
    Icons.point_of_sale,
    (_) => const SellScreen(),
    Permission.takeOrders,
  ),
  _Destination(
    'Tables',
    Icons.table_restaurant_outlined,
    Icons.table_restaurant,
    (_) => const TablesScreen(),
    Permission.takeOrders,
  ),
  _Destination(
    'Kitchen',
    Icons.soup_kitchen_outlined,
    Icons.soup_kitchen,
    (_) => const KitchenScreen(),
    Permission.kitchenTickets,
  ),
  _Destination(
    'Bills',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
    (_) => const BillsScreen(),
    Permission.viewBills,
  ),
  _Destination(
    'Dashboard',
    Icons.insights_outlined,
    Icons.insights,
    (_) => const DashboardScreen(),
    Permission.viewReports,
  ),
  _Destination(
    'Shift',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
    (_) => const ShiftScreen(),
    Permission.ownShift,
  ),
  _Destination(
    'Expenses',
    Icons.payments_outlined,
    Icons.payments,
    (_) => const ExpensesScreen(),
    Permission.recordExpense,
  ),
  _Destination(
    'Menu',
    Icons.restaurant_menu_outlined,
    Icons.restaurant_menu,
    (_) => const MenuAdminScreen(),
    Permission.manageMenu,
  ),
  _Destination(
    'Print jobs',
    Icons.print_outlined,
    Icons.print,
    (_) => const PrintQueueScreen(),
    Permission.viewPrintQueue,
  ),
  _Destination('Staff', Icons.badge_outlined, Icons.badge, (_) => const StaffScreen(), Permission.manageStaff),
  _Destination(
    'Settings',
    Icons.settings_outlined,
    Icons.settings,
    (_) => const SettingsScreen(),
    Permission.manageSettings,
  ),
];

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(sessionProvider)!;
    final items = _destinations.where((d) => actor.can(d.permission)).toList();
    if (_index >= items.length) _index = 0;
    final size = screenSizeOf(context);
    final isDemo = ref.watch(runtimeProvider).mode == AppMode.demo;
    final body = KeyedSubtree(key: ValueKey(items[_index].label), child: items[_index].builder(context));

    final appBar = AppBar(
      title: Text(items[_index].label),
      actions: [
        const _LocalOnlyChip(),
        const _ShiftChip(),
        const _PrintStatusButton(),
        _UserMenu(actor: actor),
      ],
    );

    Widget content;
    if (size == ScreenSize.phone) {
      final primary = items.take(4).toList();
      final overflow = items.skip(4).toList();
      content = Scaffold(
        appBar: appBar,
        body: body,
        bottomNavigationBar: items.length <= 1
            ? null
            : NavigationBar(
                selectedIndex: _index < 4 ? _index : primary.length,
                onDestinationSelected: (i) async {
                  if (i < primary.length) {
                    setState(() => _index = i);
                  } else {
                    final picked = await showModalBottomSheet<int>(
                      context: context,
                      builder: (c) => SafeArea(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            for (var j = 0; j < overflow.length; j++)
                              ListTile(
                                leading: Icon(overflow[j].icon),
                                title: Text(overflow[j].label),
                                onTap: () => Navigator.pop(c, j + 4),
                              ),
                          ],
                        ),
                      ),
                    );
                    if (picked != null) setState(() => _index = picked);
                  }
                },
                destinations: [
                  for (final d in primary)
                    NavigationDestination(icon: Icon(d.icon), selectedIcon: Icon(d.selectedIcon), label: d.label),
                  if (overflow.isNotEmpty) const NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
                ],
              ),
      );
    } else {
      content = Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            if (items.length > 1)
              SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: MediaQuery.sizeOf(context).height - kToolbarHeight - 24),
                  child: IntrinsicHeight(
                    child: NavigationRail(
                      extended: size == ScreenSize.desktop,
                      selectedIndex: _index,
                      labelType: size == ScreenSize.desktop
                          ? NavigationRailLabelType.none
                          : NavigationRailLabelType.all,
                      onDestinationSelected: (i) => setState(() => _index = i),
                      destinations: [
                        for (final d in items)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            selectedIcon: Icon(d.selectedIcon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            if (items.length > 1) const VerticalDivider(width: 1),
            Expanded(child: body),
          ],
        ),
      );
    }
    if (!isDemo) return content;
    // The banner takes the status-bar inset, so the scaffold below must not
    // add it again.
    return Column(
      children: [
        const DemoBanner(),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: content),
        ),
      ],
    );
  }
}

class _LocalOnlyChip extends StatelessWidget {
  const _LocalOnlyChip();
  @override
  Widget build(BuildContext context) {
    if (screenSizeOf(context) == ScreenSize.phone) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: 'All data is saved on this device only. There is no cloud sync.',
        child: StatusChip(label: 'This device only', color: AppColors.info, icon: Icons.phonelink_lock_outlined),
      ),
    );
  }
}

class _ShiftChip extends ConsumerWidget {
  const _ShiftChip();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(currentShiftProvider);
    final open = shift.value != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: StatusChip(
        label: open ? 'Shift open' : 'No shift',
        color: open ? AppColors.success : AppColors.warning,
        icon: open ? Icons.lock_open_outlined : Icons.lock_clock_outlined,
      ),
    );
  }
}

class _PrintStatusButton extends ConsumerWidget {
  const _PrintStatusButton();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(printCountsProvider).value;
    final attention = counts?.attention ?? 0;
    final pending = counts?.pending ?? 0;
    final actor = ref.watch(sessionProvider);
    if (actor == null || !actor.can(Permission.viewPrintQueue)) return const SizedBox.shrink();
    return IconButton(
      tooltip: attention > 0
          ? '$attention print job(s) need attention'
          : (pending > 0 ? '$pending printing' : 'Printing: all clear'),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Print jobs')),
            body: const PrintQueueScreen(),
          ),
        ),
      ),
      icon: Badge(
        isLabelVisible: attention > 0 || pending > 0,
        backgroundColor: attention > 0 ? AppColors.danger : AppColors.info,
        label: Text('${attention > 0 ? attention : pending}'),
        child: Icon(attention > 0 ? Icons.print_disabled_outlined : Icons.print_outlined),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({required this.actor});
  final Actor actor;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
    tooltip: actor.name,
    icon: const Icon(Icons.account_circle_outlined),
    onSelected: (v) async {
      switch (v) {
        case 'lock':
          ref.read(sessionProvider.notifier).logout();
        case 'pin':
          await showChangePinDialog(context, ref);
      }
    },
    itemBuilder: (_) => [
      PopupMenuItem(enabled: false, child: Text('${actor.name} · ${actor.role.label}')),
      const PopupMenuItem(value: 'pin', child: Text('Change my PIN')),
      const PopupMenuItem(value: 'lock', child: Text('Lock / switch user')),
    ],
  );
}
