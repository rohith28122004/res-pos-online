@Tags(['screenshots'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cafedesk/app/device_runtime.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/app/shell.dart';
import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/theme.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/sync/client_database.dart';
import 'package:cafedesk/core/sync/device_sync.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/devices/presentation/device_providers.dart';
import 'package:cafedesk/features/kitchen/presentation/kitchen_board_screen.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:cafedesk/features/waiter/presentation/order_builder.dart';
import 'package:cafedesk/features/waiter/presentation/waiter_home.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

/// Renders the waiter and kitchen screens with real fonts on sample café data
/// and saves PNGs to `build/screenshots/` — to show the app without a phone,
/// and for docs. Opt-in (writes files):
///
///   flutter test --dart-define=CAFEDESK_SCREENSHOTS=true test/screenshots
const _enabled = bool.fromEnvironment('CAFEDESK_SCREENSHOTS');

void main() {
  final now = DateTime.now().millisecondsSinceEpoch;
  int minutesAgo(int m) => now - m * 60000;

  setUpAll(() async {
    if (!_enabled) return;
    // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final fonts = p.join(artifacts.path, 'material_fonts');
    Future<void> load(String family, List<String> files) async {
      final loader = FontLoader(family);
      for (final f in files) {
        final bytes = File(p.join(fonts, f)).readAsBytesSync();
        loader.addFont(Future.value(ByteData.view(bytes.buffer)));
      }
      await loader.load();
    }

    await load('Roboto', [
      'roboto-regular.ttf',
      'roboto-medium.ttf',
      'roboto-bold.ttf',
      'roboto-italic.ttf',
      'roboto-light.ttf',
      'roboto-black.ttf',
    ]);
    await load('MaterialIcons', ['materialicons-regular.otf']);
  });

  Map<String, Object?> line(
    String id,
    String item,
    int qty,
    int price, {
    String? variant,
    List<String> mods = const [],
  }) => {
    'lineId': id,
    'itemId': id,
    'itemName': item,
    'variantName': variant,
    'modifiers': mods,
    'note': null,
    'quantity': qty,
    'sentQuantity': qty,
    'unitPrice': price,
    'revision': 1,
    'createdBy': 's1',
    'createdByName': 'Wendy',
  };

  Map<String, Object?> order(String id, int no, String? table, String by, List<Map<String, Object?>> lines, int age) =>
      {
        'orderId': id,
        'orderNo': no,
        'orderRef': table == null ? 'Takeaway · #$no' : '$table · #$no',
        'orderType': table == null ? 'takeaway' : 'dine_in',
        'tableId': table == null ? null : 't${table.substring(1)}',
        'tableLabel': table,
        'status': 'open',
        'revision': 2,
        'createdBy': by == 'Wendy' ? 's1' : 's2',
        'createdByName': by,
        'createdAt': minutesAgo(age),
        'guestCount': 2,
        'note': null,
        'estimatedTotal': lines.fold<int>(0, (a, l) => a + (l['unitPrice']! as int) * (l['quantity']! as int)),
        'lines': lines,
      };

  Map<String, Object?> ticket(
    String id,
    int no,
    String ref,
    String? table,
    String status,
    int age,
    List<Map<String, Object?>> lines, {
    String kind = 'order',
    String? reason,
    String by = 'Wendy',
  }) => {
    'ticketId': id,
    'ticketNo': no,
    'orderId': 'o-$ref',
    'orderRef': ref,
    'tableLabel': table,
    'kind': kind,
    'reason': reason,
    'status': status,
    'revision': 1,
    'createdBy': 's1',
    'createdByName': by,
    'createdAt': minutesAgo(age),
    'lines': lines,
  };

  Map<String, Object?> kot(String item, int qty, {String? variant, String? mods, String? note}) => {
    'itemName': item,
    'variantName': variant,
    'modifiersText': mods,
    'note': note,
    'quantityDelta': qty,
  };

  Future<(ClientDatabase, DeviceSync)> cafe({required String role, bool kitchenEnabled = true}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemoryClientDatabase();
    final sync = DeviceSync(db: db, secrets: MemorySecretStore(), clock: const SystemClock());
    await db
        .into(db.clientLink)
        .insert(
          ClientLinkCompanion.insert(
            singleton: const Value(1),
            deviceId: 'dev-1',
            role: role,
            deviceName: role == 'kitchen' ? 'Kitchen tablet' : "Wendy's phone",
            restaurantId: 'r1',
            restaurantName: 'Green Leaf Café',
            hostDeviceId: 'h1',
            hostEpoch: 1,
            hostAddressesJson: '["192.168.1.10"]',
            hostPort: 47821,
            certSha256: '0' * 64,
            signingPublicKey: 'x',
            sealPublicKey: 'y',
            pairedAt: minutesAgo(600),
            cursorEpoch: const Value(1),
            cursorSequence: const Value(120),
            lastLiveAt: Value(now),
          ),
        );
    await db
        .into(db.clientSessions)
        .insert(
          ClientSessionsCompanion.insert(
            singleton: const Value(1),
            staffId: 's1',
            name: role == 'kitchen' ? 'Ken' : 'Wendy',
            role: role,
            expiresAt: now + 3600000,
          ),
        );
    Future<void> put(String key, String kind, Object value) => db
        .into(db.cacheEntries)
        .insert(CacheEntriesCompanion.insert(key: key, kind: kind, json: jsonEncode(value), updatedAt: now));
    Map<String, Object?> item(String id, String cat, String name, int price, {bool available = true}) => {
      'itemId': id,
      'categoryId': cat,
      'name': name,
      'price': price,
      'available': available,
      'variants': const [],
      'modifiers': const [],
    };
    await put('meta', 'meta', {'restaurantName': 'Green Leaf Café', 'hostEpoch': 1, 'kitchenEnabled': kitchenEnabled});
    await put('menu', 'menu', {
      'categories': [
        {'categoryId': 'coffee', 'name': 'Coffee'},
        {'categoryId': 'tea', 'name': 'Tea'},
        {'categoryId': 'snacks', 'name': 'Snacks'},
        {'categoryId': 'desserts', 'name': 'Desserts'},
      ],
      'items': [
        item('filter', 'coffee', 'Filter coffee', 4000),
        {
          ...item('capp', 'coffee', 'Cappuccino', 0),
          'variants': [
            {'variantId': 'reg', 'name': 'Regular', 'price': 12000},
            {'variantId': 'lg', 'name': 'Large', 'price': 15000},
          ],
          'modifiers': [
            {'modifierId': 'shot', 'name': 'Extra shot', 'price': 3000},
            {'modifierId': 'oat', 'name': 'Oat milk', 'price': 4000},
          ],
        },
        item('cold', 'coffee', 'Cold coffee', 13000),
        item('chai', 'tea', 'Masala chai', 3000),
        item('green', 'tea', 'Green tea', 6000),
        item('sandwich', 'snacks', 'Veg sandwich', 11000),
        item('puff', 'snacks', 'Paneer puff', 4500),
        item('samosa', 'snacks', 'Samosa (2 pcs)', 4000),
        item('brownie', 'desserts', 'Brownie', 9000, available: false),
      ],
    });
    await put('tables', 'tables', [
      for (var i = 1; i <= 8; i++) {'tableId': 't$i', 'name': 'T$i', 'capacity': i.isEven ? 4 : 2},
    ]);
    final orders = [
      order('o12', 12, 'T1', 'Wendy', [
        line('l1', 'Cappuccino', 2, 15000, variant: 'Large'),
        line('l2', 'Veg sandwich', 1, 11000),
      ], 18),
      order('o13', 13, null, 'Wendy', [line('l3', 'Cold coffee', 1, 13000)], 12),
      order('o14', 14, 'T4', 'Raj', [line('l4', 'Masala chai', 3, 3000), line('l5', 'Samosa (2 pcs)', 2, 4000)], 9),
      order('o15', 15, 'T6', 'Wendy', [line('l6', 'Filter coffee', 2, 4000)], 3),
    ];
    for (final o in orders) {
      await put('order:${o['orderId']}', 'order', o);
    }
    final tickets = [
      ticket('k31', 31, 'T1 · #12', 'T1', 'ready', 17, [
        kot('Cappuccino', 2, variant: 'Large', mods: 'Extra shot'),
        kot('Veg sandwich', 1, note: 'No onion'),
      ]),
      ticket('k32', 32, 'Takeaway · #13', null, 'preparing', 11, [kot('Cold coffee', 1, note: 'Less sugar')]),
      ticket('k33', 33, 'T4 · #14', 'T4', 'preparing', 8, [
        kot('Masala chai', 3),
        kot('Samosa (2 pcs)', 2),
      ], by: 'Raj'),
      ticket('k34', 34, 'T6 · #15', 'T6', 'pending', 2, [kot('Filter coffee', 2, note: 'One without sugar')]),
      ticket(
        'k35',
        35,
        'T4 · #14',
        'T4',
        'pending',
        1,
        [kot('Masala chai', -1)],
        kind: 'correction',
        reason: 'Guest cancelled one',
        by: 'Raj',
      ),
    ];
    for (final t in tickets) {
      await put('ticket:${t['ticketId']}', 'ticket', t);
    }
    if (role == 'waiter') {
      // An order being put together for T2.
      await db
          .into(db.drafts)
          .insert(
            DraftsCompanion.insert(
              id: 'd1',
              staffId: 's1',
              orderType: 'dine_in',
              tableId: const Value('t2'),
              tableLabel: const Value('T2'),
              linesJson: jsonEncode([
                {
                  'key': 'a',
                  'itemId': 'capp',
                  'itemName': 'Cappuccino',
                  'variantId': 'lg',
                  'variantName': 'Large',
                  'modifierIds': ['shot'],
                  'modifierNames': ['Extra shot'],
                  'quantity': 2,
                  'note': null,
                  'unitPrice': 18000,
                },
                {
                  'key': 'b',
                  'itemId': 'sandwich',
                  'itemName': 'Veg sandwich',
                  'modifierIds': <String>[],
                  'modifierNames': <String>[],
                  'quantity': 1,
                  'note': 'No onion',
                  'unitPrice': 11000,
                },
              ]),
              createdAt: minutesAgo(1),
              updatedAt: minutesAgo(1),
            ),
          );
      Future<void> sent(String id, String summary, String state, int age, {Map<String, Object?>? result}) => db
          .into(db.pendingCommands)
          .insert(
            PendingCommandsCompanion.insert(
              commandId: id,
              staffId: 's1',
              action: CommandAction.orderPlace,
              bodyJson: jsonEncode({
                'payload': {'lines': []},
              }),
              summary: summary,
              state: state,
              createdAt: minutesAgo(age),
              updatedAt: minutesAgo(age),
              lastRoute: const Value('lan'),
              resultJson: Value(result == null ? null : jsonEncode(result)),
            ),
          );
      Map<String, Object?> accepted(String id, String ref, int ticketNo) => {
        'commandId': id,
        'state': 'accepted',
        'hostEpoch': 1,
        'resultId': id,
        'result': {'orderRef': ref, 'ticketNo': ticketNo},
      };
      await sent('c1', 'T1: 3 items', CommandState.accepted, 18, result: accepted('c1', 'T1 · #12', 31));
      await sent('c2', 'Takeaway: 1 item', CommandState.accepted, 12, result: accepted('c2', 'Takeaway · #13', 32));
      await sent('c3', 'T6: 2 items', CommandState.accepted, 3, result: accepted('c3', 'T6 · #15', 34));
    }
    return (db, sync);
  }

  /// Draws [screen] with real shadows and saves it as build/screenshots/[name].png.
  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget screen,
    ProviderContainer container, {
    required Size size,
    required double ratio,
    Future<void> Function()? before,
  }) async {
    // flutter_test draws shadows as solid outlines by default; show real ones.
    debugDisableShadows = false;
    tester.view.physicalSize = size * ratio;
    tester.view.devicePixelRatio = ratio;
    final boundary = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: boundary,
          child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: screen),
        ),
      ),
    );
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    if (before != null) {
      await before();
      await settle();
    }
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final png = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File(p.join('build', 'screenshots', '$name.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!);
    // The framework checks this is back to its default when the test ends.
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  Future<void> shot(
    WidgetTester tester,
    String name,
    Widget screen, {
    required String role,
    Size size = const Size(390, 844),
    double ratio = 2,
    bool kitchenEnabled = true,
    Future<void> Function()? before,
  }) async {
    late ClientDatabase db;
    late DeviceSync sync;
    await tester.runAsync(() async => (db, sync) = await cafe(role: role, kitchenEnabled: kitchenEnabled));
    final container = ProviderContainer(
      overrides: [
        deviceRuntimeProvider.overrideWithValue(DeviceRuntime.forTesting(db, sync)),
        // The banner as it looks on the café Wi-Fi (no POS here to connect to).
        linkStatusProvider.overrideWith(
          (ref) => Stream.value(LinkStatus(live: true, route: 'lan', lastLiveAt: now)),
        ),
      ],
    );
    await capture(tester, name, screen, container, size: size, ratio: ratio, before: before);
    await tester.runAsync(() => db.close());
  }

  /// The main till (POS) signed in as [role], on a small sample café.
  Future<void> posShot(
    WidgetTester tester,
    String name,
    StaffRole role, {
    Size size = const Size(1280, 800),
    double ratio = 1.5,
    bool kitchenEnabled = true,
    Future<void> Function()? before,
  }) async {
    late Harness h;
    late AppRuntime rt;
    late Actor actor;
    await tester.runAsync(() async {
      h = await Harness.create(start: DateTime.now().toUtc());
      final coffee = await h.category('Coffee');
      final snacks = await h.category('Snacks');
      final filter = await h.item(coffee, 'Filter coffee', 4000);
      final chai = await h.item(coffee, 'Masala chai', 3000);
      final puff = await h.item(snacks, 'Veg puff', 2500);
      final sandwich = await h.item(snacks, 'Paneer sandwich', 16000);
      final tables = TableService(h.ctx);
      final ids = [for (var i = 1; i <= 8; i++) await tables.createTable(h.owner, name: 'T$i', capacity: 4)];
      await h.openShift();
      await h.pay(await h.orderWith({filter: 2, puff: 2}), [
        const TenderInput(method: PaymentMethod.cash, applied: 13000, tendered: 20000),
      ]);
      await h.pay(await h.orderWith({sandwich: 1, chai: 2}), [
        const TenderInput(method: PaymentMethod.upi, applied: 22000),
      ]);
      final t2 = await h.orderWith({filter: 2, sandwich: 1}, type: OrderType.dineIn, tableId: ids[1]);
      await h.orders.sendToKitchen(h.cashier, t2, operationId: 'k-t2');
      final t5 = await h.orderWith({chai: 3, puff: 3}, type: OrderType.dineIn, tableId: ids[4]);
      await h.orders.sendToKitchen(h.cashier, t5, operationId: 'k-t5');
      final first = (await h.db.select(h.db.kitchenTickets).get()).first;
      await h.orders.setTicketStatus(h.kitchen, first.id, TicketStatus.preparing);
      if (!kitchenEnabled) await h.settings.setKitchenEnabled(h.owner, enabled: false);
      actor = switch (role) {
        StaffRole.waiter => Actor(
          staffId: await h.auth.createStaff(
            h.owner,
            name: 'Wendy Waiter',
            email: 'wendy@test.cafe',
            role: StaffRole.waiter,
            password: 'waiter-pass-1',
            mustChangePassword: false,
          ),
          name: 'Wendy Waiter',
          role: StaffRole.waiter,
        ),
        StaffRole.kitchen => h.kitchen,
        StaffRole.cashier => h.cashier,
        StaffRole.owner => h.owner,
      };
      final dir = Directory.systemTemp.createTempSync('cafedesk_shots');
      rt = AppRuntime.forTesting(AppPaths(dir, dir), h.db, h.clock);
    });
    final container = ProviderContainer(
      overrides: [runtimeProvider.overrideWithValue(rt), servicesProvider.overrideWithValue(rt.services)],
    );
    container.read(sessionProvider.notifier).login(actor);
    await capture(tester, name, const AppShell(), container, size: size, ratio: ratio, before: before);
    await tester.runAsync(() => h.dispose());
  }

  const skip = _enabled ? null : 'set --dart-define=CAFEDESK_SCREENSHOTS=true to write screenshots';

  testWidgets('waiter: tables', (tester) async {
    addTearDown(tester.view.reset);
    await shot(tester, 'waiter_1_tables', const WaiterHomeScreen(), role: 'waiter');
  }, skip: skip != null);

  testWidgets('waiter: taking an order', (tester) async {
    addTearDown(tester.view.reset);
    await shot(
      tester,
      'waiter_2_order',
      const OrderBuilderScreen(orderType: 'dine_in', tableId: 't2', tableLabel: 'T2'),
      role: 'waiter',
    );
  }, skip: skip != null);

  testWidgets('waiter: sent orders', (tester) async {
    addTearDown(tester.view.reset);
    await shot(
      tester,
      'waiter_3_sent',
      const WaiterHomeScreen(),
      role: 'waiter',
      before: () => tester.tap(find.text('Sent')),
    );
  }, skip: skip != null);

  testWidgets('waiter phone: to prepare (no kitchen)', (tester) async {
    addTearDown(tester.view.reset);
    await shot(
      tester,
      'waiter_4_to_prepare_no_kitchen',
      const WaiterHomeScreen(),
      role: 'waiter',
      kitchenEnabled: false,
      before: () => tester.tap(find.text('To prepare')),
    );
  }, skip: skip != null);

  testWidgets('till: admin home', (tester) async {
    addTearDown(tester.view.reset);
    await posShot(tester, 'till_1_admin_home', StaffRole.owner);
  }, skip: skip != null);

  testWidgets('till: waiter signed in (phone size)', (tester) async {
    addTearDown(tester.view.reset);
    await posShot(tester, 'till_2_waiter', StaffRole.waiter, size: const Size(390, 844), ratio: 2);
  }, skip: skip != null);

  testWidgets('till: kitchen board', (tester) async {
    addTearDown(tester.view.reset);
    await posShot(tester, 'till_3_kitchen', StaffRole.kitchen);
  }, skip: skip != null);

  testWidgets('kitchen display (tablet)', (tester) async {
    addTearDown(tester.view.reset);
    await shot(
      tester,
      'kitchen_board_tablet',
      const KitchenBoardScreen(),
      role: 'kitchen',
      size: const Size(1280, 800),
      ratio: 1.5,
    );
  }, skip: skip != null);
}
