import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/money/money.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/sync/host_outbox.dart';

class MenuVariant {
  const MenuVariant({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final int price;
}

class MenuModifier {
  const MenuModifier({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final int price;
}

class MenuItemView {
  const MenuItemView({
    required this.row,
    required this.categoryName,
    required this.variants,
    required this.modifiers,
    this.taxProfileName,
  });

  final MenuItemRow row;
  final String categoryName;
  final List<MenuVariant> variants;
  final List<MenuModifier> modifiers;
  final String? taxProfileName;

  String get id => row.id;
  String get name => row.name;
  bool get available => row.available;
  bool get hasVariants => variants.isNotEmpty;
  bool get needsOptions => variants.length > 1 || modifiers.isNotEmpty;

  /// Lowest selectable price, for the menu button.
  int get fromPrice => variants.isEmpty ? row.price : variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
}

class MenuData {
  const MenuData({required this.categories, required this.items});
  final List<CategoryRow> categories;
  final List<MenuItemView> items;

  static const empty = MenuData(categories: [], items: []);
}

class VariantInput {
  const VariantInput({this.id, required this.name, required this.price});
  final String? id;
  final String name;
  final int price;
}

class ModifierInput {
  const ModifierInput({this.id, required this.name, required this.price});
  final String? id;
  final String name;
  final int price;
}

class ItemInput {
  const ItemInput({
    this.id,
    required this.categoryId,
    required this.name,
    required this.price,
    this.taxProfileId,
    this.available = true,
    this.sku,
    this.variants = const [],
    this.modifiers = const [],
  });

  final String? id;
  final String categoryId;
  final String name;
  final int price;
  final String? taxProfileId;
  final bool available;
  final String? sku;
  final List<VariantInput> variants;
  final List<ModifierInput> modifiers;
}

class MenuService {
  MenuService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  // ---- Reading -------------------------------------------------------------

  Stream<MenuData> watchMenu({bool includeArchived = false}) async* {
    yield await loadMenu(includeArchived: includeArchived);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.categories,
        _db.menuItems,
        _db.itemVariants,
        _db.itemModifiers,
        _db.taxProfiles,
      ]),
    )) {
      yield await loadMenu(includeArchived: includeArchived);
    }
  }

  Future<MenuData> loadMenu({bool includeArchived = false}) async {
    final cq = _db.select(_db.categories)
      ..orderBy([(c) => OrderingTerm(expression: c.sortOrder), (c) => OrderingTerm(expression: c.name)]);
    if (!includeArchived) cq.where((c) => c.archived.equals(false));
    final categories = await cq.get();
    final catNames = {for (final c in categories) c.id: c.name};

    final iq = _db.select(_db.menuItems)
      ..orderBy([(i) => OrderingTerm(expression: i.sortOrder), (i) => OrderingTerm(expression: i.name)]);
    if (!includeArchived) iq.where((i) => i.archived.equals(false));
    final items = (await iq.get()).where((i) => catNames.containsKey(i.categoryId)).toList();

    final variants =
        await (_db.select(_db.itemVariants)
              ..where((v) => v.archived.equals(false))
              ..orderBy([(v) => OrderingTerm(expression: v.sortOrder)]))
            .get();
    final modifiers =
        await (_db.select(_db.itemModifiers)
              ..where((m) => m.archived.equals(false))
              ..orderBy([(m) => OrderingTerm(expression: m.sortOrder)]))
            .get();
    final taxNames = {for (final t in await _db.select(_db.taxProfiles).get()) t.id: t.name};

    final byItemV = <String, List<MenuVariant>>{};
    for (final v in variants) {
      byItemV.putIfAbsent(v.itemId, () => []).add(MenuVariant(id: v.id, name: v.name, price: v.price));
    }
    final byItemM = <String, List<MenuModifier>>{};
    for (final m in modifiers) {
      byItemM.putIfAbsent(m.itemId, () => []).add(MenuModifier(id: m.id, name: m.name, price: m.price));
    }
    return MenuData(
      categories: categories,
      items: [
        for (final i in items)
          MenuItemView(
            row: i,
            categoryName: catNames[i.categoryId]!,
            variants: byItemV[i.id] ?? const [],
            modifiers: byItemM[i.id] ?? const [],
            taxProfileName: i.taxProfileId == null ? null : taxNames[i.taxProfileId],
          ),
      ],
    );
  }

  // ---- Categories -----------------------------------------------------------

  Future<String> createCategory(Actor actor, String name) async {
    actor.require(Permission.manageMenu);
    final n = requireText(name, 'Category name', max: 40);
    final id = ctx.ids.newId();
    await _db.transaction(() async {
      final count = await _db.select(_db.categories).get().then((r) => r.length);
      await _db
          .into(_db.categories)
          .insert(CategoriesCompanion.insert(id: id, name: n, sortOrder: Value(count), updatedAt: ctx.nowMs()));
      await ctx.audit(actor, 'menu.category_created', entityType: 'category', entityId: id, details: {'name': n});
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
    return id;
  }

  Future<void> renameCategory(Actor actor, String id, String name) async {
    actor.require(Permission.manageMenu);
    final n = requireText(name, 'Category name', max: 40);
    await _db.transaction(() async {
      final updated = await (_db.update(
        _db.categories,
      )..where((c) => c.id.equals(id))).write(CategoriesCompanion(name: Value(n), updatedAt: Value(ctx.nowMs())));
      if (updated == 0) throw const NotFoundException('Category not found');
      await ctx.audit(actor, 'menu.category_renamed', entityType: 'category', entityId: id, details: {'name': n});
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
  }

  Future<void> setCategoryArchived(Actor actor, String id, bool archived) async {
    actor.require(Permission.manageMenu);
    await _db.transaction(() async {
      await (_db.update(_db.categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(archived: Value(archived), updatedAt: Value(ctx.nowMs())),
      );
      await ctx.audit(
        actor,
        archived ? 'menu.category_archived' : 'menu.category_restored',
        entityType: 'category',
        entityId: id,
      );
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
  }

  Future<void> reorderCategories(Actor actor, List<String> orderedIds) async {
    actor.require(Permission.manageMenu);
    await _db.transaction(() async {
      for (var i = 0; i < orderedIds.length; i++) {
        await (_db.update(
          _db.categories,
        )..where((c) => c.id.equals(orderedIds[i]))).write(CategoriesCompanion(sortOrder: Value(i)));
      }
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
  }

  // ---- Items ------------------------------------------------------------------

  void _validateItem(ItemInput input) {
    requireText(input.name, 'Item name', max: 80);
    if (input.price < 0) throw const ValidationException('Price cannot be negative');
    final names = <String>{};
    for (final v in input.variants) {
      final n = requireText(v.name, 'Variant name', max: 40).toLowerCase();
      if (!names.add(n)) throw ValidationException('Variant "${v.name}" is listed twice');
      if (v.price < 0) throw const ValidationException('Variant price cannot be negative');
    }
    final mods = <String>{};
    for (final m in input.modifiers) {
      final n = requireText(m.name, 'Modifier name', max: 40).toLowerCase();
      if (!mods.add(n)) throw ValidationException('Modifier "${m.name}" is listed twice');
      if (m.price < 0) throw const ValidationException('Modifier price cannot be negative');
    }
  }

  /// Creates or updates an item with its variants and modifiers. Variants or
  /// modifiers removed from [input] are archived, never deleted. Price edits
  /// only affect lines added afterwards (open lines keep their captured price).
  Future<String> saveItem(Actor actor, ItemInput input) async {
    actor.require(Permission.manageMenu);
    _validateItem(input);
    final category = await (_db.select(_db.categories)..where((c) => c.id.equals(input.categoryId))).getSingleOrNull();
    if (category == null) throw const ValidationException('Choose a category');
    if (input.taxProfileId != null) {
      final tp = await (_db.select(_db.taxProfiles)..where((t) => t.id.equals(input.taxProfileId!))).getSingleOrNull();
      if (tp == null) throw const ValidationException('Unknown tax profile');
    }
    final now = ctx.nowMs();
    return _db.transaction(() async {
      final id = input.id ?? ctx.ids.newId();
      final before = input.id == null
          ? null
          : await (_db.select(_db.menuItems)..where((i) => i.id.equals(input.id!))).getSingleOrNull();
      if (input.id != null && before == null) throw const NotFoundException('Item not found');
      final beforeVariants = before == null
          ? <ItemVariantRow>[]
          : await (_db.select(_db.itemVariants)..where((v) => v.itemId.equals(id))).get();
      final beforeMods = before == null
          ? <ItemModifierRow>[]
          : await (_db.select(_db.itemModifiers)..where((m) => m.itemId.equals(id))).get();

      final basePrice = input.variants.isEmpty ? input.price : input.variants.first.price;
      if (before == null) {
        final count = (await (_db.select(
          _db.menuItems,
        )..where((i) => i.categoryId.equals(input.categoryId))).get()).length;
        await _db
            .into(_db.menuItems)
            .insert(
              MenuItemsCompanion.insert(
                id: id,
                categoryId: input.categoryId,
                name: input.name.trim(),
                price: basePrice,
                taxProfileId: Value(input.taxProfileId),
                available: Value(input.available),
                sku: Value(optionalText(input.sku, max: 40)),
                sortOrder: Value(count),
                updatedAt: now,
              ),
            );
      } else {
        await (_db.update(_db.menuItems)..where((i) => i.id.equals(id))).write(
          MenuItemsCompanion(
            categoryId: Value(input.categoryId),
            name: Value(input.name.trim()),
            price: Value(basePrice),
            taxProfileId: Value(input.taxProfileId),
            available: Value(input.available),
            sku: Value(optionalText(input.sku, max: 40)),
            updatedAt: Value(now),
          ),
        );
      }

      final keptVariantIds = <String>{};
      for (var i = 0; i < input.variants.length; i++) {
        final v = input.variants[i];
        final existing = v.id == null ? null : beforeVariants.where((b) => b.id == v.id).firstOrNull;
        if (existing == null) {
          final vid = ctx.ids.newId();
          keptVariantIds.add(vid);
          await _db
              .into(_db.itemVariants)
              .insert(
                ItemVariantsCompanion.insert(
                  id: vid,
                  itemId: id,
                  name: v.name.trim(),
                  price: v.price,
                  sortOrder: Value(i),
                ),
              );
        } else {
          keptVariantIds.add(existing.id);
          await (_db.update(_db.itemVariants)..where((x) => x.id.equals(existing.id))).write(
            ItemVariantsCompanion(
              name: Value(v.name.trim()),
              price: Value(v.price),
              sortOrder: Value(i),
              archived: const Value(false),
            ),
          );
        }
      }
      for (final b in beforeVariants.where((b) => !keptVariantIds.contains(b.id) && !b.archived)) {
        await (_db.update(
          _db.itemVariants,
        )..where((x) => x.id.equals(b.id))).write(const ItemVariantsCompanion(archived: Value(true)));
      }

      final keptModIds = <String>{};
      for (var i = 0; i < input.modifiers.length; i++) {
        final m = input.modifiers[i];
        final existing = m.id == null ? null : beforeMods.where((b) => b.id == m.id).firstOrNull;
        if (existing == null) {
          final mid = ctx.ids.newId();
          keptModIds.add(mid);
          await _db
              .into(_db.itemModifiers)
              .insert(
                ItemModifiersCompanion.insert(
                  id: mid,
                  itemId: id,
                  name: m.name.trim(),
                  price: m.price,
                  sortOrder: Value(i),
                ),
              );
        } else {
          keptModIds.add(existing.id);
          await (_db.update(_db.itemModifiers)..where((x) => x.id.equals(existing.id))).write(
            ItemModifiersCompanion(
              name: Value(m.name.trim()),
              price: Value(m.price),
              sortOrder: Value(i),
              archived: const Value(false),
            ),
          );
        }
      }
      for (final b in beforeMods.where((b) => !keptModIds.contains(b.id) && !b.archived)) {
        await (_db.update(
          _db.itemModifiers,
        )..where((x) => x.id.equals(b.id))).write(const ItemModifiersCompanion(archived: Value(true)));
      }

      final priceChanged =
          before != null &&
          (before.price != basePrice ||
              _priceList(beforeVariants.where((v) => !v.archived).map((v) => (v.name, v.price))) !=
                  _priceList(input.variants.map((v) => (v.name.trim(), v.price))) ||
              _priceList(beforeMods.where((m) => !m.archived).map((m) => (m.name, m.price))) !=
                  _priceList(input.modifiers.map((m) => (m.name.trim(), m.price))));
      await ctx.audit(
        actor,
        before == null ? 'menu.item_created' : (priceChanged ? 'menu.price_changed' : 'menu.item_updated'),
        entityType: 'menu_item',
        entityId: id,
        details: {
          'name': input.name.trim(),
          if (before != null)
            'before': {
              'price': before.price,
              'variants': _priceList(beforeVariants.where((v) => !v.archived).map((v) => (v.name, v.price))),
            },
          'after': {'price': basePrice, 'variants': _priceList(input.variants.map((v) => (v.name.trim(), v.price)))},
        },
      );
      await ctx.outbox.changed(Aggregate.menu, 'menu');
      return id;
    });
  }

  static String _priceList(Iterable<(String, int)> entries) => jsonEncode([for (final e in entries) '${e.$1}=${e.$2}']);

  /// Sold-out toggle; allowed for anyone who takes orders.
  Future<void> setItemAvailable(Actor actor, String itemId, bool available) async {
    actor.require(Permission.takeOrders);
    await _db.transaction(() async {
      final n = await (_db.update(_db.menuItems)..where((i) => i.id.equals(itemId))).write(
        MenuItemsCompanion(available: Value(available), updatedAt: Value(ctx.nowMs())),
      );
      if (n == 0) throw const NotFoundException('Item not found');
      await ctx.audit(
        actor,
        available ? 'menu.item_available' : 'menu.item_sold_out',
        entityType: 'menu_item',
        entityId: itemId,
      );
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
  }

  Future<void> setItemArchived(Actor actor, String itemId, bool archived) async {
    actor.require(Permission.manageMenu);
    await _db.transaction(() async {
      await (_db.update(_db.menuItems)..where((i) => i.id.equals(itemId))).write(
        MenuItemsCompanion(archived: Value(archived), updatedAt: Value(ctx.nowMs())),
      );
      await ctx.audit(
        actor,
        archived ? 'menu.item_archived' : 'menu.item_restored',
        entityType: 'menu_item',
        entityId: itemId,
      );
      await ctx.outbox.changed(Aggregate.menu, 'menu');
    });
  }

  Future<CurrencyFormat> currency() => ctx.currency();
}
