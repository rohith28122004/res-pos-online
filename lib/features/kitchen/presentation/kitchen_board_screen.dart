import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../app/theme.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_app.dart';
import '../../devices/presentation/device_providers.dart';

/// Kitchen display on a phone or tablet: accepted tickets from the POS,
/// preparing / ready changes checked by the POS, one alarm per new ticket.
class KitchenBoardScreen extends ConsumerStatefulWidget {
  const KitchenBoardScreen({super.key});
  @override
  ConsumerState<KitchenBoardScreen> createState() => _KitchenBoardScreenState();
}

class _KitchenBoardScreenState extends ConsumerState<KitchenBoardScreen> {
  bool _muted = false;
  bool _awake = false;
  StreamSubscription<Map<String, Object?>>? _alarms;

  /// Created on the first alarm (no audio resources until needed).
  AudioPlayer? _player;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _alarms = ref.read(deviceSyncProvider).alarms.listen(_onAlarm);
    // Elapsed times refresh every 30 s.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_alarms?.cancel());
    _tick?.cancel();
    final player = _player;
    if (player != null) unawaited(player.dispose());
    if (_awake) unawaited(WakelockPlus.disable());
    super.dispose();
  }

  Future<void> _onAlarm(Map<String, Object?> ticket) async {
    if (_muted) return;
    unawaited(HapticFeedback.heavyImpact());
    try {
      final player = _player ??= AudioPlayer();
      await player.play(AssetSource('sounds/new_ticket.wav'));
    } on Object {
      // No audio output: the card still appears.
    }
  }

  Future<void> _toggleAwake() async {
    final next = !_awake;
    try {
      await (next ? WakelockPlus.enable() : WakelockPlus.disable());
      setState(() => _awake = next);
    } on Object {
      if (mounted) showInfo(context, 'This device cannot keep the screen on from the app.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheViewProvider).value ?? const CacheView();
    final commands = ref.watch(myCommandsProvider).value ?? const <PendingCommandRow>[];
    final tickets = cache.tickets.values.toList()
      ..sort((a, b) => (a['createdAt']! as int).compareTo(b['createdAt']! as int));
    final byStatus = {
      for (final s in ['pending', 'preparing', 'ready']) s: tickets.where((t) => t['status'] == s).toList(),
    };
    // Show the most recent ready tickets only.
    byStatus['ready'] = byStatus['ready']!.reversed.take(12).toList();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      appBar: AppBar(
        title: Text('Kitchen · ${cache.meta?['restaurantName'] ?? ''}'),
        actions: [
          IconButton(
            tooltip: _muted ? 'Sound off — tap to turn on' : 'Sound on — tap to mute',
            icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
            onPressed: () => setState(() => _muted = !_muted),
          ),
          IconButton(
            tooltip: _awake ? 'Screen stays on' : 'Keep the screen on',
            icon: Icon(_awake ? Icons.light_mode : Icons.light_mode_outlined),
            onPressed: _toggleAwake,
          ),
          const DeviceMenuButton(),
        ],
      ),
      body: Column(
        children: [
          const LinkBanner(),
          Expanded(
            child: tickets.isEmpty
                ? const EmptyState(
                    icon: Icons.soup_kitchen_outlined,
                    title: 'No tickets',
                    message: 'New orders accepted by the POS appear here.',
                  )
                : wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final s in ['pending', 'preparing', 'ready'])
                        Expanded(
                          child: _Column(status: s, tickets: byStatus[s]!, commands: commands),
                        ),
                    ],
                  )
                : DefaultTabController(
                    length: 3,
                    child: Column(
                      children: [
                        TabBar(
                          tabs: [
                            for (final s in ['pending', 'preparing', 'ready'])
                              Tab(text: '${_Column.title(s)} (${byStatus[s]!.length})'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              for (final s in ['pending', 'preparing', 'ready'])
                                _Column(status: s, tickets: byStatus[s]!, commands: commands, showTitle: false),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({required this.status, required this.tickets, required this.commands, this.showTitle = true});

  final String status;
  final List<Map<String, Object?>> tickets;
  final List<PendingCommandRow> commands;
  final bool showTitle;

  static String title(String s) => switch (s) {
    'pending' => 'New',
    'preparing' => 'Preparing',
    _ => 'Ready',
  };

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(8),
    children: [
      if (showTitle)
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text('${title(status)} (${tickets.length})', style: Theme.of(context).textTheme.titleMedium),
        ),
      for (final t in tickets)
        _TicketCard(
          ticket: t,
          pending: commands
              .where((c) => c.aggregateId == t['ticketId'] && CommandState.open.contains(c.state))
              .firstOrNull,
        ),
    ],
  );
}

class _TicketCard extends ConsumerWidget {
  const _TicketCard({required this.ticket, required this.pending});
  final Map<String, Object?> ticket;

  /// A status change from this display that the POS has not confirmed yet.
  final PendingCommandRow? pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ticket;
    final status = t['status']! as String;
    final correction = t['kind'] == 'correction';
    final minutes = ((DateTime.now().millisecondsSinceEpoch - (t['createdAt']! as int)) / 60000).floor();
    final sending = pending != null;
    final lines = [for (final l in t['lines']! as List) (l! as Map).cast<String, Object?>()];
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(t['createdAt']! as int)).format(context);
    final late = status != 'ready' && minutes >= 15;

    Future<void> move(String to) => guard(
      context,
      () => ref
          .read(deviceSyncProvider)
          .enqueue(
            action: CommandAction.ticketSetStatus,
            aggregateId: t['ticketId']! as String,
            expectedRevision: t['revision']! as int,
            payload: {'status': to},
            summary: 'KOT #${t['ticketNo']} → $to',
          ),
    );

    return Card(
      color: correction ? AppColors.danger.withValues(alpha: 0.08) : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${t['orderRef']}  ·  KOT #${t['ticketNo']}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusChip(
                  label: status == 'ready' ? time : '$minutes min',
                  color: late ? AppColors.danger : AppColors.info,
                  icon: Icons.timer_outlined,
                ),
              ],
            ),
            Text(
              '${t['createdByName']} · $time${correction ? ' · CORRECTION' : ''}',
              style: TextStyle(color: correction ? AppColors.danger : AppColors.ink.withValues(alpha: 0.7)),
            ),
            if (t['reason'] != null) Text('Reason: ${t['reason']}', style: const TextStyle(color: AppColors.danger)),
            const Divider(),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${(l['quantityDelta']! as int) > 0 ? '' : 'CANCEL '}${(l['quantityDelta']! as int).abs()} × '
                      '${l['itemName']}${l['variantName'] == null ? '' : ' (${l['variantName']})'}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: (l['quantityDelta']! as int) < 0 ? AppColors.danger : null,
                      ),
                    ),
                    if (l['modifiersText'] != null) Text('+ ${l['modifiersText']}'),
                    if (l['note'] != null)
                      Text('Note: ${l['note']}', style: const TextStyle(fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            if (sending)
              const Row(
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Expanded(child: Text('Waiting for the POS to confirm…')),
                ],
              )
            else if (status == 'pending')
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => move('preparing'), child: const Text('Start')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(onPressed: () => move('ready'), child: const Text('Ready')),
                  ),
                ],
              )
            else if (status == 'preparing')
              SizedBox(
                width: double.infinity,
                child: FilledButton(onPressed: () => move('ready'), child: const Text('Ready')),
              ),
          ],
        ),
      ),
    );
  }
}
