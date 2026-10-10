import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/auth/application/auth_service.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/setup/application/demo_seed.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  test('demo seed builds a complete, clearly marked demo installation', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemoryDatabase();
    final ctx = ServiceContext(db: db, clock: FixedClock(DateTime.utc(2026, 10, 5, 4)));
    await DemoSeeder(ctx, hasher: fastHasher).seed();
    final inst = await db.select(db.installation).getSingle();
    expect(inst.isDemo, isTrue);
    expect(inst.receiptPrefix, 'DEMO');
    expect((await db.select(db.staff).get()).length, 3);
    // The demo sign-ins shown on the demo lock screen work, with no forced change.
    final auth = AuthService(ctx, hasher: fastHasher);
    for (final role in StaffRole.values) {
      final actor = await auth.login(DemoLogins.emailFor(role), DemoLogins.password);
      expect(actor.role, role);
      expect(actor.mustChangePassword, isFalse);
    }
    final menu = await MenuService(ctx).loadMenu();
    expect(menu.categories.length, 5);
    expect(menu.items.length, greaterThan(10));
    expect(menu.items.any((i) => i.variants.isNotEmpty && i.modifiers.isNotEmpty), isTrue);
    expect((await db.select(db.diningTables).get()).length, 8);
    expect(await db.select(db.bills).get(), isEmpty, reason: 'no fake sales in reports');
    await db.close();
  });

  test('a demo seeded before email sign-in gets its demo logins back', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemoryDatabase();
    final ctx = ServiceContext(db: db, clock: FixedClock(DateTime.utc(2026, 10, 5, 4)));
    final seeder = DemoSeeder(ctx, hasher: fastHasher);
    await seeder.seed();
    // Make it look like a schema-2 demo: PIN-only staff.
    await db.update(db.staff).write(const StaffCompanion(email: Value(null), passwordHash: Value(null)));
    await seeder.upgradeLogins();
    await seeder.upgradeLogins(); // idempotent
    final auth = AuthService(ctx, hasher: fastHasher);
    for (final role in StaffRole.values) {
      expect((await auth.login(DemoLogins.emailFor(role), DemoLogins.password)).role, role);
    }
    await db.close();
  });
}
