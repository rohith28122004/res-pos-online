import 'dart:convert';
import 'dart:typed_data';

import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/features/menu/application/menu_csv.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  late MenuCsvService csv;

  setUp(() async {
    h = await Harness.create();
    await h.taxProfile('GST 5%', TaxMode.exclusive);
    csv = MenuCsvService(h.ctx);
  });
  tearDown(() => h.dispose());

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  test('preview reports actionable row errors and imports nothing', () async {
    final p = await csv.preview(
      h.owner,
      bytes(
        'category,item,variant,price,tax_profile,available\n'
        'Coffee,Latte,Small,120.00,GST 5%,yes\n'
        'Coffee,Latte,Small,130,GST 5%,yes\n'
        ',Nameless,,10,,\n'
        'Coffee,Mocha,,12.345,,\n'
        'Tea,Masala chai,,30,Unknown tax,maybe\n',
      ),
    );
    expect(p.canImport, isFalse);
    final messages = p.errors.map((e) => e.toString()).join('\n');
    expect(messages, contains('Line 3: variant "Small" of "Latte" is listed twice'));
    expect(messages, contains('Line 4: category is empty'));
    expect(messages, contains('Line 5: price'));
    expect(messages, contains('Line 6: unknown tax profile "Unknown tax"'));
    expect(messages, contains('Line 6: available must be yes or no'));
    expect(await h.count(h.db.menuItems), 0);
  });

  test('valid file imports categories, items, variants, modifiers; re-import updates', () async {
    const file =
        'category,item,variant,price,tax_profile,available,modifiers,sku\n'
        'Coffee,Cappuccino,Small,120.00,GST 5%,yes,"Extra shot=30; Oat milk=40",CAP\n'
        'Coffee,Cappuccino,Large,160,GST 5%,yes,,\n'
        'Bakery,Croissant,,90,,no,,\n';
    final p = await csv.preview(h.owner, bytes(file));
    expect(p.errors, isEmpty);
    expect(p.newItems, 2);
    expect(p.newCategories.toSet(), {'Coffee', 'Bakery'});
    expect(await csv.apply(h.owner, p), 2);
    var menu = await h.menu.loadMenu();
    final capp = menu.items.firstWhere((i) => i.name == 'Cappuccino');
    expect(capp.variants.map((v) => (v.name, v.price)), [('Small', 12000), ('Large', 16000)]);
    expect(capp.modifiers.map((m) => (m.name, m.price)), [('Extra shot', 3000), ('Oat milk', 4000)]);
    expect(capp.taxProfileName, 'GST 5%');
    expect(menu.items.firstWhere((i) => i.name == 'Croissant').available, isFalse);

    final again = await csv.preview(h.owner, bytes('category,item,variant,price\nCoffee,Cappuccino,Small,125\n'));
    expect(again.updatedItems, 1);
    await csv.apply(h.owner, again);
    menu = await h.menu.loadMenu();
    final updated = menu.items.firstWhere((i) => i.name == 'Cappuccino');
    expect(updated.variants.firstWhere((v) => v.name == 'Small').price, 12500);
    expect(updated.variants.length, 2, reason: 'import never removes variants');
    expect(updated.modifiers.length, 2);
  });

  test('export → import round trip is stable', () async {
    final p = await csv.preview(
      h.owner,
      bytes('category,item,variant,price\nTea,Masala chai,,30\nTea,Green tea,Pot,80\n'),
    );
    await csv.apply(h.owner, p);
    final exported = await csv.export(h.owner);
    final again = await csv.preview(h.owner, exported);
    expect(again.errors, isEmpty);
    expect(again.newItems, 0);
    expect(again.updatedItems, 2);
  });

  test('cashiers cannot import menus', () async {
    await expectLater(csv.preview(h.cashier, bytes('category,item,price\nA,B,1\n')), throwsA(anything));
  });
}
