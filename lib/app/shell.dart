import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/host/host_connectivity.dart';
import '../core/security/permissions.dart';
import '../features/auth/presentation/staff_screen.dart';
import '../features/devices/presentation/connected_devices_screen.dart';
import '../features/home/presentation/admin_home.dart';
import '../features/orders/presentation/kitchen_screen.dart';
import '../features/settings/presentation/print_queue_screen.dart';
import '../features/waiter/presentation/waiter_till_home.dart';
import '../shared/widgets/common.dart';
import '../shared/widgets/people.dart';
import 'providers.dart';
import 'theme.dart';

/// After sign-in each role gets its own screen: the admin and cashiers a home
/// page with big buttons, waiters only their tables and orders, kitchen staff
/// only the kitchen board.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(sessionProvider)!;
    return switch (actor.role) {
      StaffRole.waiter => const WaiterTillHome(menu: UserMenuButton()),
      StaffRole.kitchen => const KitchenHomePage(menu: UserMenuButton()),
      StaffRole.owner || StaffRole.cashier => const AdminHome(),
    };
  }
}

/// Whether waiter phones and kitchen displays can reach this till, and how
/// many are connected right now. The admin taps it to manage devices.
class ConnectionChip extends ConsumerWidget {
  const ConnectionChip({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (screenSizeOf(context) == ScreenSize.phone) return const SizedBox.shrink();
    final s = ref.watch(hostStatusProvider).value ?? const HostStatus();
    final (label, color, icon, tip) = switch (s) {
      HostStatus(:final problem?) => ('Phones: problem', AppColors.danger, Icons.wifi_off, problem),
      HostStatus(lanRunning: true, cloudEnrolled: true, cloudConnected: false) => (
        'Phones: ${s.liveDevices} live',
        AppColors.warning,
        Icons.cloud_off_outlined,
        'Phones on the café Wi-Fi can connect. The cloud relay is not connected, so phones off the Wi-Fi '
            'cannot reach this till.',
      ),
      HostStatus(lanRunning: true) => (
        'Phones: ${s.liveDevices} live',
        s.liveDevices > 0 ? AppColors.success : AppColors.info,
        Icons.phonelink_ring_outlined,
        '${s.liveDevices} phone(s) or kitchen display(s) connected now. Keep this app open: closing it '
            'disconnects them.',
      ),
      HostStatus(cloudEnrolled: true) => (
        s.cloudConnected ? 'Cloud only' : 'Cloud offline',
        s.cloudConnected ? AppColors.info : AppColors.warning,
        s.cloudConnected ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
        'Phone connections over the café Wi-Fi are off.',
      ),
      _ => (
        'This till only',
        AppColors.info,
        Icons.phonelink_lock_outlined,
        platformCanHost
            ? 'Sales are saved on this PC. Waiter phones are not connected; the admin can turn them on in '
                  'Phones & cloud.'
            : 'Sales are saved on this device.',
      ),
    };
    final canManage = platformCanHost && (ref.watch(sessionProvider)?.can(Permission.manageDevices) ?? false);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: canManage
              ? () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const ConnectedDevicesScreen()))
              : null,
          child: StatusChip(label: label, color: color, icon: icon),
        ),
      ),
    );
  }
}

class ShiftChip extends ConsumerWidget {
  const ShiftChip({super.key});
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

class PrintStatusButton extends ConsumerWidget {
  const PrintStatusButton({super.key});
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

/// The signed-in person: name and role, change password, sign out.
class UserMenuButton extends ConsumerWidget {
  const UserMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(sessionProvider);
    if (actor == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: '${actor.name} · ${actor.role.label}',
      icon: PersonAvatar(name: actor.name, role: actor.role, radius: 16),
      onSelected: (v) async {
        switch (v) {
          case 'lock':
            ref.read(sessionProvider.notifier).logout();
          case 'password':
            await showChangePasswordDialog(context, ref);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(actor.name),
            subtitle: Text(actor.role.label),
          ),
        ),
        const PopupMenuItem(
          value: 'password',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.key_outlined),
            title: Text('Change my password'),
          ),
        ),
        const PopupMenuItem(
          value: 'lock',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout),
            title: Text('Sign out'),
          ),
        ),
      ],
    );
  }
}
