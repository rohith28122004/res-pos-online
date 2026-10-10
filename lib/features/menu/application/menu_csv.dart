import 'dart:convert';
import 'dart:typed_data';

import '../../../core/csv/csv.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../settings/application/settings_service.dart';
import 'menu_service.dart';

/// Menu CSV format (one row per item, or per variant):
///
/// ```
/// category,item,variant,price,tax_profile,available,modifiers,sku
/// Coffee,Cappuccino,Small,120.00,GST 5%,yes,"Extra shot=30; Oat milk=40",CAP-S
/// Coffee,Cappuccino,Large,160.00,GST 5%,yes,,CAP-L
/// Bakery,Croissant,,90,,yes,,
/// ```
///
/// Import adds and updates; it never deletes or archives anything. Items are
/// matched by category + item name (case-insensitive), variants by name.
const menuCsvHeader = ['category', 'item', 'variant', 'price', 'tax_profile', 'available', 'modifiers', 'sku'];

class MenuCsvRowError {
  const MenuCsvRowError(this.line, this.message);
  final int line;
  final String message;
  @override
  String toString() => 'Line $line: $message';
}

class ParsedMenuItem {
  ParsedMenuItem({required this.category, required this.name, required this.firstLine});
  final String category;
  final String name;
  final int firstLine;
  int? price;
  String? taxProfileName;
  bool available = true;
  String? sku;
  final List<VariantInput> variants = [];
  final List<ModifierInput> modifiers = [];
  bool existing = false;
}

class MenuImportPreview {
  const MenuImportPreview({required this.items, required this.errors, required this.newCategories});
  final List<ParsedMenuItem> items;
  final List<MenuCsvRowError> errors;
  final List<String> newCategories;

  bool get canImport => errors.isEmpty && items.isNotEmpty;
  int get newItems => items.where((i) => !i.existing).length;
  int get updatedItems => items.where((i) => i.existing).length;
}

class MenuCsvService {
  MenuCsvService(this.ctx);
  final ServiceContext ctx;

  Future<Uint8List> export(Actor actor) async {
    actor.require(Permission.manageMenu);
    final menu = await MenuService(ctx).loadMenu();
    final money = await ctx.currency();
    final rows = <List<Object?>>[menuCsvHeader];
    for (final item in menu.items) {
      final mods = item.modifiers.map((m) => '${m.name}=${money.plain(m.price)}').join('; ');
      if (item.variants.isEmpty) {
        rows.add([
          item.categoryName,
          item.name,
          '',
          CsvNumber(money.plain(item.row.price)),
          item.taxProfileName ?? '',
          item.available ? 'yes' : 'no',
          mods,
          item.row.sku ?? '',
        ]);
      } else {
        for (var i = 0; i < item.variants.length; i++) {
          final v = item.variants[i];
          rows.add([
            item.categoryName,
            item.name,
            v.name,
            CsvNumber(money.plain(v.price)),
            item.taxProfileName ?? '',
            item.available ? 'yes' : 'no',
            i == 0 ? mods : '',
            i == 0 ? (item.row.sku ?? '') : '',
          ]);
        }
      }
    }
    return encodeCsvBytes(rows);
  }

  Future<MenuImportPreview> preview(Actor actor, Uint8List bytes) async {
    actor.require(Permission.manageMenu);
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const ValidationException('The file is not UTF-8 text. Save it as "CSV UTF-8" and try again.');
    }
    final rows = parseCsv(text);
    if (rows.isEmpty) throw const ValidationException('The file is empty');
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final missing = ['category', 'item', 'price'].where((h) => !header.contains(h)).toList();
    if (missing.isNotEmpty) {
      throw ValidationException('Missing column(s): ${missing.join(', ')}. Expected: ${menuCsvHeader.join(',')}');
    }
    int col(String name) => header.indexOf(name);
    String cell(List<String> row, String name) {
      final i = col(name);
      return (i < 0 || i >= row.length) ? '' : unguardCsvText(row[i].trim());
    }

    final money = await ctx.currency();
    final taxProfiles = await SettingsService(ctx).taxProfiles();
    final taxByName = {for (final t in taxProfiles) t.name.toLowerCase(): t};
    final menu = await MenuService(ctx).loadMenu(includeArchived: true);
    final existingCats = {for (final c in menu.categories) c.name.toLowerCase()};
    final existingItems = {
      for (final i in menu.items) '${i.categoryName.toLowerCase()}|${i.name.toLowerCase()}',
    };

    final errors = <MenuCsvRowError>[];
    final items = <String, ParsedMenuItem>{};
    final newCats = <String>{};
    for (var r = 1; r < rows.length; r++) {
      final line = r + 1;
      final row = rows[r];
      final category = cell(row, 'category');
      final name = cell(row, 'item');
      final variant = cell(row, 'variant');
      final priceText = cell(row, 'price');
      if (category.isEmpty) errors.add(MenuCsvRowError(line, 'category is empty'));
      if (name.isEmpty) errors.add(MenuCsvRowError(line, 'item is empty'));
      if (category.length > 40) errors.add(MenuCsvRowError(line, 'category is longer than 40 characters'));
      if (name.length > 80) errors.add(MenuCsvRowError(line, 'item name is longer than 80 characters'));
      int? price;
      try {
        price = money.parse(priceText);
      } on ValidationException catch (e) {
        errors.add(MenuCsvRowError(line, 'price: ${e.message}'));
      }
      if (category.isEmpty || name.isEmpty || price == null) continue;

      final key = '${category.toLowerCase()}|${name.toLowerCase()}';
      final item = items.putIfAbsent(key, () {
        final p = ParsedMenuItem(category: category, name: name, firstLine: line);
        p.existing = existingItems.contains(key);
        if (!existingCats.contains(category.toLowerCase())) newCats.add(category);
        return p;
      });

      final tax = cell(row, 'tax_profile');
      if (tax.isNotEmpty) {
        if (!taxByName.containsKey(tax.toLowerCase())) {
          errors.add(MenuCsvRowError(line, 'unknown tax profile "$tax". Create it in Settings → Taxes first.'));
        } else if (item.taxProfileName != null && item.taxProfileName!.toLowerCase() != tax.toLowerCase()) {
          errors.add(MenuCsvRowError(line, 'rows for "$name" use different tax profiles'));
        } else {
          item.taxProfileName = taxByName[tax.toLowerCase()]!.name;
        }
      }
      final avail = cell(row, 'available').toLowerCase();
      if (avail.isNotEmpty) {
        if (['yes', 'y', 'true', '1'].contains(avail)) {
          // available
        } else if (['no', 'n', 'false', '0', 'sold out'].contains(avail)) {
          item.available = false;
        } else {
          errors.add(MenuCsvRowError(line, 'available must be yes or no'));
        }
      }
      final sku = cell(row, 'sku');
      if (sku.isNotEmpty) item.sku ??= sku;

      if (variant.isEmpty) {
        if (item.price != null || item.variants.isNotEmpty) {
          errors.add(MenuCsvRowError(line, '"$name" appears more than once without a variant name'));
        }
        item.price = price;
      } else {
        if (item.price != null) {
          errors.add(MenuCsvRowError(line, '"$name" mixes a no-variant row with variant rows'));
        }
        if (item.variants.any((v) => v.name.toLowerCase() == variant.toLowerCase())) {
          errors.add(MenuCsvRowError(line, 'variant "$variant" of "$name" is listed twice'));
        } else if (variant.length > 40) {
          errors.add(MenuCsvRowError(line, 'variant name is longer than 40 characters'));
        } else {
          item.variants.add(VariantInput(name: variant, price: price));
        }
      }

      final mods = cell(row, 'modifiers');
      if (mods.isNotEmpty) {
        for (final part in mods.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty)) {
          final eq = part.lastIndexOf('=');
          if (eq <= 0) {
            errors.add(MenuCsvRowError(line, 'modifier "$part" must look like Name=price'));
            continue;
          }
          final mName = part.substring(0, eq).trim();
          try {
            final mPrice = money.parse(part.substring(eq + 1));
            if (item.modifiers.any((m) => m.name.toLowerCase() == mName.toLowerCase())) continue;
            item.modifiers.add(ModifierInput(name: mName, price: mPrice));
          } on ValidationException catch (e) {
            errors.add(MenuCsvRowError(line, 'modifier "$mName": ${e.message}'));
          }
        }
      }
    }
    if (rows.length == 1) errors.add(const MenuCsvRowError(1, 'no menu rows below the header'));
    return MenuImportPreview(items: items.values.toList(), errors: errors, newCategories: newCats.toList());
  }

  /// Applies a validated preview in one transaction.
  Future<int> apply(Actor actor, MenuImportPreview preview) async {
    actor.require(Permission.manageMenu);
    if (!preview.canImport) throw const ValidationException('Fix the errors before importing');
    final menuService = MenuService(ctx);
    final taxProfiles = await SettingsService(ctx).taxProfiles();
    final taxByName = {for (final t in taxProfiles) t.name.toLowerCase(): t.id};
    var count = 0;
    await ctx.db.transaction(() async {
      final menu = await menuService.loadMenu(includeArchived: true);
      final catIds = {for (final c in menu.categories) c.name.toLowerCase(): c.id};
      for (final p in preview.items) {
        final catId = catIds[p.category.toLowerCase()] ??= await menuService.createCategory(actor, p.category);
        final existing = menu.items
            .where((i) => i.row.categoryId == catId && i.name.toLowerCase() == p.name.toLowerCase())
            .firstOrNull;
        // Keep existing variant/modifier ids so history stays linked.
        final variants = [
          for (final v in p.variants)
            VariantInput(
              id: existing?.variants.where((x) => x.name.toLowerCase() == v.name.toLowerCase()).firstOrNull?.id,
              name: v.name,
              price: v.price,
            ),
          // Import never removes variants that the file does not mention.
          if (existing != null)
            for (final old in existing.variants)
              if (!p.variants.any((v) => v.name.toLowerCase() == old.name.toLowerCase()))
                VariantInput(id: old.id, name: old.name, price: old.price),
        ];
        final modifiers = [
          for (final m in p.modifiers)
            ModifierInput(
              id: existing?.modifiers.where((x) => x.name.toLowerCase() == m.name.toLowerCase()).firstOrNull?.id,
              name: m.name,
              price: m.price,
            ),
          if (existing != null)
            for (final old in existing.modifiers)
              if (!p.modifiers.any((m) => m.name.toLowerCase() == old.name.toLowerCase()))
                ModifierInput(id: old.id, name: old.name, price: old.price),
        ];
        await menuService.saveItem(
          actor,
          ItemInput(
            id: existing?.id,
            categoryId: catId,
            name: p.name,
            price: p.price ?? (p.variants.isEmpty ? 0 : p.variants.first.price),
            taxProfileId: p.taxProfileName == null
                ? existing?.row.taxProfileId
                : taxByName[p.taxProfileName!.toLowerCase()],
            available: p.available,
            sku: p.sku ?? existing?.row.sku,
            variants: variants,
            modifiers: modifiers,
          ),
        );
        count++;
      }
      await ctx.audit(actor, 'menu.csv_imported', details: {'items': count, 'newCategories': preview.newCategories});
    });
    return count;
  }
}
