import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/common.dart';
import '../application/menu_service.dart';

class MenuAdminScreen extends ConsumerStatefulWidget {
  const MenuAdminScreen({super.key});
  @override
  ConsumerState<MenuAdminScreen> createState() => _MenuAdminScreenState();
}

class _MenuAdminScreenState extends ConsumerState<MenuAdminScreen> {
  String? _category;
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return StreamView<MenuData>(
      key: ValueKey(_showArchived),
      stream: services.menu.watchMenu(includeArchived: _showArchived),
      builder: (context, menu) {
        final cats = menu.categories;
        if (_category != null && !cats.any((c) => c.id == _category)) _category = null;
        final items = menu.items.where((i) => _category == null || i.row.categoryId == _category).toList();
        return Scaffold(
          floatingActionButton: cats.isEmpty
              ? null
              : FloatingActionButton.extended(
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                  onPressed: () => _editItem(context, menu, null),
                ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('Add category'),
                      onPressed: _addCategory,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Import CSV'),
                      onPressed: _import,
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Export CSV'),
                      onPressed: _export,
                    ),
                    FilterChip(
                      label: const Text('Show archived'),
                      selected: _showArchived,
                      onSelected: (v) => setState(() => _showArchived = v),
                    ),
                  ],
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
                    for (final c in cats)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InputChip(
                          label: Text(c.archived ? '${c.name} (archived)' : c.name),
                          selected: _category == c.id,
                          onSelected: (_) => setState(() => _category = c.id),
                          onDeleted: () => _categoryMenu(c),
                          deleteIcon: const Icon(Icons.more_vert, size: 18),
                          deleteButtonTooltipMessage: 'Category options',
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: cats.isEmpty
                    ? const EmptyState(
                        icon: Icons.restaurant_menu_outlined,
                        title: 'Start your menu',
                        message:
                            'Add a category (e.g. Coffee), then add items. Or import a CSV with columns: '
                            'category, item, variant, price, tax_profile, available, modifiers, sku.',
                      )
                    : items.isEmpty
                    ? const EmptyState(icon: Icons.restaurant_menu_outlined, title: 'No items in this category')
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return ListTile(
                            title: Text(
                              it.name,
                              style: it.row.archived ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                            ),
                            subtitle: Text(
                              [
                                it.categoryName,
                                if (it.variants.isEmpty)
                                  formatMoney(it.row.price)
                                else
                                  it.variants.map((v) => '${v.name} ${formatMoney(v.price)}').join(', '),
                                if (it.modifiers.isNotEmpty) '${it.modifiers.length} add-on(s)',
                                it.taxProfileName ?? 'No tax',
                              ].join(' · '),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: it.available
                                      ? 'Available — tap to mark sold out'
                                      : 'Sold out — tap to make available',
                                  child: Switch(
                                    value: it.available,
                                    onChanged: it.row.archived
                                        ? null
                                        : (v) => guard(context, () => services.menu.setItemAvailable(actor, it.id, v)),
                                  ),
                                ),
                                IconButton(
                                  tooltip: it.row.archived ? 'Restore' : 'Archive',
                                  icon: Icon(it.row.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
                                  onPressed: () => guard(
                                    context,
                                    () => services.menu.setItemArchived(actor, it.id, !it.row.archived),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () => _editItem(context, menu, it),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addCategory() async {
    final name = await askText(context, title: 'New category', label: 'Name', maxLength: 40);
    if (name == null || name.isEmpty || !mounted) return;
    final services = ref.read(servicesProvider);
    final id = await guard(context, () => services.menu.createCategory(requireActor(ref), name));
    if (id != null) setState(() => _category = id);
  }

  Future<void> _categoryMenu(CategoryRow c) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(s, 'rename'),
            ),
            ListTile(
              leading: Icon(c.archived ? Icons.unarchive_outlined : Icons.archive_outlined),
              title: Text(c.archived ? 'Restore category' : 'Archive category'),
              subtitle: const Text('Archived categories and their items are hidden from billing; history is kept.'),
              onTap: () => Navigator.pop(s, 'archive'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = await askText(context, title: 'Rename category', initial: c.name, maxLength: 40);
      if (name != null && name.isNotEmpty && mounted) {
        await guard(context, () => services.menu.renameCategory(actor, c.id, name));
      }
    } else if (action == 'archive') {
      await guard(context, () => services.menu.setCategoryArchived(actor, c.id, !c.archived));
    }
  }

  Future<void> _editItem(BuildContext context, MenuData menu, MenuItemView? item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ItemEditorScreen(menu: menu, item: item, defaultCategory: _category),
      ),
    );
  }

  Future<void> _export() async {
    final services = ref.read(servicesProvider);
    final bytes = await guard(context, () => services.menuCsv.export(requireActor(ref)));
    if (bytes == null || !mounted) return;
    await guard(
      context,
      () => FilePicker.saveFile(fileName: 'cafedesk_menu.csv', bytes: bytes, mimeType: 'text/csv'),
      success: 'Menu exported',
    );
  }

  Future<void> _import() async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']);
    if (file == null || !mounted) return;
    final preview = await guard(context, () async => services.menuCsv.preview(actor, await file.readAsBytes()));
    if (preview == null || !mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(preview.canImport ? 'Import ${preview.items.length} item(s)?' : 'Fix these problems first'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (preview.canImport) ...[
                  Text('${preview.newItems} new · ${preview.updatedItems} updated'),
                  if (preview.newCategories.isNotEmpty) Text('New categories: ${preview.newCategories.join(', ')}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Import adds and updates items. It never deletes or archives anything. '
                    'Price changes apply to new order lines only.',
                  ),
                  const Divider(),
                  for (final i in preview.items.take(50))
                    Text(
                      '${i.existing ? 'Update' : 'New'}: ${i.category} › ${i.name}'
                      '${i.variants.isEmpty ? ' ${money.format(i.price ?? 0)}' : ' (${i.variants.map((v) => '${v.name} ${money.format(v.price)}').join(', ')})'}',
                    ),
                  if (preview.items.length > 50) Text('…and ${preview.items.length - 50} more'),
                ] else
                  for (final e in preview.errors.take(100))
                    Text(e.toString(), style: const TextStyle(color: AppColors.danger)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          if (preview.canImport) FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Import')),
        ],
      ),
    );
    if (go == true && mounted) {
      await guard(context, () => services.menuCsv.apply(actor, preview), success: 'Menu imported');
    }
  }
}

class _Row {
  _Row({this.id, String name = '', String price = ''})
    : name = TextEditingController(text: name),
      price = TextEditingController(text: price);
  final String? id;
  final TextEditingController name;
  final TextEditingController price;
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class ItemEditorScreen extends ConsumerStatefulWidget {
  const ItemEditorScreen({super.key, required this.menu, this.item, this.defaultCategory});
  final MenuData menu;
  final MenuItemView? item;
  final String? defaultCategory;
  @override
  ConsumerState<ItemEditorScreen> createState() => _ItemEditorScreenState();
}

class _ItemEditorScreenState extends ConsumerState<ItemEditorScreen> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _price = TextEditingController(text: widget.item == null ? '' : money.plain(widget.item!.row.price));
  late final _sku = TextEditingController(text: widget.item?.row.sku ?? '');
  late String _categoryId = widget.item?.row.categoryId ?? widget.defaultCategory ?? widget.menu.categories.first.id;
  late String? _taxProfileId = widget.item?.row.taxProfileId;
  late bool _available = widget.item?.available ?? true;
  late final List<_Row> _variants = [
    for (final v in widget.item?.variants ?? const <MenuVariant>[])
      _Row(id: v.id, name: v.name, price: money.plain(v.price)),
  ];
  late final List<_Row> _mods = [
    for (final m in widget.item?.modifiers ?? const <MenuModifier>[])
      _Row(id: m.id, name: m.name, price: money.plain(m.price)),
  ];

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _sku.dispose();
    for (final r in [..._variants, ..._mods]) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final services = ref.read(servicesProvider);
    final id = await guard(context, () async {
      int parse(String s, String what) {
        final v = tryParseMoney(s);
        if (v == null) throw ValidationException('Enter a valid price for $what');
        return v;
      }

      return services.menu.saveItem(
        requireActor(ref),
        ItemInput(
          id: widget.item?.id,
          categoryId: _categoryId,
          name: _name.text,
          price: _variants.isEmpty ? parse(_price.text, _name.text.isEmpty ? 'the item' : _name.text) : 0,
          taxProfileId: _taxProfileId,
          available: _available,
          sku: _sku.text,
          variants: [
            for (final v in _variants)
              VariantInput(id: v.id, name: v.name.text, price: parse(v.price.text, v.name.text)),
          ],
          modifiers: [
            for (final m in _mods)
              ModifierInput(
                id: m.id,
                name: m.name.text,
                price: m.price.text.trim().isEmpty ? 0 : parse(m.price.text, m.name.text),
              ),
          ],
        ),
      );
    }, success: 'Saved. New prices apply to items added from now on.');
    if (id != null && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item == null ? 'New item' : 'Edit ${widget.item!.name}'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Item name'),
                maxLength: 80,
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _categoryId,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [for (final c in widget.menu.categories) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
              ),
              const SizedBox(height: 12),
              StreamView<List<TaxProfileRow>>(
                stream: services.settings.watchTaxProfiles(),
                builder: (context, profiles) => DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue: profiles.any((p) => p.id == _taxProfileId) ? _taxProfileId : null,
                  decoration: const InputDecoration(
                    labelText: 'Tax',
                    helperText: 'Create tax profiles in Settings → Taxes',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('No tax')),
                    for (final p in profiles) DropdownMenuItem<String?>(value: p.id, child: Text(p.name)),
                  ],
                  onChanged: (v) => setState(() => _taxProfileId = v),
                ),
              ),
              const SizedBox(height: 12),
              if (_variants.isEmpty) MoneyField(controller: _price, label: 'Price'),
              const SizedBox(height: 12),
              TextField(
                controller: _sku,
                decoration: const InputDecoration(labelText: 'Short code (optional, searchable)'),
                maxLength: 40,
              ),
              SwitchListTile(
                value: _available,
                onChanged: (v) => setState(() => _available = v),
                title: const Text('Available (not sold out)'),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text('Sizes / variants', style: t.titleMedium)),
                  TextButton.icon(
                    onPressed: () => setState(() => _variants.add(_Row())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              const Text('With variants, staff must pick one (e.g. Regular / Large), and each has its own price.'),
              for (final v in _variants) _rowEditor(v, _variants, 'Variant'),
              const Divider(),
              Row(
                children: [
                  Expanded(child: Text('Add-ons (modifiers)', style: t.titleMedium)),
                  TextButton.icon(
                    onPressed: () => setState(() => _mods.add(_Row())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
                ],
              ),
              for (final m in _mods) _rowEditor(m, _mods, 'Add-on'),
              const SizedBox(height: 24),
              FilledButton(onPressed: _save, child: const Text('Save item')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rowEditor(_Row r, List<_Row> list, String label) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: r.name,
            decoration: InputDecoration(labelText: '$label name'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: MoneyField(controller: r.price, label: 'Price'),
        ),
        IconButton(
          tooltip: 'Remove',
          icon: const Icon(Icons.delete_outline),
          onPressed: () => setState(() {
            list.remove(r);
            r.dispose();
          }),
        ),
      ],
    ),
  );
}
