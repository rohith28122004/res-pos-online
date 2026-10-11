import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/sync/client_database.dart';
import '../../../shared/widgets/common.dart';
import '../../devices/presentation/device_app.dart';
import '../../devices/presentation/device_providers.dart';
import '../application/drafts.dart';

/// Builds an order (new table / takeaway, or additions to an accepted order)
/// from the cached menu. Nothing is final until the POS accepts it.
class OrderBuilderScreen extends ConsumerStatefulWidget {
  const OrderBuilderScreen({
    super.key,
    required this.orderType,
    this.tableId,
    this.tableLabel,
    this.orderId,
    this.orderRef,
  });

  final String orderType;
  final String? tableId;
  final String? tableLabel;

  /// Adding to an order the POS already accepted.
  final String? orderId;
  final String? orderRef;

  @override
  ConsumerState<OrderBuilderScreen> createState() => _OrderBuilderScreenState();
}

class _OrderBuilderScreenState extends ConsumerState<OrderBuilderScreen> {
  DraftRow? _draft;
  List<DraftLine> _lines = [];
  String? _category;
  String _search = '';
  int? _guests;

  DraftStore get _store => DraftStore(ref.read(deviceRuntimeProvider).db, ref.read(deviceSyncProvider).clock);

  @override
  void initState() {
    super.initState();
    unawaited(Future.microtask(_load));
  }

  Future<void> _load() async {
    final session = await ref.read(deviceSyncProvider).session();
    if (session == null) return;
    final d = await _store.open(
      staffId: session.staffId,
      orderType: widget.orderType,
      tableId: widget.tableId,
      tableLabel: widget.tableLabel,
      orderId: widget.orderId,
    );
    if (!mounted) return;
    setState(() {
      _draft = d;
      _lines = DraftStore.linesOf(d);
      _guests = d.guestCount;
    });
  }

  Future<void> _save() async {
    final d = _draft;
    if (d != null) await _store.save(d.id, _lines, guestCount: _guests);
  }

  void _add(DraftLine line) {
    setState(() => _lines = [..._lines, line]);
    unawaited(HapticFeedback.selectionClick());
    unawaited(_save());
  }

  int get _count => _lines.fold(0, (a, l) => a + l.quantity);
  int get _total => _lines.fold(0, (a, l) => a + l.lineTotal);

  String get _title => widget.orderRef != null ? 'Add to ${widget.orderRef}' : (widget.tableLabel ?? 'Takeaway');

  @override
  Widget build(BuildContext context) {
    final cache = ref.watch(cacheViewProvider).value ?? const CacheView();
    final cats = cache.categories;
    final q = _search.trim().toLowerCase();
    final items = cache.items.where((i) {
      if (q.isNotEmpty) return (i['name']! as String).toLowerCase().contains(q);
      return _category == null || i['categoryId'] == _category;
    }).toList();
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: Column(
        children: [
          const LinkBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search the menu'),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: _category == null,
                    onSelected: (_) => setState(() => _category = null),
                  ),
                ),
                for (final c in cats)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c['name']! as String),
                      selected: _category == c['categoryId'],
                      onSelected: (_) => setState(() => _category = c['categoryId']! as String),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const EmptyState(icon: Icons.search_off, title: 'Nothing found')
                : ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      for (final i in items)
                        ListTile(
                          enabled: i['available'] == true,
                          title: Text(i['name']! as String),
                          subtitle: i['available'] == true ? null : const Text('Sold out'),
                          trailing: Text(
                            (i['variants']! as List).isEmpty
                                ? formatMoney(i['price']! as int)
                                : 'from ${formatMoney(((i['variants']! as List).map((v) => (v as Map)['price']! as int)).reduce((a, b) => a < b ? a : b))}',
                          ),
                          onTap: () async {
                            final line = await showModalBottomSheet<DraftLine>(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => ItemOptionsSheet(item: i),
                            );
                            if (line != null) _add(line);
                          },
                        ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _count == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton(
                  onPressed: _draft == null ? null : () => _review(context),
                  child: Text('Review $_count item${_count == 1 ? '' : 's'} · about ${formatMoney(_total)}'),
                ),
              ),
            ),
    );
  }

  Future<void> _review(BuildContext context) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) {
          void update(List<DraftLine> lines) {
            setState(() => _lines = lines);
            setLocal(() {});
            unawaited(_save());
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: Text(_title, style: Theme.of(c).textTheme.titleMedium),
                    subtitle: const Text('Prices are estimates from this phone. The POS confirms them.'),
                  ),
                  if (widget.orderType == 'dine_in' && widget.orderId == null)
                    ListTile(
                      title: const Text('Guests'),
                      trailing: SizedBox(
                        width: 160,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            IconButton(
                              onPressed: (_guests ?? 0) <= 1
                                  ? null
                                  : () {
                                      setState(() => _guests = _guests! - 1);
                                      setLocal(() {});
                                    },
                              icon: const Icon(Icons.remove),
                            ),
                            Text('${_guests ?? '-'}'),
                            IconButton(
                              onPressed: () {
                                setState(() => _guests = (_guests ?? 0) + 1);
                                setLocal(() {});
                              },
                              icon: const Icon(Icons.add),
                            ),
                          ],
                        ),
                      ),
                    ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final l in _lines)
                          ListTile(
                            title: Text(l.description),
                            subtitle: l.note == null ? null : Text('Note: ${l.note}'),
                            trailing: SizedBox(
                              width: 170,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    tooltip: 'One less',
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () => update([
                                      for (final x in _lines)
                                        if (x.key != l.key)
                                          x
                                        else if (x.quantity > 1)
                                          x.copyWith(quantity: x.quantity - 1),
                                    ]),
                                  ),
                                  Text('${l.quantity}'),
                                  IconButton(
                                    tooltip: 'One more',
                                    icon: const Icon(Icons.add_circle_outline),
                                    onPressed: l.quantity >= 99
                                        ? null
                                        : () => update([
                                            for (final x in _lines)
                                              x.key == l.key ? x.copyWith(quantity: x.quantity + 1) : x,
                                          ]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: Text('Send to the kitchen · about ${formatMoney(_total)}'),
                      onPressed: _lines.isEmpty
                          ? null
                          : () async {
                              final sync = ref.read(deviceSyncProvider);
                              await guard(c, () => _store.send(sync, _draft!, _lines, guestCount: _guests));
                              if (c.mounted) Navigator.pop(c, true);
                            },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (sent == true && context.mounted) {
      showInfo(context, 'Saved on this phone and sent to the POS. Check "Sent" for its answer.');
      Navigator.of(context).pop();
    }
  }
}

/// Size, add-ons, quantity and note for one menu item.
class ItemOptionsSheet extends StatefulWidget {
  const ItemOptionsSheet({super.key, required this.item});
  final Map<String, Object?> item;
  @override
  State<ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<ItemOptionsSheet> {
  late final List<Map<String, Object?>> _variants = [
    for (final v in widget.item['variants']! as List) (v! as Map).cast<String, Object?>(),
  ];
  late final List<Map<String, Object?>> _mods = [
    for (final m in widget.item['modifiers']! as List) (m! as Map).cast<String, Object?>(),
  ];
  late String? _variant = _variants.length == 1 ? _variants.single['variantId']! as String : null;
  final _chosen = <String>{};
  int _qty = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _unit {
    final base = _variant == null
        ? widget.item['price']! as int
        : _variants.firstWhere((v) => v['variantId'] == _variant)['price']! as int;
    return base +
        _mods.where((m) => _chosen.contains(m['modifierId'])).fold<int>(0, (a, m) => a + (m['price']! as int));
  }

  @override
  Widget build(BuildContext context) {
    final needsVariant = _variants.isNotEmpty && _variant == null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.item['name']! as String, style: Theme.of(context).textTheme.titleLarge),
              if (_variants.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Size'),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final v in _variants)
                      ChoiceChip(
                        label: Text('${v['name']} · ${formatMoney(v['price']! as int)}'),
                        selected: _variant == v['variantId'],
                        onSelected: (_) => setState(() => _variant = v['variantId']! as String),
                      ),
                  ],
                ),
              ],
              if (_mods.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Add-ons'),
                for (final m in _mods)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: _chosen.contains(m['modifierId']),
                    title: Text('${m['name']} +${formatMoney(m['price']! as int)}'),
                    onChanged: (v) => setState(
                      () => v == true ? _chosen.add(m['modifierId']! as String) : _chosen.remove(m['modifierId']),
                    ),
                  ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Quantity'),
                  const Spacer(),
                  IconButton(
                    onPressed: _qty <= 1 ? null : () => setState(() => _qty--),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_qty', style: Theme.of(context).textTheme.titleMedium),
                  IconButton(
                    onPressed: _qty >= 99 ? null : () => setState(() => _qty++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
              TextField(
                controller: _note,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Note for the kitchen (optional)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: needsVariant
                    ? null
                    : () {
                        final variant = _variants.where((v) => v['variantId'] == _variant).firstOrNull;
                        final mods = _mods.where((m) => _chosen.contains(m['modifierId'])).toList();
                        Navigator.pop(
                          context,
                          DraftLine(
                            key: const Uuid().v4(),
                            itemId: widget.item['itemId']! as String,
                            itemName: widget.item['name']! as String,
                            variantId: variant?['variantId'] as String?,
                            variantName: variant?['name'] as String?,
                            modifierIds: [for (final m in mods) m['modifierId']! as String],
                            modifierNames: [for (final m in mods) m['name']! as String],
                            quantity: _qty,
                            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
                            unitPrice: _unit,
                          ),
                        );
                      },
                child: Text(needsVariant ? 'Choose a size' : 'Add · ${formatMoney(_unit * _qty)}'),
              ),
              const SizedBox(height: 4),
              Text(
                'Price from this phone\'s menu copy; the POS confirms it.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.ink.withValues(alpha: 0.7)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
