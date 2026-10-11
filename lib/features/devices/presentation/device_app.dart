import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/app_info.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';
import '../../../shared/widgets/common.dart';
import '../../kitchen/presentation/kitchen_board_screen.dart';
import '../../waiter/presentation/waiter_home.dart';
import 'device_providers.dart';
import 'pair_scanner.dart';

/// Root of a waiter phone / kitchen display: pair → sign in → work.
class DeviceApp extends ConsumerWidget {
  const DeviceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final link = ref.watch(deviceLinkProvider);
    final session = ref.watch(deviceSessionProvider);
    if (link.isLoading || session.isLoading) return const Scaffold(body: LoadingView(label: 'Opening…'));
    final l = link.value;
    if (l == null) return const PairDeviceScreen();
    final s = session.value;
    if (s == null) return DeviceSignInScreen(link: l);
    return l.role == 'kitchen' ? const KitchenBoardScreen() : const WaiterHomeScreen();
  }
}

/// Connection banner shown on every device screen. Cached data is marked stale
/// when the POS is not reachable.
class LinkBanner extends ConsumerWidget {
  const LinkBanner({super.key});

  static String ago(int ms, int now) {
    final s = ((now - ms) / 1000).round();
    if (s < 60) return 'just now';
    if (s < 3600) return '${s ~/ 60} min ago';
    return '${s ~/ 3600} h ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(linkStatusProvider).value ?? const LinkStatus();
    final now = DateTime.now().millisecondsSinceEpoch;
    final (color, icon, text) = switch (status) {
      LinkStatus(problem: 'deviceRevoked') => (
        AppColors.danger,
        Icons.block,
        'This phone was removed from the POS. Unpair it and pair again.',
      ),
      LinkStatus(problem: 'wrongCertificate') => (
        AppColors.danger,
        Icons.gpp_bad_outlined,
        'Something on this network pretends to be the POS. Nothing was sent. Tell the owner.',
      ),
      LinkStatus(problem: 'updateRequired') => (
        AppColors.danger,
        Icons.system_update_outlined,
        'Update CaféDesk Online on this phone or on the POS.',
      ),
      LinkStatus(problem: 'hostRestored') => (
        AppColors.warning,
        Icons.restore,
        'The POS was restored from a backup. Check unsent orders before sending them again.',
      ),
      LinkStatus(live: true, route: 'lan') => (AppColors.success, Icons.wifi, 'Connected to the POS (café Wi-Fi)'),
      LinkStatus(live: true, route: 'cloud', hostConnectedToCloud: false) => (
        AppColors.warning,
        Icons.cloud_off_outlined,
        'Connected to the cloud, but the POS is offline. Orders wait until it is back.',
      ),
      LinkStatus(live: true, route: 'cloud') => (
        AppColors.info,
        Icons.cloud_done_outlined,
        'Connected to the POS through the cloud',
      ),
      LinkStatus(:final lastLiveAt) => (
        AppColors.warning,
        Icons.portable_wifi_off,
        lastLiveAt == null
            ? 'Not connected to the POS. Orders are saved on this phone.'
            : 'Not connected to the POS. Showing data from ${ago(lastLiveAt, now)}; orders are saved on this phone.',
      ),
    };
    return Material(
      color: color.withValues(alpha: 0.12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: AppColors.ink, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Signed-in user menu shared by waiter and kitchen screens.
class DeviceMenuButton extends ConsumerWidget {
  const DeviceMenuButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(deviceSessionProvider).value;
    final sync = ref.watch(deviceSyncProvider);
    return PopupMenuButton<String>(
      tooltip: session?.name ?? 'Menu',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: (v) async {
        switch (v) {
          case 'refresh':
            await guard(context, sync.refresh, success: 'Updated from the POS');
          case 'signout':
            await sync.signOut();
          case 'unpair':
            final ok = await confirm(
              context,
              title: 'Unpair this phone?',
              message:
                  'Unsent orders on this phone are deleted. The owner can pair it again from the POS '
                  '(Settings → Connected devices).',
              confirmLabel: 'Unpair',
              destructive: true,
            );
            if (ok) await ref.read(appControllerProvider.notifier).leaveDeviceMode();
        }
      },
      itemBuilder: (_) => [
        if (session != null) PopupMenuItem(enabled: false, child: Text('${session.name} · ${session.role}')),
        const PopupMenuItem(value: 'refresh', child: Text('Refresh from the POS')),
        const PopupMenuItem(value: 'signout', child: Text('Sign out')),
        const PopupMenuItem(value: 'unpair', child: Text('Unpair this phone')),
      ],
    );
  }
}

class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key});
  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController(text: Platform.isAndroid ? 'Android phone' : 'Device');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _pair([String? scanned]) async {
    final text = scanned ?? _code.text;
    if (text.trim().isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(deviceSyncProvider)
          .pair(text, deviceName: _name.text.trim(), platform: Platform.operatingSystem, appVersion: AppInfo.version);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect to the POS'),
        actions: [
          TextButton(
            onPressed: () => ref.read(appControllerProvider.notifier).leaveDeviceMode(),
            child: const Text('Use as a POS instead'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'On the POS, the owner opens Settings → Connected devices → Pair a phone and chooses waiter or '
                  'kitchen. Then scan the code it shows (or copy its text here). This phone must be on the café Wi-Fi.',
                  style: t.bodyLarge,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _name,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'Name for this device',
                    helperText: 'e.g. Ravi\'s phone, Kitchen tablet',
                  ),
                ),
                const SizedBox(height: 8),
                if (canScanQr)
                  FilledButton.icon(
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan the pairing code'),
                    onPressed: _busy
                        ? null
                        : () async {
                            final scanned = await Navigator.of(
                              context,
                            ).push<String>(MaterialPageRoute(builder: (_) => const PairScannerScreen()));
                            if (scanned != null) await _pair(scanned);
                          },
                  ),
                const SizedBox(height: 16),
                TextField(
                  controller: _code,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(labelText: 'Or paste the pairing text (starts with cdpair1.)'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: _busy ? null : _pair, child: const Text('Pair with this text')),
                const SizedBox(height: 12),
                if (_busy) const Center(child: CircularProgressIndicator()),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: AppColors.danger),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DeviceSignInScreen extends ConsumerStatefulWidget {
  const DeviceSignInScreen({super.key, required this.link});
  final ClientLinkRow link;
  @override
  ConsumerState<DeviceSignInScreen> createState() => _DeviceSignInScreenState();
}

class _DeviceSignInScreenState extends ConsumerState<DeviceSignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy || _email.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(deviceSyncProvider).signIn(_email.text, _password.text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final kitchen = widget.link.role == 'kitchen';
    return Scaffold(
      appBar: AppBar(title: Text(widget.link.restaurantName), actions: const [DeviceMenuButton()]),
      body: Column(
        children: [
          const LinkBanner(),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Icon(kitchen ? Icons.soup_kitchen_outlined : Icons.room_service_outlined, size: 40),
                        const SizedBox(height: 8),
                        Text(
                          kitchen ? 'Kitchen display — sign in' : 'Waiter phone — sign in',
                          style: t.titleLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Use the same email and password as on the POS. Your password is checked by the POS only.',
                          textAlign: TextAlign.center,
                          style: t.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        EmailField(controller: _email),
                        const SizedBox(height: 12),
                        PasswordField(controller: _password, onSubmitted: (_) => _signIn()),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: _busy
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Sign in'),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: AppColors.danger),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
