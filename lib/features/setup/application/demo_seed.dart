import '../../../core/pricing/tax.dart';
import '../../../core/security/permissions.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/service_context.dart';
import '../../auth/application/auth_service.dart';
import '../../menu/application/menu_service.dart';
import '../../settings/application/settings_service.dart';
import '../../tables/application/table_service.dart';
import 'setup_service.dart';

/// Demo-only PINs. They exist only inside the separate demo database and are
/// shown on the demo lock screen; production installs have no default PINs.
abstract final class DemoPins {
  static const owner = '2580';
  static const cashier = '1357';
  static const kitchen = '9024';
}

/// Seeds the separate demo database (cafedesk_demo.sqlite) with a sample café.
class DemoSeeder {
  DemoSeeder(this.ctx, {this.hasher = const PinHasher()});
  final ServiceContext ctx;
  final PinHasher hasher;

  Future<void> seed() async {
    final setup = await SetupService(ctx, hasher: hasher).completeSetup(
      const SetupInput(
        restaurantName: 'Demo Café',
        address: '12 Sample Street\nChennai',
        ownerName: 'Demo Owner',
        ownerPin: DemoPins.owner,
        receiptFooter: 'DEMO — not a real bill',
      ),
      isDemo: true,
    );
    final owner = setup.owner;
    final auth = AuthService(ctx, hasher: hasher);
    await auth.createStaff(owner, name: 'Demo Cashier', role: StaffRole.cashier, pin: DemoPins.cashier);
    await auth.createStaff(owner, name: 'Demo Kitchen', role: StaffRole.kitchen, pin: DemoPins.kitchen);

    final settings = SettingsService(ctx);
    final gst = await settings.createTaxProfile(
      owner,
      const TaxProfileInput(
        name: 'Sample 5% (demo)',
        mode: TaxMode.exclusive,
        rateBps: 500,
        components: [
          TaxComponentRate(name: 'CGST', rateBps: 250),
          TaxComponentRate(name: 'SGST', rateBps: 250),
        ],
      ),
    );

    final tables = TableService(ctx);
    for (var i = 1; i <= 8; i++) {
      await tables.createTable(owner, name: 'T$i', capacity: i <= 4 ? 2 : 4);
    }

    final menu = MenuService(ctx);
    Future<void> item(
      String cat,
      String name,
      int price, {
      List<VariantInput> variants = const [],
      List<ModifierInput> modifiers = const [],
      bool taxed = false,
    }) async {
      await menu.saveItem(
        owner,
        ItemInput(
          categoryId: cat,
          name: name,
          price: price,
          taxProfileId: taxed ? gst : null,
          variants: variants,
          modifiers: modifiers,
        ),
      );
    }

    final coffee = await menu.createCategory(owner, 'Coffee');
    final tea = await menu.createCategory(owner, 'Tea');
    final snacks = await menu.createCategory(owner, 'Snacks');
    final bakery = await menu.createCategory(owner, 'Bakery');
    final cold = await menu.createCategory(owner, 'Cold drinks');
    const milk = [ModifierInput(name: 'Oat milk', price: 4000), ModifierInput(name: 'Extra shot', price: 3000)];
    await item(coffee, 'Filter coffee', 4000);
    await item(
      coffee,
      'Cappuccino',
      0,
      variants: const [
        VariantInput(name: 'Regular', price: 14000),
        VariantInput(name: 'Large', price: 18000),
      ],
      modifiers: milk,
      taxed: true,
    );
    await item(
      coffee,
      'Café latte',
      0,
      variants: const [
        VariantInput(name: 'Regular', price: 15000),
        VariantInput(name: 'Large', price: 19000),
      ],
      modifiers: milk,
      taxed: true,
    );
    await item(coffee, 'Americano', 12000, taxed: true);
    await item(tea, 'Masala chai', 3000);
    await item(tea, 'Ginger lemon tea', 6000, modifiers: const [ModifierInput(name: 'Honey', price: 1500)]);
    await item(tea, 'Green tea pot', 9000);
    await item(snacks, 'Veg puff', 3500);
    await item(
      snacks,
      'Paneer tikka sandwich',
      16000,
      modifiers: const [
        ModifierInput(name: 'Extra cheese', price: 3000),
        ModifierInput(name: 'No onion', price: 0),
      ],
      taxed: true,
    );
    await item(snacks, 'Masala fries', 11000, taxed: true);
    await item(bakery, 'Butter croissant', 9000);
    await item(bakery, 'Chocolate brownie', 8500);
    await item(bakery, 'Banana walnut cake slice', 7500);
    await item(
      cold,
      'Cold coffee',
      0,
      variants: const [
        VariantInput(name: 'Regular', price: 13000),
        VariantInput(name: 'Large', price: 16000),
      ],
      taxed: true,
    );
    await item(
      cold,
      'Fresh lime soda',
      7000,
      variants: const [
        VariantInput(name: 'Sweet', price: 7000),
        VariantInput(name: 'Salted', price: 7000),
      ],
    );
  }
}
