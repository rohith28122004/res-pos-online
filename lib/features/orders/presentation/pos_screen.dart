import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/money/money.dart';
import '../../../core/pricing/pricing_engine.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/lock_screen.dart';
import '../../checkout/presentation/checkout_screen.dart';
import '../../menu/application/menu_service.dart';
import '../domain/order_models.dart';

/// Tracks whether the last edit reached the database.
class SaveStatus extends ChangeNotifier {
  int _inFlight = 0;
  Object? error;
  bool get saving => _inFlight > 0;

  Future<T?> run<T>(BuildContext context, Future<T> Function() action) async {
    _inFlight++;
    notifyListeners();
    try {
      final r = await action();
      error = null;
      return r;
    } on Object catch (e) {
      error = e;
      if (context.mounted) showError(context, e);
      return null;
    } finally {
      _inFlight--;
      notifyListeners();
    }
  }
}

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key, required this.orderId});
  final String orderId;
  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _save = SaveStatus();
  final _searchFocus = FocusNode(debugLabel: 'menu search');
  late final Stream<OrderDetail> _orderStream = ref.read(servicesProvider).orders.watchOrder(widget.orderId);
  late final Stream<MenuData> _menuStream = ref.read(servicesProvider).menu.watchMenu();

  @override
  void dispose() {
    _save.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> addItem(MenuItemView item) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    if (!item.available) {
      showError(context, '${item.name} is sold out');
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    if (item.needsOptions) {
      final choice = await showItemOptions(context, item);
      if (choice == null || !mounted) return;
      await _save.run(
        context,
        () => services.orders.addItem(
          actor,
          widget.orderId,
          itemId: item.id,
          variantId: choice.variantId,
          modifierIds: choice.modifierIds,
          quantity: choice.quantity,
          note: choice.note,
        ),
      );
    } else {
      await _save.run(context, () => services.orders.addItem(actor, widget.orderId, itemId: item.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return StreamBuilder<OrderDetail>(
      stream: _orderStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(error: snap.error!),
          );
        }
        if (!snap.hasData) return const Scaffold(body: LoadingView());
        final detail = snap.data!;
        if (detail.order.status != OrderStatus.open) {
          return Scaffold(
            appBar: AppBar(title: Text(detail.reference)),
            body: EmptyState(
              icon: Icons.check_circle_outline,
              title: detail.order.status == OrderStatus.finalized
                  ? 'This order has been billed'
                  : 'This order was cancelled',
              action: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Back to orders')),
            ),
          );
        }
        final menu = MenuPanel(
          stream: _menuStream,
          onItem: addItem,
          autofocusSearch: wide,
          searchFocus: _searchFocus,
          inCart: detail.quantitiesByItem,
          showShortcuts: wide,
        );
        final cart = CartPanel(detail: detail, save: _save, showShortcuts: wide);
        // Keyboard shortcuts for the Windows till; they work while typing in
        // the menu search too.
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.f2): _searchFocus.requestFocus,
            const SingleActivator(LogicalKeyboardKey.f8, includeRepeats: false): () {
              if (detail.unsentCount > 0 && !_save.saving) unawaited(sendOrderToKitchen(context, ref, detail, _save));
            },
            const SingleActivator(LogicalKeyboardKey.f9, includeRepeats: false): () {
              if (detail.canPay) unawaited(openCheckout(context, detail));
            },
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(detail.reference),
              actions: [_SaveIndicator(status: _save)],
            ),
            body: wide
                ? Row(
                    children: [
                      Expanded(flex: 3, child: menu),
                      const VerticalDivider(width: 1),
                      SizedBox(width: MediaQuery.sizeOf(context).width >= 1300 ? 460 : 400, child: cart),
                    ],
                  )
                : Column(
                    children: [
                      Expanded(child: menu),
                      _CartSummaryBar(detail: detail, save: _save),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

extension on OrderDetail {
  /// Quantity in the cart per menu item, for the badges on the menu buttons.
  Map<String, int> get quantitiesByItem {
    final out = <String, int>{};
    for (final l in activeLines) {
      final id = l.row.itemId;
      if (id != null) out[id] = (out[id] ?? 0) + l.row.quantity;
    }
    return out;
  }

  int get unsentCount => lines.fold<int>(0, (a, l) => a + (l.unsentQuantity > 0 ? l.unsentQuantity : 0));

  bool get canPay => pricing != null && activeLines.isNotEmpty;
}

Future<void> openCheckout(BuildContext context, OrderDetail detail) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => CheckoutScreen(orderId: detail.order.id)));

Future<void> sendOrderToKitchen(BuildContext context, WidgetRef ref, OrderDetail detail, SaveStatus save) async {
  final services = ref.read(servicesProvider);
  final op = services.ctx.ids.newId();
  final id = await save.run(
    context,
    () => services.orders.sendToKitchen(requireActor(ref), detail.order.id, operationId: op),
  );
  if (id != null && context.mounted) showInfo(context, 'Sent to kitchen');
}

class _SaveIndicator extends StatelessWidget {
  const _SaveIndicator({required this.status});
  final SaveStatus status;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: status,
    builder: (context, _) {
      if (status.saving) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: StatusChip(label: 'Saving…', color: AppColors.info),
        );
      }
      if (status.error != null) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: StatusChip(label: 'Last change not saved', color: AppColors.danger, icon: Icons.error_outline),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(12),
        child: StatusChip(label: 'Saved', color: AppColors.success, icon: Icons.check),
      );
    },
  );
}

class _CartSummaryBar extends StatelessWidget {
  const _CartSummaryBar({required this.detail, required this.save});
  final OrderDetail detail;
  final SaveStatus save;

  @override
  Widget build(BuildContext context) {
    final count = detail.activeLines.fold<int>(0, (a, l) => a + l.row.quantity);
    final total = detail.pricing?.total ?? 0;
    return Material(
      elevation: 8,
      color: AppColors.surfaceDim,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$count item(s)${detail.hasUnsentItems ? ' · not sent to kitchen' : ''}'),
                    Text(formatMoney(total), style: Theme.of(context).textTheme.titleLarge),
                  ],
                ),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.shopping_cart_outlined),
                label: const Text('View cart'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PhoneCartPage(orderId: detail.order.id, save: save),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneCartPage extends ConsumerWidget {
  const _PhoneCartPage({required this.orderId, required this.save});
  final String orderId;
  final SaveStatus save;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamView<OrderDetail>(
    stream: ref.watch(servicesProvider).orders.watchOrder(orderId),
    builder: (context, detail) => Scaffold(
      appBar: AppBar(
        title: Text(detail.reference),
        actions: [_SaveIndicator(status: save)],
      ),
      body: detail.order.status == OrderStatus.open
          ? CartPanel(detail: detail, save: save)
          : const EmptyState(icon: Icons.check_circle_outline, title: 'This order is closed'),
    ),
  );
}

// ---- Menu -------------------------------------------------------------------

class MenuPanel extends StatefulWidget {
  const MenuPanel({
    super.key,
    required this.stream,
    required this.onItem,
    this.autofocusSearch = false,
    this.searchFocus,
    this.inCart = const {},
    this.showShortcuts = false,
  });
  final Stream<MenuData> stream;
  final Future<void> Function(MenuItemView item) onItem;
  final bool autofocusSearch;
  final FocusNode? searchFocus;

  /// Quantity already in the cart per menu item id.
  final Map<String, int> inCart;
  final bool showShortcuts;

  @override
  State<MenuPanel> createState() => _MenuPanelState();
}

class _MenuPanelState extends State<MenuPanel> {
  final _search = TextEditingController();
  String? _category;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MenuItemView> _filter(MenuData menu) {
    final q = _query.trim().toLowerCase();
    return menu.items.where((i) {
      if (q.isNotEmpty) {
        return i.name.toLowerCase().contains(q) ||
            (i.row.sku?.toLowerCase().contains(q) ?? false) ||
            i.categoryName.toLowerCase().contains(q);
      }
      return _category == null || i.row.categoryId == _category;
    }).toList();
  }

  @override
  Widget build(BuildContext context) => StreamView<MenuData>(
    stream: widget.stream,
    builder: (context, menu) {
      final items = _filter(menu);
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _search,
              focusNode: widget.searchFocus,
              autofocus: widget.autofocusSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: widget.showShortcuts
                    ? 'Search menu (F2) · Enter adds the first match'
                    : 'Search menu (name, code, category)',
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
              onSubmitted: (_) {
                if (items.isNotEmpty) unawaited(widget.onItem(items.first));
              },
            ),
          ),
          SizedBox(
            height: 56,
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
                for (final c in menu.categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: _category == c.id,
                      onSelected: (_) => setState(() => _category = c.id),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? EmptyState(
                    icon: Icons.restaurant_menu_outlined,
                    title: menu.items.isEmpty ? 'The menu is empty' : 'No matching items',
                    message: menu.items.isEmpty ? 'An owner can add items in Menu, or import a CSV.' : null,
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 200,
                      mainAxisExtent: scaledExtent(context, 104),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _MenuButton(
                      item: items[i],
                      inCart: widget.inCart[items[i].id] ?? 0,
                      onTap: () => widget.onItem(items[i]),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.item, required this.onTap, this.inCart = 0});
  final MenuItemView item;
  final VoidCallback onTap;
  final int inCart;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final soldOut = !item.available;
    final added = inCart > 0 && !soldOut;
    return Semantics(
      button: true,
      label: '${item.name}, ${soldOut ? 'sold out' : formatMoney(item.fromPrice)}${added ? ', $inCart in cart' : ''}',
      child: Material(
        color: soldOut ? const Color(0xFFEDE9E3) : (added ? const Color(0xFFF0F7F6) : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: added
              ? const BorderSide(color: AppColors.accent, width: 1.5)
              : const BorderSide(color: Color(0xFFE6DED3)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: soldOut ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: t.titleSmall?.copyWith(color: soldOut ? Colors.black45 : null),
                        ),
                      ),
                      if (added)
                        ExcludeSemantics(
                          child: Container(
                            margin: const EdgeInsets.only(left: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.accent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$inCart',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        soldOut
                            ? 'Sold out'
                            : '${item.variants.length > 1 ? 'from ' : ''}${formatMoney(item.fromPrice)}',
                        style: t.bodyMedium?.copyWith(
                          color: soldOut ? AppColors.danger : AppColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (item.needsOptions && !soldOut) const Icon(Icons.tune, size: 16, color: Colors.black45),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ItemChoice {
  const ItemChoice({this.variantId, this.modifierIds = const [], this.quantity = 1, this.note});
  final String? variantId;
  final List<String> modifierIds;
  final int quantity;
  final String? note;
}

Future<ItemChoice?> showItemOptions(BuildContext context, MenuItemView item) => showModalBottomSheet<ItemChoice>(
  context: context,
  isScrollControlled: true,
  builder: (c) => _ItemOptionsSheet(item: item),
);

class _ItemOptionsSheet extends StatefulWidget {
  const _ItemOptionsSheet({required this.item});
  final MenuItemView item;
  @override
  State<_ItemOptionsSheet> createState() => _ItemOptionsSheetState();
}

class _ItemOptionsSheetState extends State<_ItemOptionsSheet> {
  late String? _variant = widget.item.variants.isEmpty ? null : widget.item.variants.first.id;
  final _mods = <String>{};
  int _qty = 1;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  int get _unit {
    final base = _variant == null
        ? widget.item.row.price
        : widget.item.variants.firstWhere((v) => v.id == _variant).price;
    return base + widget.item.modifiers.where((m) => _mods.contains(m.id)).fold<int>(0, (a, m) => a + m.price);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.item.name, style: t.titleLarge),
              if (widget.item.variants.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Size / variant', style: t.titleSmall),
                RadioGroup<String>(
                  groupValue: _variant,
                  onChanged: (v) => setState(() => _variant = v),
                  child: Column(
                    children: [
                      for (final v in widget.item.variants)
                        RadioListTile<String>(value: v.id, title: Text(v.name), secondary: Text(formatMoney(v.price))),
                    ],
                  ),
                ),
              ],
              if (widget.item.modifiers.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Add-ons', style: t.titleSmall),
                for (final m in widget.item.modifiers)
                  CheckboxListTile(
                    value: _mods.contains(m.id),
                    onChanged: (on) => setState(() => on == true ? _mods.add(m.id) : _mods.remove(m.id)),
                    title: Text(m.name),
                    secondary: Text(m.price == 0 ? 'free' : '+ ${formatMoney(m.price)}'),
                  ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Note for the kitchen (optional)'),
              ),
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Less',
                    onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('$_qty', style: t.titleLarge),
                  ),
                  IconButton.outlined(
                    tooltip: 'More',
                    onPressed: _qty < 999 ? () => setState(() => _qty++) : null,
                    icon: const Icon(Icons.add),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      ItemChoice(variantId: _variant, modifierIds: _mods.toList(), quantity: _qty, note: _note.text),
                    ),
                    child: Text('Add · ${formatMoney(_unit * _qty)}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---- Cart ---------------------------------------------------------------------

class CartPanel extends ConsumerWidget {
  const CartPanel({super.key, required this.detail, required this.save, this.showShortcuts = false});
  final OrderDetail detail;
  final SaveStatus save;

  /// Mentions the F8 / F9 keys (keyboard tills).
  final bool showShortcuts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    final pricing = detail.pricing;
    final t = Theme.of(context).textTheme;
    final pricedByKey = {for (final p in pricing?.lines ?? const <PricedLine>[]) p.key: p};
    final unsent = detail.unsentCount;
    final order = detail.order;

    Future<void> changeQty(OrderLineView l, int q) async {
      if (q < l.sentQuantity) {
        final reason = await askReason(
          context,
          title: 'Cancel ${l.sentQuantity - q} × ${l.row.itemName}?',
          hint: 'Reason (the kitchen already has this)',
        );
        if (reason == null || !context.mounted) return;
        await withOwnerApproval(
          context,
          ref,
          purpose: 'Cancelling items after they were sent to the kitchen',
          action: (approval) => services.orders.changeQuantity(actor, l.row.id, q, reason: reason, approval: approval),
        );
        return;
      }
      await save.run(context, () => services.orders.changeQuantity(actor, l.row.id, q));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(detail.reference, style: t.titleMedium),
                    Text(
                      [
                        OrderType.parse(order.orderType).label,
                        ?order.customerName,
                        if (order.guestCount != null) '${order.guestCount} guest(s)',
                      ].join(' · '),
                      style: t.bodySmall,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Order options',
                onSelected: (v) => _orderAction(context, ref, v),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'customer', child: Text('Customer name / note')),
                  if (order.orderType == OrderType.dineIn.code)
                    const PopupMenuItem(value: 'guests', child: Text('Guests')),
                  if (order.orderType == OrderType.dineIn.code)
                    const PopupMenuItem(value: 'move', child: Text('Move to another table')),
                  if (order.orderType == OrderType.delivery.code)
                    const PopupMenuItem(value: 'delivery', child: Text('Delivery charge')),
                  if (order.orderType == OrderType.dineIn.code)
                    PopupMenuItem(
                      value: 'service',
                      child: Text(order.serviceChargeBps > 0 ? 'Remove service charge' : 'Add service charge'),
                    ),
                  const PopupMenuItem(value: 'discount', child: Text('Bill discount')),
                  const PopupMenuItem(value: 'cancel', child: Text('Cancel order')),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: detail.activeLines.isEmpty
              ? const EmptyState(
                  icon: Icons.add_shopping_cart,
                  title: 'Cart is empty',
                  message: 'Tap menu items to add them.',
                )
              : ListView.separated(
                  itemCount: detail.activeLines.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final l = detail.activeLines[i];
                    final p = pricedByKey[l.row.id];
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  l.row.variantName == null
                                      ? l.row.itemName
                                      : '${l.row.itemName} (${l.row.variantName})',
                                  style: t.titleSmall,
                                ),
                                for (final m in l.modifiers) Text('+ ${m.name}', style: t.bodySmall),
                                if (l.row.note != null)
                                  Text(
                                    'Note: ${l.row.note}',
                                    style: t.bodySmall?.copyWith(fontStyle: FontStyle.italic),
                                  ),
                                if (p != null && p.lineDiscountEntered > 0)
                                  Text(
                                    'Discount −${formatMoney(p.lineDiscountEntered)}',
                                    style: t.bodySmall?.copyWith(color: AppColors.success),
                                  ),
                                if (l.sentQuantity > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: StatusChip(
                                      label: l.unsentQuantity > 0
                                          ? 'Kitchen has ${l.sentQuantity}, ${l.unsentQuantity} new'
                                          : 'Sent to kitchen',
                                      color: l.unsentQuantity > 0 ? AppColors.warning : AppColors.info,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(formatMoney(p?.grossEntered ?? 0), style: t.titleSmall),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Remove one',
                                    onPressed: () => changeQty(l, l.row.quantity - 1),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Text('${l.row.quantity}', style: t.titleMedium),
                                  IconButton(
                                    tooltip: 'Add one',
                                    onPressed: () => changeQty(l, l.row.quantity + 1),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Line options',
                                    onSelected: (v) => _lineAction(context, ref, l, v),
                                    itemBuilder: (_) => [
                                      if (!l.lockedByKitchen) const PopupMenuItem(value: 'note', child: Text('Note')),
                                      const PopupMenuItem(value: 'qty', child: Text('Set quantity')),
                                      const PopupMenuItem(value: 'discount', child: Text('Line discount')),
                                      const PopupMenuItem(value: 'remove', child: Text('Remove')),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: pricing == null
              ? Text(detail.pricingError ?? '', style: const TextStyle(color: AppColors.danger))
              : Column(
                  children: [
                    MoneyRow('Subtotal', pricing.itemsGrossEntered),
                    if (pricing.discountEnteredTotal > 0)
                      MoneyRow('Discounts', -pricing.discountEnteredTotal, color: AppColors.success),
                    for (final c in pricing.charges) MoneyRow(c.label, c.amountEntered),
                    for (final tx in pricing.taxBreakdown)
                      if (tx.amount > 0) MoneyRow('${tx.name} ${formatBps(tx.rateBps)}', tx.amount),
                    if (pricing.lines.any((l) => l.taxSnapshot.mode.name == 'inclusive'))
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Some prices include tax', style: t.bodySmall),
                      ),
                    if (pricing.roundingAdjustment != 0) MoneyRow('Rounding', pricing.roundingAdjustment),
                    MoneyRow('Total', pricing.total, bold: true, big: true),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: _shortcutHint(
                  'Send new items to the kitchen (F8)',
                  OutlinedButton.icon(
                    icon: const Icon(Icons.soup_kitchen_outlined),
                    label: Text(unsent > 0 ? 'Send to kitchen ($unsent)' : 'Kitchen up to date'),
                    onPressed: unsent == 0 ? null : () => sendOrderToKitchen(context, ref, detail, save),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _shortcutHint(
                  'Take payment (F9)',
                  FilledButton.icon(
                    icon: const Icon(Icons.payments_outlined),
                    label: Text(pricing == null ? 'Pay' : 'Pay ${formatMoney(pricing.total)}'),
                    onPressed: detail.canPay ? () => openCheckout(context, detail) : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _shortcutHint(String message, Widget child) => showShortcuts ? Tooltip(message: message, child: child) : child;

  Future<void> _lineAction(BuildContext context, WidgetRef ref, OrderLineView l, String action) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    switch (action) {
      case 'note':
        final note = await askText(
          context,
          title: 'Note for ${l.row.itemName}',
          label: 'Note',
          initial: l.row.note ?? '',
          maxLength: 140,
        );
        if (note != null && context.mounted) {
          await save.run(context, () => services.orders.updateLineNote(actor, l.row.id, note));
        }
      case 'qty':
        final text = await askText(
          context,
          title: 'Quantity',
          initial: '${l.row.quantity}',
          maxLength: 3,
          keyboard: TextInputType.number,
        );
        final q = int.tryParse(text ?? '');
        if (q == null || !context.mounted) return;
        if (q < l.sentQuantity) {
          final reason = await askReason(context, title: 'Cancel items the kitchen already has?');
          if (reason == null || !context.mounted) return;
          await withOwnerApproval(
            context,
            ref,
            purpose: 'Cancelling items after they were sent to the kitchen',
            action: (a) => services.orders.changeQuantity(actor, l.row.id, q, reason: reason, approval: a),
          );
        } else {
          await save.run(context, () => services.orders.changeQuantity(actor, l.row.id, q));
        }
      case 'discount':
        final d = await showDiscountDialog(context, title: 'Discount on ${l.row.itemName}');
        if (d == null || !context.mounted) return;
        await withOwnerApproval(
          context,
          ref,
          purpose: 'This discount is above the cashier limit',
          action: (a) => services.orders.setLineDiscount(actor, l.row.id, d.discount, approval: a),
        );
      case 'remove':
        if (l.sentQuantity > 0) {
          final reason = await askReason(context, title: 'Remove ${l.row.itemName}? The kitchen already has it.');
          if (reason == null || !context.mounted) return;
          await withOwnerApproval(
            context,
            ref,
            purpose: 'Cancelling items after they were sent to the kitchen',
            action: (a) => services.orders.changeQuantity(actor, l.row.id, 0, reason: reason, approval: a),
          );
        } else {
          await save.run(context, () => services.orders.changeQuantity(actor, l.row.id, 0));
        }
    }
  }

  Future<void> _orderAction(BuildContext context, WidgetRef ref, String action) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    final order = detail.order;
    switch (action) {
      case 'customer':
        final name = await askText(context, title: 'Customer name (optional)', initial: order.customerName ?? '');
        if (name != null && context.mounted) {
          await save.run(
            context,
            () => services.orders.updateDetails(
              actor,
              order.id,
              customerName: name,
              note: order.note,
              guestCount: order.guestCount,
            ),
          );
        }
      case 'guests':
        final text = await askText(
          context,
          title: 'Number of guests',
          initial: order.guestCount?.toString() ?? '',
          maxLength: 3,
          keyboard: TextInputType.number,
        );
        if (text == null || !context.mounted) return;
        await save.run(
          context,
          () => services.orders.updateDetails(
            actor,
            order.id,
            customerName: order.customerName,
            note: order.note,
            guestCount: int.tryParse(text),
          ),
        );
      case 'move':
        final tables = await services.tables.tableStatus();
        if (!context.mounted) return;
        final free = tables.where((t) => !t.occupied).toList();
        final picked = await showDialog<String>(
          context: context,
          builder: (c) => SimpleDialog(
            title: const Text('Move to table'),
            children: [
              if (free.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('No free tables')),
              for (final t in free)
                SimpleDialogOption(onPressed: () => Navigator.pop(c, t.table.id), child: Text(t.table.name)),
            ],
          ),
        );
        if (picked != null && context.mounted) {
          await save.run(context, () => services.orders.moveToTable(actor, order.id, picked));
        }
      case 'delivery':
        final text = await askText(
          context,
          title: 'Delivery charge (₹)',
          initial: money.plain(order.deliveryCharge),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        );
        if (text == null || !context.mounted) return;
        await save.run(context, () async => services.orders.setDeliveryCharge(actor, order.id, money.parse(text)));
      case 'service':
        await save.run(
          context,
          () => services.orders.setServiceCharge(actor, order.id, enabled: order.serviceChargeBps == 0),
        );
      case 'discount':
        final d = await showDiscountDialog(context, title: 'Bill discount', withReason: true);
        if (d == null || !context.mounted) return;
        await withOwnerApproval(
          context,
          ref,
          purpose: 'This discount is above the cashier limit',
          action: (a) => services.orders.setBillDiscount(actor, order.id, d.discount, reason: d.reason, approval: a),
        );
      case 'cancel':
        final reason = await askReason(context, title: 'Cancel this order?', confirmLabel: 'Cancel order');
        if (reason == null || !context.mounted) return;
        final ok = await withOwnerApproval(
          context,
          ref,
          purpose: 'The kitchen has already received items from this order',
          action: (a) => services.orders.cancelOrder(actor, order.id, reason: reason, approval: a).then((_) => true),
        );
        if (ok == true && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }
}

class DiscountChoice {
  const DiscountChoice(this.discount, this.reason);
  final Discount discount;
  final String? reason;
}

/// Asks for a discount (and optionally a reason).
Future<DiscountChoice?> showDiscountDialog(BuildContext context, {required String title, bool withReason = false}) =>
    showDialog<DiscountChoice>(
      context: context,
      builder: (_) => _DiscountDialog(title: title, withReason: withReason),
    );

class _DiscountDialog extends StatefulWidget {
  const _DiscountDialog({required this.title, required this.withReason});
  final String title;
  final bool withReason;
  @override
  State<_DiscountDialog> createState() => _DiscountDialogState();
}

class _DiscountDialogState extends State<_DiscountDialog> {
  DiscountType _type = DiscountType.percent;
  final _value = TextEditingController();
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _value.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _ok() {
    try {
      final text = _value.text.trim();
      final Discount d;
      if (text.isEmpty || text == '0') {
        d = Discount.none;
      } else if (_type == DiscountType.percent) {
        d = Discount.percent(parsePercentToBps(text));
      } else {
        d = Discount.amount(money.parse(text));
      }
      Navigator.pop(context, DiscountChoice(d, _reason.text.trim().isEmpty ? null : _reason.text.trim()));
    } on Object catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 340,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<DiscountType>(
            segments: const [
              ButtonSegment(value: DiscountType.percent, label: Text('Percent')),
              ButtonSegment(value: DiscountType.amount, label: Text('Amount')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _value,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: InputDecoration(
              labelText: _type == DiscountType.percent ? 'Percent' : 'Amount',
              suffixText: _type == DiscountType.percent ? '%' : null,
              prefixText: _type == DiscountType.amount ? '₹ ' : null,
              helperText: 'Enter 0 to remove the discount',
              errorText: _error,
            ),
            onSubmitted: (_) => _ok(),
          ),
          if (widget.withReason) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _reason,
              maxLength: 140,
              decoration: const InputDecoration(labelText: 'Reason (optional)'),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: _ok, child: const Text('Apply')),
    ],
  );
}
