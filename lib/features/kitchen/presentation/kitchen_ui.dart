import 'dart:async';

import 'package:flutter/material.dart';

/// Colours for kitchen screens. The dark set is for the kitchen (readable from
/// across the room); the light set is for waiters preparing orders themselves
/// when the café has no kitchen.
class KitchenPalette {
  const KitchenPalette({
    required this.background,
    required this.card,
    required this.text,
    required this.muted,
    required this.divider,
  });

  final Color background;
  final Color card;
  final Color text;
  final Color muted;
  final Color divider;

  static const dark = KitchenPalette(
    background: Color(0xFF12161A),
    card: Color(0xFF1E252B),
    text: Color(0xFFF4F6F7),
    muted: Color(0xFFA8B3BC),
    divider: Color(0xFF34404A),
  );

  static const light = KitchenPalette(
    background: Color(0xFFFBF8F3),
    card: Colors.white,
    text: Color(0xFF2B2622),
    muted: Color(0xFF6E655C),
    divider: Color(0xFFE6DED3),
  );

  static const newColor = Color(0xFFF5A524);
  static const cookingColor = Color(0xFF3B9BFF);
  static const readyColor = Color(0xFF2FBF71);
  static const lateColor = Color(0xFFFF5A52);

  static Color forStatus(String status) => switch (status) {
    KitchenStatus.pending => newColor,
    KitchenStatus.preparing => cookingColor,
    _ => readyColor,
  };
}

/// Ticket statuses as the kitchen screens name them.
abstract final class KitchenStatus {
  static const pending = 'pending';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const all = [pending, preparing, ready];

  static String title(String s) => switch (s) {
    pending => 'New',
    preparing => 'Cooking',
    _ => 'Ready',
  };
}

/// Dark theme for kitchen displays.
ThemeData kitchenTheme(ThemeData base) {
  const p = KitchenPalette.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: KitchenPalette.readyColor,
    brightness: Brightness.dark,
    primary: KitchenPalette.readyColor,
    surface: p.background,
  ).copyWith(onSurface: p.text, onPrimary: Colors.black);
  return base.copyWith(
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: p.background,
    canvasColor: p.background,
    appBarTheme: AppBarTheme(backgroundColor: p.background, foregroundColor: p.text, elevation: 0),
    cardTheme: base.cardTheme.copyWith(color: p.card),
    dividerTheme: DividerThemeData(color: p.divider),
    textTheme: base.textTheme.apply(bodyColor: p.text, displayColor: p.text),
    iconTheme: IconThemeData(color: p.text),
    tabBarTheme: TabBarThemeData(
      labelColor: p.text,
      unselectedLabelColor: p.muted,
      indicatorColor: KitchenPalette.readyColor,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.card,
      textStyle: TextStyle(color: p.text),
    ),
  );
}

/// One ticket, whatever the data source (the POS database or a phone's copy).
class KitchenCardData {
  const KitchenCardData({
    required this.id,
    required this.status,
    required this.orderRef,
    required this.ticketNo,
    required this.createdAt,
    required this.lines,
    this.byName,
    this.correction = false,
    this.reason,
  });

  final String id;
  final String status;
  final String orderRef;
  final int ticketNo;
  final int createdAt;
  final String? byName;
  final bool correction;
  final String? reason;
  final List<KitchenLineData> lines;
}

class KitchenLineData {
  const KitchenLineData({required this.quantity, required this.name, this.variant, this.modifiers, this.note});
  final int quantity;
  final String name;
  final String? variant;
  final String? modifiers;
  final String? note;
}

/// What a card can do. A null callback hides that button.
class KitchenActions {
  const KitchenActions({this.onMove, this.onUndo, this.onReprint, this.busy});

  /// Move the ticket forward (to [KitchenStatus.preparing] or ready).
  final Future<void> Function(KitchenCardData ticket, String to)? onMove;

  /// Move it one step back (only where the screen allows it).
  final Future<void> Function(KitchenCardData ticket)? onUndo;
  final Future<void> Function(KitchenCardData ticket)? onReprint;

  /// A text shown instead of the buttons while a change is not confirmed yet.
  final String? Function(KitchenCardData ticket)? busy;
}

/// Ticket card: big order name, how long it has waited, the items and one or
/// two large buttons.
class KitchenTicketCard extends StatelessWidget {
  const KitchenTicketCard({
    super.key,
    required this.data,
    required this.actions,
    this.palette = KitchenPalette.dark,
    this.readyLabel = 'Ready',
  });

  final KitchenCardData data;
  final KitchenActions actions;
  final KitchenPalette palette;

  /// "Ready" in the kitchen; a waiter preparing orders may see "Done".
  final String readyLabel;

  @override
  Widget build(BuildContext context) {
    final t = data;
    final status = t.status;
    final color = t.correction ? KitchenPalette.lateColor : KitchenPalette.forStatus(status);
    final minutes = ((DateTime.now().millisecondsSinceEpoch - t.createdAt) / 60000).floor();
    final time = TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(t.createdAt)).format(context);
    final waitColor = status == KitchenStatus.ready
        ? palette.muted
        : minutes >= 20
        ? KitchenPalette.lateColor
        : minutes >= 10
        ? KitchenPalette.newColor
        : palette.muted;
    final busy = actions.busy?.call(t);
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border(top: BorderSide(color: color, width: 5)),
        boxShadow: palette == KitchenPalette.light
            ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    t.orderRef,
                    style: text.titleLarge?.copyWith(color: palette.text, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.schedule, size: 18, color: waitColor),
                    const SizedBox(width: 4),
                    Text(
                      status == KitchenStatus.ready ? time : '$minutes min',
                      style: TextStyle(color: waitColor, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: Text(
                    ['KOT #${t.ticketNo}', ?t.byName, time].join(' · '),
                    style: TextStyle(color: palette.muted, fontSize: 13),
                  ),
                ),
                if (actions.onReprint != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => unawaited(actions.onReprint!(t)),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.print_outlined, size: 20, color: palette.muted, semanticLabel: 'Reprint'),
                    ),
                  ),
              ],
            ),
            if (t.correction)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: KitchenPalette.lateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'CHANGE TO AN ORDER${t.reason == null ? '' : ' — ${t.reason}'}',
                  style: const TextStyle(color: KitchenPalette.lateColor, fontWeight: FontWeight.w800),
                ),
              ),
            Divider(height: 20, color: palette.divider),
            for (final l in t.lines) _Line(line: l, palette: palette),
            const SizedBox(height: 10),
            if (busy != null)
              Row(
                children: [
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(busy, style: TextStyle(color: palette.muted)),
                  ),
                ],
              )
            else
              _Buttons(data: t, actions: actions, palette: palette, readyLabel: readyLabel),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.line, required this.palette});
  final KitchenLineData line;
  final KitchenPalette palette;

  @override
  Widget build(BuildContext context) {
    final cancel = line.quantity < 0;
    final color = cancel ? KitchenPalette.lateColor : palette.text;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: cancel ? 'CANCEL ${-line.quantity} × ' : '${line.quantity} × ',
                  style: TextStyle(fontWeight: FontWeight.w900, color: color),
                ),
                TextSpan(
                  text: line.variant == null ? line.name : '${line.name} (${line.variant})',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                    decoration: cancel ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 19),
          ),
          if (line.modifiers != null) Text('+ ${line.modifiers}', style: TextStyle(color: palette.muted, fontSize: 15)),
          if (line.note != null)
            Text(
              '» ${line.note}',
              style: const TextStyle(color: KitchenPalette.newColor, fontSize: 15, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.data, required this.actions, required this.palette, required this.readyLabel});
  final KitchenCardData data;
  final KitchenActions actions;
  final KitchenPalette palette;
  final String readyLabel;

  @override
  Widget build(BuildContext context) {
    final move = actions.onMove;
    final ready = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: KitchenPalette.readyColor,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(52),
      ),
      icon: const Icon(Icons.check),
      label: Text(readyLabel),
      onPressed: move == null ? null : () => unawaited(move(data, KitchenStatus.ready)),
    );
    switch (data.status) {
      case KitchenStatus.pending:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: KitchenPalette.cookingColor,
                  side: const BorderSide(color: KitchenPalette.cookingColor, width: 1.5),
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: const Icon(Icons.local_fire_department_outlined),
                label: const Text('Start'),
                onPressed: move == null ? null : () => unawaited(move(data, KitchenStatus.preparing)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: ready),
          ],
        );
      case KitchenStatus.preparing:
        return Row(
          children: [
            if (actions.onUndo != null) ...[
              TextButton(
                style: TextButton.styleFrom(foregroundColor: palette.muted),
                onPressed: () => unawaited(actions.onUndo!(data)),
                child: const Text('Back'),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: ready),
          ],
        );
      default:
        if (actions.onUndo == null) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: palette.muted),
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Not ready yet'),
            onPressed: () => unawaited(actions.onUndo!(data)),
          ),
        );
    }
  }
}

/// New / Cooking / Ready: three columns on tablets and PCs, tabs on phones.
/// Elapsed times refresh every 30 seconds.
class KitchenBoard extends StatefulWidget {
  const KitchenBoard({
    super.key,
    required this.tickets,
    required this.actions,
    this.emptyTitle = 'No orders yet',
    this.emptyMessage = 'New orders appear here as soon as they are sent.',
  });

  final List<KitchenCardData> tickets;
  final KitchenActions actions;
  final String emptyTitle;
  final String emptyMessage;

  @override
  State<KitchenBoard> createState() => _KitchenBoardState();
}

class _KitchenBoardState extends State<KitchenBoard> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.tickets]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final by = {for (final s in KitchenStatus.all) s: sorted.where((t) => t.status == s).toList()};
    // Newest finished first, and only the last few.
    by[KitchenStatus.ready] = by[KitchenStatus.ready]!.reversed.take(12).toList();
    if (sorted.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.soup_kitchen_outlined, size: 64, color: KitchenPalette.readyColor),
              const SizedBox(height: 12),
              Text(widget.emptyTitle, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 6),
              Text(widget.emptyMessage, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (MediaQuery.sizeOf(context).width >= 900) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final s in KitchenStatus.all)
            Expanded(
              child: Column(
                children: [
                  _ColumnHeader(status: s, count: by[s]!.length),
                  Expanded(
                    child: _List(tickets: by[s]!, actions: widget.actions),
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            tabs: [
              for (final s in KitchenStatus.all)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: KitchenPalette.forStatus(s), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${KitchenStatus.title(s)} ${by[s]!.length}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final s in KitchenStatus.all) _List(tickets: by[s]!, actions: widget.actions),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.status, required this.count});
  final String status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final color = KitchenPalette.forStatus(status);
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 10, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              KitchenStatus.title(status),
              style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
          Text(
            '$count',
            style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 18),
          ),
        ],
      ),
    );
  }
}

class _List extends StatelessWidget {
  const _List({required this.tickets, required this.actions});
  final List<KitchenCardData> tickets;
  final KitchenActions actions;

  @override
  Widget build(BuildContext context) {
    if (tickets.isEmpty) {
      return Center(
        child: Text('Nothing here', style: TextStyle(color: KitchenPalette.dark.muted)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [for (final t in tickets) KitchenTicketCard(data: t, actions: actions)],
    );
  }
}
