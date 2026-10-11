import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/shell.dart';
import '../../../app/theme.dart';
import '../../../core/host/host_connectivity.dart';
import '../../../core/security/permissions.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/staff_screen.dart';
import '../../bills/presentation/bills_screen.dart';
import '../../dashboard/application/report_service.dart';
import '../../dashboard/presentation/dashboard_screen.dart';
import '../../devices/presentation/connected_devices_screen.dart';
import '../../expenses/presentation/expenses_screen.dart';
import '../../kitchen/presentation/kitchen_ui.dart';
import '../../menu/presentation/menu_admin_screen.dart';
import '../../orders/application/order_service.dart';
import '../../orders/domain/order_models.dart';
import '../../orders/presentation/kitchen_screen.dart';
import '../../orders/presentation/sell_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shifts/presentation/shift_screen.dart';
import '../../tables/presentation/tables_screen.dart';

/// Home for the admin and cashiers: today at a glance, then big buttons —
/// "Daily work" for running the café and "Manage" for the admin's setup.
/// Every button opens one page; back returns here.
class AdminHome extends ConsumerStatefulWidget {
  const AdminHome({super.key});
  @override
  ConsumerState<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends ConsumerState<AdminHome> {
  late final Stream<DashboardData>? _today = _todayStream();

  /// Today's sales, refreshed whenever a bill or refund is saved.
  Stream<DashboardData>? _todayStream() {
    final actor = ref.read(sessionProvider);
    if (actor == null || !actor.can(Permission.viewReports)) return null;
    final services = ref.read(servicesProvider);
    Future<DashboardData> load() async {
      final cal = await services.ctx.calendar();
      final today = cal.businessDateOf(services.ctx.now());
      return services.reports.dashboard(actor, BusinessDateRange(today, today.addDays(1)));
    }

    final db = services.ctx.db;
    return () async* {
      yield await load();
      await for (final _ in db.tableUpdates(TableUpdateQuery.onAllTables([db.bills, db.refunds]))) {
        yield await load();
      }
    }();
  }

  void _page(String title, Widget body) =>
      Navigator.of(
        context,
      ).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text(title)),
            body: body,
          ),
        ),
      );

  void _fullPage(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _newOrder() async {
    final picked = await showModalBottomSheet<OrderType>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('New order', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final (type, title, subtitle) in [
                (OrderType.takeaway, 'Takeaway', 'Customer takes it away'),
                (OrderType.dineIn, 'Dine-in', 'Choose a table'),
                (OrderType.delivery, 'Delivery', 'Delivered to the customer'),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Icon(orderTypeIcon(type), size: 32, color: AppColors.accent),
                      title: Text(title, style: Theme.of(c).textTheme.titleMedium),
                      subtitle: Text(subtitle),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(c, type),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == OrderType.dineIn) {
      await startDineIn(context, ref);
    } else {
      await startOrder(context, ref, picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actor = ref.watch(sessionProvider)!;
    final settings = ref.watch(settingsStreamProvider).value;
    final kitchenOn = settings?.kitchenEnabled ?? true;
    final can = actor.can;
    final daily = <Widget>[
      if (can(Permission.takeOrders))
        _HomeTile(
          icon: Icons.add_shopping_cart,
          title: 'New order',
          subtitle: 'Takeaway, table or delivery',
          primary: true,
          onTap: _newOrder,
        ),
      if (can(Permission.takeOrders))
        _LiveTile<List<OpenOrderSummary>>(
          key: const ValueKey('open-orders'),
          watch: () => ref.read(servicesProvider).orders.watchOpenOrders(),
          builder: (context, open) => _HomeTile(
            icon: Icons.receipt_long_outlined,
            title: 'Open orders',
            subtitle: open == null ? 'Orders not paid yet' : '${open.length} open',
            onTap: () => _page('Open orders', const SellScreen()),
          ),
        ),
      if (can(Permission.takeOrders))
        _HomeTile(
          icon: Icons.table_restaurant_outlined,
          title: 'Tables',
          subtitle: 'Free and busy tables',
          onTap: () => _page('Tables', const TablesScreen()),
        ),
      if (can(Permission.kitchenTickets) && kitchenOn)
        _LiveTile<List<KitchenTicketView>>(
          key: const ValueKey('kitchen'),
          watch: () => ref.read(servicesProvider).orders.watchTickets(includeReady: false, limit: 200),
          builder: (context, tickets) {
            final waiting = tickets?.where((t) => t.ticket.status == KitchenStatus.pending).length ?? 0;
            return _HomeTile(
              icon: Icons.soup_kitchen_outlined,
              title: 'Kitchen',
              subtitle: waiting == 0 ? 'Orders being made' : '$waiting new',
              badge: waiting,
              onTap: () => _fullPage(
                Theme(
                  data: kitchenTheme(Theme.of(context)),
                  child: Scaffold(
                    appBar: AppBar(title: const Text('Kitchen')),
                    body: const KitchenScreen(),
                  ),
                ),
              ),
            );
          },
        ),
      if (can(Permission.viewBills))
        _HomeTile(
          icon: Icons.receipt_outlined,
          title: 'Bills',
          subtitle: 'Find, reprint or refund',
          onTap: () => _page('Bills', const BillsScreen()),
        ),
      if (can(Permission.ownShift))
        _HomeTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Shift & cash',
          subtitle: 'Open, close, cash in and out',
          onTap: () => _page('Shift & cash', const ShiftScreen()),
        ),
      if (can(Permission.recordExpense))
        _HomeTile(
          icon: Icons.payments_outlined,
          title: 'Expenses',
          subtitle: 'Money spent today',
          onTap: () => _page('Expenses', const ExpensesScreen()),
        ),
    ];
    final manage = <Widget>[
      if (can(Permission.viewReports))
        _HomeTile(
          icon: Icons.insights_outlined,
          title: 'Reports',
          subtitle: 'Sales, items, payments',
          onTap: () => _page('Reports', const DashboardScreen()),
        ),
      if (can(Permission.manageMenu))
        _HomeTile(
          icon: Icons.restaurant_menu_outlined,
          title: 'Menu',
          subtitle: 'Items, prices, sold out',
          onTap: () => _page('Menu', const MenuAdminScreen()),
        ),
      if (can(Permission.manageStaff))
        _HomeTile(
          icon: Icons.badge_outlined,
          title: 'Staff',
          subtitle: 'Accounts and roles',
          onTap: () => _page('Staff', const StaffScreen()),
        ),
      if (can(Permission.manageDevices) && platformCanHost)
        _HomeTile(
          icon: Icons.phonelink_ring_outlined,
          title: 'Phones & cloud',
          subtitle: 'Waiter phones, kitchen screens',
          onTap: () => _fullPage(const ConnectedDevicesScreen()),
        ),
      if (can(Permission.manageSettings))
        _HomeTile(
          icon: Icons.settings_outlined,
          title: 'Settings',
          subtitle: 'Kitchen, printers, taxes, backup',
          onTap: () => _page('Settings', const SettingsScreen()),
        ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(settings?.name ?? 'CaféDesk Online', style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('${actor.role.label} · ${actor.name}', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        actions: const [ConnectionChip(), ShiftChip(), PrintStatusButton(), UserMenuButton(), SizedBox(width: 4)],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              if (_today != null) _TodayCard(stream: _today),
              if (!kitchenOn && can(Permission.manageSettings))
                const _InfoBanner(
                  icon: Icons.no_food_outlined,
                  text: 'Kitchen is switched off: waiters prepare orders and mark them ready. Turn it on in Settings.',
                ),
              if (daily.isNotEmpty) ...[
                const _SectionTitle('Daily work'),
                _TileGrid(children: daily),
              ],
              if (manage.isNotEmpty) ...[
                const _SectionTitle('Manage'),
                _TileGrid(children: manage),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A tile that shows live numbers. It owns its stream, so tiles can come and
/// go (kitchen switched on or off) without re-listening to a used stream.
class _LiveTile<T> extends StatefulWidget {
  const _LiveTile({super.key, required this.watch, required this.builder});
  final Stream<T> Function() watch;
  final Widget Function(BuildContext context, T? value) builder;

  @override
  State<_LiveTile<T>> createState() => _LiveTileState<T>();
}

class _LiveTileState<T> extends State<_LiveTile<T>> {
  late final Stream<T> _stream = widget.watch();

  @override
  Widget build(BuildContext context) =>
      StreamBuilder<T>(stream: _stream, builder: (context, snap) => widget.builder(context, snap.data));
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.stream});
  final Stream<DashboardData> stream;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return StreamBuilder<DashboardData>(
      stream: stream,
      builder: (context, snap) {
        final d = snap.data;
        return Container(
          margin: const EdgeInsets.only(top: 8, bottom: 4),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.accent, Color(0xFF168C82)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Today's sales", style: t.bodyMedium?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 2),
                    Text(
                      d == null ? '…' : formatMoney(d.billsTotal),
                      style: t.headlineMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    d == null ? '' : '${d.billCount}',
                    style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  Text('bills', style: t.bodyMedium?.copyWith(color: Colors.white70)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: const Color(0xFFFFF4E0), borderRadius: BorderRadius.circular(12)),
    child: Row(
      children: [
        Icon(icon, color: AppColors.warning),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
  );
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GridView(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 260,
      mainAxisExtent: scaledExtent(context, 124),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    ),
    children: children,
  );
}

class _HomeTile extends StatelessWidget {
  const _HomeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
    this.badge = 0,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool primary;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final fg = primary ? Colors.white : AppColors.ink;
    return Material(
      color: primary ? AppColors.accent : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: primary ? BorderSide.none : const BorderSide(color: Color(0xFFE6DED3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: primary ? Colors.white24 : AppColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 26, color: primary ? Colors.white : AppColors.accent),
                  ),
                  const Spacer(),
                  if (badge > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(12)),
                      child: Text(
                        '$badge',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                title,
                style: t.titleMedium?.copyWith(color: fg, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                subtitle,
                style: t.bodySmall?.copyWith(color: primary ? Colors.white70 : AppColors.ink.withValues(alpha: 0.65)),
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
