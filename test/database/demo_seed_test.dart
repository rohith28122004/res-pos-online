import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/time/business_time.dart';
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
    final menu = await MenuService(ctx).loadMenu();
    expect(menu.categories.length, 5);
    expect(menu.items.length, greaterThan(10));
    expect(menu.items.any((i) => i.variants.isNotEmpty && i.modifiers.isNotEmpty), isTrue);
    expect((await db.select(db.diningTables).get()).length, 8);
    expect(await db.select(db.bills).get(), isEmpty, reason: 'no fake sales in reports');
    await db.close();
  });
}
