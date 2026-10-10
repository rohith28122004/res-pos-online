import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/pricing/tax.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../auth/application/auth_service.dart';
import '../../menu/application/menu_service.dart';
import '../../settings/application/settings_service.dart';
import '../../tables/application/table_service.dart';
import 'setup_service.dart';

/// Demo-only sign-ins. They exist only inside the separate demo database and
/// are shown on the demo lock screen; production installs have no default
/// accounts.
abstract final class DemoLogins {
  static const ownerEmail = 'owner@demo.test';
  static const cashierEmail = 'cashier@demo.test';
  static const kitchenEmail = 'kitchen@demo.test';
  static const password = 'demo1234';

  static String emailFor(StaffRole role) => switch (role) {
    StaffRole.owner => ownerEmail,
    StaffRole.cashier => cashierEmail,
    StaffRole.kitchen => kitchenEmail,
  };
}

/// Seeds the separate demo database (cafedesk_demo.sqlite) with a sample café.
class DemoSeeder {
  DemoSeeder(this.ctx, {this.hasher = const PasswordHasher()});
  final ServiceContext ctx;
  final PasswordHasher hasher;

  Future<void> seed() async {
    final setup = await SetupService(ctx, hasher: hasher).completeSetup(
      const SetupInput(
        restaurantName: 'Demo Café',
        address: '12 Sample Street\nChennai',
        ownerName: 'Demo Owner',
        ownerEmail: DemoLogins.ownerEmail,
        ownerPassword: DemoLogins.password,
        receiptFooter: 'DEMO — not a real bill',
      ),
      isDemo: true,
    );
    final owner = setup.owner;
    final auth = AuthService(ctx, hasher: hasher);
    for (final (name, role) in [('Demo Cashier', StaffRole.cashier), ('Demo Kitchen', StaffRole.kitchen)]) {
      await auth.createStaff(
        owner,
        name: name,
        role: role,
        email: DemoLogins.emailFor(role),
        password: DemoLogins.password,
        mustChangePassword: false,
      );
    }

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

  /// Demo databases seeded before email sign-in (schema 2) have PIN-only
  /// staff. Gives each demo account without a password its demo email and
  /// password so the credentials on the demo lock screen work. Demo only.
  Future<void> upgradeLogins() async {
    final db = ctx.db;
    final rows = await (db.select(db.staff)..where((s) => s.passwordHash.isNull())).get();
    final used = <String>{};
    for (final row in rows) {
      final email = DemoLogins.emailFor(StaffRole.parse(row.role));
      if (!used.add(email)) continue;
      final taken = await (db.select(db.staff)..where((s) => s.email.equals(email))).getSingleOrNull();
      if (taken != null) continue;
      await (db.update(db.staff)..where((s) => s.id.equals(row.id))).write(
        StaffCompanion(
          email: Value(email),
          passwordHash: Value(await hasher.hash(DemoLogins.password)),
          pinHash: const Value(''),
        ),
      );
    }
  }
}
