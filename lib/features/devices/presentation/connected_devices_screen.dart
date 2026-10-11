import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/host/cloud_connector.dart';
import '../../../core/host/command_dispatcher.dart';
import '../../../core/host/host_connectivity.dart';
import '../../../core/host/host_identity.dart';
import '../../../shared/widgets/common.dart';
import '../application/device_service.dart';

final _identityProvider = StreamProvider<HostIdentityRow?>((ref) {
  final db = ref.watch(servicesProvider).ctx.db;
  return db.select(db.hostIdentity).watchSingleOrNull();
});

final _devicesProvider = StreamProvider<List<PairedDeviceRow>>(
  (ref) => DeviceService(ref.watch(servicesProvider).ctx).watchDevices(),
);

/// Owner screen on the POS host: let phones connect, pair them, see and
/// revoke them, and connect the cloud relay.
class ConnectedDevicesScreen extends ConsumerStatefulWidget {
  const ConnectedDevicesScreen({super.key});
  @override
  ConsumerState<ConnectedDevicesScreen> createState() => _ConnectedDevicesScreenState();
}

class _ConnectedDevicesScreenState extends ConsumerState<ConnectedDevicesScreen> {
  StreamSubscription<void>? _hostChanges;
  StreamSubscription<CloudStatus>? _cloudChanges;
  List<String> _addresses = const [];

  @override
  void initState() {
    super.initState();
    final host = ref.read(runtimeProvider).host;
    _hostChanges = host.changes.listen((_) => _watchCloud());
    _watchCloud();
    unawaited(
      DeviceService.lanAddresses().then((a) {
        if (mounted) setState(() => _addresses = a);
      }),
    );
  }

  void _watchCloud() {
    unawaited(_cloudChanges?.cancel());
    _cloudChanges = ref.read(runtimeProvider).host.cloud?.status.listen((_) {
      if (mounted) setState(() {});
    });
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(_hostChanges?.cancel());
    unawaited(_cloudChanges?.cancel());
    super.dispose();
  }

  HostIdentityService _identityService() {
    final rt = ref.read(runtimeProvider);
    return HostIdentityService(rt.services.ctx, rt.secrets);
  }

  Future<void> _setLan(bool on) async {
    final rt = ref.read(runtimeProvider);
    final actor = requireActor(ref);
    await guard(context, () async {
      final service = _identityService();
      await service.ensure(actor);
      await service.setLan(actor, enabled: on);
      await rt.host.restart();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rt = ref.watch(runtimeProvider);
    final host = rt.host;
    final identity = ref.watch(_identityProvider).value;
    final devices = ref.watch(_devicesProvider).value ?? const [];
    final t = Theme.of(context).textTheme;
    final active = devices.where((d) => d.revokedAt == null).toList();
    final revoked = devices.where((d) => d.revokedAt != null).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Connected devices')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!platformCanHost)
            const SectionCard(
              title: 'Waiter phones and kitchen displays',
              child: Text(
                'Phones connect to a Windows PC running CaféDesk Online as the main till. This device keeps working '
                'as a standalone till. To use phones, set up CaféDesk Online on the café\'s Windows PC.',
              ),
            )
          else ...[
            SectionCard(
              title: 'Phones on the café Wi-Fi',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: identity?.lanEnabled ?? false,
                    title: const Text('Let paired phones connect to this POS'),
                    subtitle: Text(
                      host.lanRunning
                          ? 'On · ${_addresses.isEmpty ? 'no network found' : _addresses.join(', ')} · port ${identity?.lanPort}'
                          : 'Off',
                    ),
                    onChanged: _setLan,
                  ),
                  if (host.lanError != null) Text(host.lanError!, style: const TextStyle(color: AppColors.danger)),
                  if (host.lanRunning)
                    Text(
                      '${host.lan?.connectedSockets ?? 0} device(s) live right now. Keep CaféDesk Online open (it can '
                      'be minimised): closing it disconnects every phone. The first time, Windows may ask to allow '
                      'CaféDesk Online on private networks — choose Allow.',
                      style: t.bodySmall,
                    ),
                  if (identity != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Security fingerprint: ${identity.tlsCertSha256.substring(0, 16)}…',
                        style: t.bodySmall?.copyWith(fontFamily: 'monospace'),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Paired devices (${active.length})',
              trailing: FilledButton.icon(
                icon: const Icon(Icons.qr_code_2),
                label: const Text('Pair a phone'),
                onPressed: host.lanRunning ? () => _pair(context) : null,
              ),
              child: Column(
                children: [
                  if (!host.lanRunning)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Text('Turn on phone connections above to pair a phone.'),
                    ),
                  if (active.isEmpty) const Text('No phones paired yet.'),
                  for (final d in active)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        d.role == DeviceRole.kitchen ? Icons.soup_kitchen_outlined : Icons.room_service_outlined,
                      ),
                      title: Text(d.name),
                      subtitle: Text(
                        '${d.role == DeviceRole.kitchen ? 'Kitchen display' : 'Waiter phone'} · paired by ${d.pairedByName}'
                        '${d.lastSeenAt == null ? '' : ' · last seen ${formatLocalMs(d.lastSeenAt!)}'}',
                      ),
                      trailing: TextButton(
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Remove ${d.name}?',
                            message:
                                'It is disconnected at once on this POS. If it is connected through the cloud, the cloud '
                                'stops it as soon as this POS can tell it.',
                            confirmLabel: 'Remove',
                            destructive: true,
                          );
                          if (ok && context.mounted) {
                            await guard(
                              context,
                              () => DeviceService(rt.services.ctx).revoke(requireActor(ref), d.id),
                              success: '${d.name} removed',
                            );
                          }
                        },
                        child: const Text('Remove'),
                      ),
                    ),
                  if (revoked.isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text('Removed (${revoked.length})'),
                      children: [
                        for (final d in revoked)
                          ListTile(
                            dense: true,
                            title: Text(d.name),
                            subtitle: Text('Removed ${formatLocalMs(d.revokedAt!)}'),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CloudCard(identity: identity),
            const SizedBox(height: 12),
            if (identity != null)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                icon: const Icon(Icons.restart_alt),
                label: const Text('Reset device connections'),
                onPressed: () async {
                  final ok = await confirm(
                    context,
                    title: 'Reset device connections?',
                    message:
                        'New security keys are made. Every phone must be paired again and the cloud connection set '
                        'up again. Sales and orders are not affected.',
                    confirmLabel: 'Reset',
                    destructive: true,
                  );
                  if (!ok || !context.mounted) return;
                  await guard(context, () async {
                    await _identityService().resetConnections(requireActor(ref));
                    await rt.host.restart();
                  }, success: 'Device connections reset');
                },
              ),
          ],
        ],
      ),
    );
  }

  Future<void> _pair(BuildContext context) async {
    final rt = ref.read(runtimeProvider);
    var role = DeviceRole.waiter;
    final name = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Pair a phone'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: DeviceRole.waiter,
                    label: Text('Waiter phone'),
                    icon: Icon(Icons.room_service_outlined),
                  ),
                  ButtonSegment(
                    value: DeviceRole.kitchen,
                    label: Text('Kitchen display'),
                    icon: Icon(Icons.soup_kitchen_outlined),
                  ),
                ],
                selected: {role},
                onSelectionChanged: (s) => setLocal(() => role = s.single),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: name,
                maxLength: 40,
                decoration: const InputDecoration(labelText: 'Device name', hintText: 'e.g. Ravi\'s phone'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Show code')),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) {
      name.dispose();
      return;
    }
    final identity = await _identityService().current();
    if (identity == null || !context.mounted) return;
    final invite = await guard(
      context,
      () => DeviceService(rt.services.ctx).createInvite(
        requireActor(ref),
        role: role,
        deviceName: name.text.trim().isEmpty
            ? (role == DeviceRole.kitchen ? 'Kitchen display' : 'Waiter phone')
            : name.text,
        identity: identity,
        addresses: _addresses,
      ),
    );
    name.dispose();
    if (invite == null || !context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _PairingCodeDialog(invite: invite),
    );
  }
}

class _PairingCodeDialog extends StatefulWidget {
  const _PairingCodeDialog({required this.invite});
  final PairingInvite invite;
  @override
  State<_PairingCodeDialog> createState() => _PairingCodeDialogState();
}

class _PairingCodeDialogState extends State<_PairingCodeDialog> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = Duration(milliseconds: widget.invite.expiresAt - DateTime.now().millisecondsSinceEpoch);
    final expired = left.isNegative;
    return AlertDialog(
      title: Text(widget.invite.role == DeviceRole.kitchen ? 'Pair the kitchen display' : 'Pair the waiter phone'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('On the phone: open CaféDesk Online → "Use as a waiter phone or kitchen display" → Scan.'),
            const SizedBox(height: 12),
            if (expired)
              const Text('This code has expired. Close and make a new one.', style: TextStyle(color: AppColors.danger))
            else
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(8),
                child: QrImageView(data: widget.invite.payload, size: 260),
              ),
            const SizedBox(height: 8),
            if (!expired)
              Text('Works once, for ${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')} more.'),
            TextButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy as text instead'),
              onPressed: expired
                  ? null
                  : () async {
                      await Clipboard.setData(ClipboardData(text: widget.invite.payload));
                      if (context.mounted) showInfo(context, 'Copied. Paste it on the phone.');
                    },
            ),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
    );
  }
}

class _CloudCard extends ConsumerStatefulWidget {
  const _CloudCard({required this.identity});
  final HostIdentityRow? identity;
  @override
  ConsumerState<_CloudCard> createState() => _CloudCardState();
}

class _CloudCardState extends ConsumerState<_CloudCard> {
  final _url = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rt = ref.watch(runtimeProvider);
    final identity = widget.identity;
    final cloud = rt.host.cloud;
    final status = cloud?.currentStatus;
    final t = Theme.of(context).textTheme;
    if (identity == null) {
      return const SectionCard(
        title: 'Cloud relay (optional)',
        child: Text('Turn on phone connections first.'),
      );
    }
    if (identity.cloudUrl == null) {
      return SectionCard(
        title: 'Cloud relay (optional)',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Lets phones reach this POS when they are not on the café Wi-Fi, and keeps an off-site copy of sales '
              'for reports. The POS still decides everything and keeps billing without internet.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Cloud address (https://…)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Enrollment code'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () => guard(context, () async {
                final api = rt.host.api;
                if (api == null) throw StateError('Turn on phone connections first');
                final connector = CloudConnector(api: api, secrets: rt.secrets);
                try {
                  await connector.enroll(requireActor(ref), cloudUrl: _url.text, enrollmentCode: _code.text);
                } finally {
                  await connector.dispose();
                }
                await rt.host.restart();
              }, success: 'Connected to the cloud'),
              child: const Text('Connect'),
            ),
          ],
        ),
      );
    }
    return SectionCard(
      title: 'Cloud relay',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(Uri.parse(identity.cloudUrl!).host, style: t.titleSmall),
          const SizedBox(height: 4),
          Text(status == null ? 'Starting…' : (status.socketConnected ? 'Connected' : 'Not connected — retrying')),
          if (status?.lastUploadAt != null)
            Text(
              'Sales copied to the cloud up to #${status!.ackedThrough} · last at ${formatLocalMs(status.lastUploadAt!)}',
            ),
          if ((status?.pendingEvents ?? 0) > 0) Text('${status!.pendingEvents} change(s) waiting to be copied'),
          if (status?.lastError != null) Text(status!.lastError!, style: const TextStyle(color: AppColors.danger)),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: cloud == null ? null : () => guard(context, cloud.uploadNow, success: 'Copied'),
            child: const Text('Copy now'),
          ),
        ],
      ),
    );
  }
}
