import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_app.dart';
import '../../devices/presentation/device_providers.dart';
import 'kitchen_ui.dart';

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
    return Theme(
      data: kitchenTheme(Theme.of(context)),
      child: Scaffold(
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
              child: !cache.kitchenEnabled
                  ? const EmptyState(
                      icon: Icons.no_food_outlined,
                      title: 'The kitchen is switched off',
                      message:
                          'Waiters prepare orders on their phones. The admin can switch the kitchen on in Settings.',
                    )
                  : KitchenBoard(
                      tickets: [for (final t in cache.tickets.values) kitchenCardFromJson(t)],
                      emptyMessage: 'New orders accepted by the POS appear here.',
                      actions: ticketCommandActions(context, ref, cache, commands),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A ticket from the phone's copy of the POS (TicketView JSON).
KitchenCardData kitchenCardFromJson(Map<String, Object?> t) => KitchenCardData(
  id: t['ticketId']! as String,
  status: t['status']! as String,
  orderRef: t['orderRef']! as String,
  ticketNo: t['ticketNo']! as int,
  createdAt: t['createdAt']! as int,
  byName: t['createdByName'] as String?,
  correction: t['kind'] == 'correction',
  reason: t['reason'] as String?,
  lines: [
    for (final l in ((t['lines'] as List?) ?? const []).cast<Map<String, Object?>>())
      KitchenLineData(
        quantity: l['quantityDelta']! as int,
        name: l['itemName']! as String,
        variant: l['variantName'] as String?,
        modifiers: l['modifiersText'] as String?,
        note: l['note'] as String?,
      ),
  ],
);

/// On a phone, moving a ticket is a command the POS must accept (with the
/// ticket's revision). While it waits, the card says so instead of showing
/// buttons; a phone cannot move a ticket back.
KitchenActions ticketCommandActions(
  BuildContext context,
  WidgetRef ref,
  CacheView cache,
  List<PendingCommandRow> commands,
) => KitchenActions(
  onMove: (t, to) => guard(
    context,
    () => ref
        .read(deviceSyncProvider)
        .enqueue(
          action: CommandAction.ticketSetStatus,
          aggregateId: t.id,
          expectedRevision: cache.tickets[t.id]!['revision']! as int,
          payload: {'status': to},
          summary: 'KOT #${t.ticketNo} → ${KitchenStatus.title(to).toLowerCase()}',
        ),
  ),
  busy: (t) => commands.any((c) => c.aggregateId == t.id && CommandState.open.contains(c.state))
      ? 'Waiting for the POS to confirm…'
      : null,
);
