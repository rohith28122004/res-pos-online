import 'dart:convert';
import 'dart:io';

import 'package:cafedesk/app/device_runtime.dart';
import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/app/theme.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/sync/client_database.dart';
import 'package:cafedesk/core/sync/device_sync.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/devices/presentation/connected_devices_screen.dart';
import 'package:cafedesk/features/devices/presentation/device_app.dart';
import 'package:cafedesk/features/kitchen/presentation/kitchen_board_screen.dart';
import 'package:cafedesk/features/waiter/presentation/order_builder.dart';
import 'package:cafedesk/features/waiter/presentation/order_detail.dart';
import 'package:cafedesk/features/waiter/presentation/sent_commands.dart';
import 'package:cafedesk/features/waiter/presentation/waiter_home.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Renders every phone / kitchen / device-management screen at phone and
/// tablet sizes on seeded data, failing on exceptions, layout overflow and
/// unstyled text.
void main() {
  const phone = Size(390, 844);
  const tablet = Size(1280, 800);
  final now = DateTime.utc(2026, 10, 11, 6).millisecondsSinceEpoch;

  Future<(ClientDatabase, DeviceSync)> seededDevice({required String role, bool signedIn = true}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = openInMemoryClientDatabase();
    final sync = DeviceSync(
      db: db,
      secrets: MemorySecretStore(),
      clock: FixedClock(DateTime.fromMillisecondsSinceEpoch(now, isUtc: true)),
    );
    await db
        .into(db.clientLink)
        .insert(
          ClientLinkCompanion.insert(
            singleton: const Value(1),
            deviceId: 'dev-1',
            role: role,
            deviceName: 'Front phone',
            restaurantId: 'r1',
            restaurantName: 'The Very Long Named Café and Bakery of Chennai',
            hostDeviceId: 'h1',
            hostEpoch: 1,
            hostAddressesJson: '["192.168.1.10"]',
            hostPort: 47821,
            certSha256: '0' * 64,
            signingPublicKey: 'x',
            sealPublicKey: 'y',
            pairedAt: now,
            cursorEpoch: const Value(1),
            cursorSequence: const Value(10),
            lastLiveAt: Value(now - 120000),
          ),
        );
    if (signedIn) {
      await db
          .into(db.clientSessions)
          .insert(
            ClientSessionsCompanion.insert(
              singleton: const Value(1),
              staffId: 's1',
              name: 'Wendy Waiter',
              role: role == 'kitchen' ? 'kitchen' : 'waiter',
              expiresAt: now + 3600000,
            ),
          );
    }
    Future<void> put(String key, String kind, Object value) => db
        .into(db.cacheEntries)
        .insert(CacheEntriesCompanion.insert(key: key, kind: kind, json: jsonEncode(value), updatedAt: now));
    await put('meta', 'meta', {'restaurantName': 'The Very Long Named Café and Bakery of Chennai', 'hostEpoch': 1});
    await put('menu', 'menu', {
      'categories': [
        {'categoryId': 'c1', 'name': 'Coffee'},
        {'categoryId': 'c2', 'name': 'A very long category name for wrapping on small phones'},
      ],
      'items': [
        {
          'itemId': 'i1',
          'categoryId': 'c1',
          'name': 'Filter coffee',
          'price': 4000,
          'available': true,
          'variants': [],
          'modifiers': [],
        },
        {
          'itemId': 'i2',
          'categoryId': 'c1',
          'name': 'Café latte',
          'price': 0,
          'available': true,
          'variants': [
            {'variantId': 'v1', 'name': 'Regular', 'price': 15000},
            {'variantId': 'v2', 'name': 'Large', 'price': 19000},
          ],
          'modifiers': [
            {'modifierId': 'm1', 'name': 'Oat milk', 'price': 4000},
          ],
        },
        {
          'itemId': 'i3',
          'categoryId': 'c2',
          'name': 'Paneer tikka grilled sandwich with extra cheese and mint chutney',
          'price': 16000,
          'available': false,
          'variants': [],
          'modifiers': [],
        },
      ],
    });
    await put('tables', 'tables', [
      for (var i = 1; i <= 9; i++)
        {'tableId': 't$i', 'name': 'T$i', 'capacity': 4, 'openOrderId': null, 'openOrderNo': null},
    ]);
    final order = {
      'orderId': 'o1',
      'orderNo': 12,
      'orderRef': 'T1 · #12',
      'orderType': 'dine_in',
      'tableId': 't1',
      'tableLabel': 'T1',
      'status': 'open',
      'revision': 4,
      'createdBy': 's1',
      'createdByName': 'Wendy Waiter',
      'createdAt': now - 600000,
      'guestCount': 3,
      'note': null,
      'estimatedTotal': 38000,
      'lines': [
        {
          'lineId': 'l1',
          'itemId': 'i2',
          'itemName': 'Café latte',
          'variantName': 'Large',
          'modifiers': ['Oat milk'],
          'note': 'Extra hot please, and no sugar at all',
          'quantity': 2,
          'sentQuantity': 1,
          'unitPrice': 23000,
          'revision': 2,
          'createdBy': 's1',
          'createdByName': 'Wendy Waiter',
        },
      ],
    };
    await put('order:o1', 'order', order);
    Map<String, Object?> ticket(String id, int no, String status, {String kind = 'order', int ageMin = 3}) => {
      'ticketId': id,
      'ticketNo': no,
      'orderId': 'o1',
      'orderRef': 'T1 · #12',
      'tableLabel': 'T1',
      'kind': kind,
      'reason': kind == 'correction' ? 'Customer changed their mind' : null,
      'status': status,
      'revision': 1,
      'createdBy': 's1',
      'createdByName': 'Wendy Waiter',
      'createdAt': now - ageMin * 60000,
      'lines': [
        {
          'itemName': 'Paneer tikka grilled sandwich with extra cheese and mint chutney',
          'variantName': 'Large',
          'modifiersText': 'Oat milk, Extra shot',
          'note': 'No onion, very spicy, cut in four',
          'quantityDelta': kind == 'correction' ? -1 : 2,
        },
      ],
    };
    await put('ticket:k1', 'ticket', ticket('k1', 31, 'pending'));
    await put('ticket:k2', 'ticket', ticket('k2', 32, 'preparing', ageMin: 20));
    await put('ticket:k3', 'ticket', ticket('k3', 33, 'ready'));
    await put('ticket:k4', 'ticket', ticket('k4', 34, 'pending', kind: 'correction'));
    Future<void> cmd(String id, String state, {String? code, String? message, Map<String, Object?>? result}) => db
        .into(db.pendingCommands)
        .insert(
          PendingCommandsCompanion.insert(
            commandId: id,
            staffId: 's1',
            action: CommandAction.orderPlace,
            bodyJson: jsonEncode({
              'payload': {'lines': []},
            }),
            summary: 'T$id: 2 items',
            state: state,
            createdAt: now,
            updatedAt: now,
            errorCode: Value(code),
            errorMessage: Value(message),
            resultJson: Value(result == null ? null : jsonEncode(result)),
          ),
        );
    await cmd('2', CommandState.queued);
    await cmd('3', CommandState.relayed);
    await cmd(
      '4',
      CommandState.accepted,
      result: {
        'commandId': '4',
        'state': 'accepted',
        'hostEpoch': 1,
        'resultId': 'o1',
        'result': {'orderRef': 'T1 · #12', 'ticketNo': 31},
      },
    );
    await cmd(
      '5',
      CommandState.rejected,
      code: ErrorCode.priceChanged,
      message: 'Prices changed. Check the new prices and send again.',
      result: {
        'commandId': '5',
        'state': 'rejected',
        'hostEpoch': 1,
        'error': {
          'code': ErrorCode.priceChanged,
          'message': 'Prices changed',
          'retryable': false,
          'details': {
            'lines': [
              {'index': 0, 'itemId': 'i1', 'itemName': 'Filter coffee', 'expected': 3500, 'current': 4000},
            ],
          },
        },
      },
    );
    await cmd(
      '6',
      CommandState.rejected,
      code: ErrorCode.tableOccupied,
      message: 'T6 already has an open order (#13)',
      result: {
        'commandId': '6',
        'state': 'rejected',
        'hostEpoch': 1,
        'error': {
          'code': ErrorCode.tableOccupied,
          'message': 'T6 already has an open order',
          'retryable': false,
          'details': {'orderId': 'o9', 'orderNo': 13, 'revision': 2, 'createdByName': 'Raj'},
        },
      },
    );
    await cmd('7', CommandState.needsReview, code: ErrorCode.expired, message: 'Not delivered within 30 minutes.');
    return (db, sync);
  }

  Future<void> pump(WidgetTester tester, Widget screen, Size size, List<Override> overrides) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final container = ProviderContainer(overrides: overrides);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d);
      debugPrint(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error).toStringDeep());
    };
    try {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildTheme(), home: screen),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      final unstyled = [
        for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText)))
          if (p.text.style?.toString().contains('fallback style') ?? false) p.text.toPlainText(),
      ];
      expect(unstyled, isEmpty, reason: 'text without a Material ancestor');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
    } finally {
      FlutterError.onError = previous;
    }
    expect(errors, isEmpty, reason: errors.map((e) => e.exceptionAsString()).join('\n'));
  }

  final waiterScreens = <String, Widget Function()>{
    'sign-in': () => const DeviceApp(),
    'waiter home': () => const WaiterHomeScreen(),
    'order builder': () => const OrderBuilderScreen(orderType: 'dine_in', tableId: 't2', tableLabel: 'T2'),
    'order detail': () => const OrderDetailScreen(orderId: 'o1'),
    'item options': () => Scaffold(
      body: ItemOptionsSheet(
        item: {
          'itemId': 'i2',
          'name': 'Café latte',
          'price': 0,
          'variants': [
            {'variantId': 'v1', 'name': 'Regular', 'price': 15000},
            {'variantId': 'v2', 'name': 'Large', 'price': 19000},
          ],
          'modifiers': [
            {'modifierId': 'm1', 'name': 'Oat milk', 'price': 4000},
          ],
        },
      ),
    ),
  };

  for (final size in [phone, tablet]) {
    final label = '${size.width.toInt()}';
    for (final e in waiterScreens.entries) {
      testWidgets('${e.key} renders at $label', (tester) async {
        addTearDown(tester.view.reset);
        late ClientDatabase db;
        late DeviceSync sync;
        await tester.runAsync(
          () async => (db, sync) = await seededDevice(role: 'waiter', signedIn: e.key != 'sign-in'),
        );
        await pump(tester, e.value(), size, [
          deviceRuntimeProvider.overrideWithValue(DeviceRuntime.forTesting(db, sync)),
        ]);
        await tester.runAsync(() => db.close());
      }, timeout: const Timeout(Duration(minutes: 2)));
    }

    testWidgets('waiter sent tab renders at $label', (tester) async {
      addTearDown(tester.view.reset);
      late ClientDatabase db;
      late DeviceSync sync;
      await tester.runAsync(() async => (db, sync) = await seededDevice(role: 'waiter'));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final container = ProviderContainer(
        overrides: [deviceRuntimeProvider.overrideWithValue(DeviceRuntime.forTesting(db, sync))],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildTheme(), home: const WaiterHomeScreen()),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.tap(find.text('Sent'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 100));
      }
      final list = find.descendant(of: find.byType(SentCommandsList), matching: find.byType(Scrollable)).first;
      for (final f in [
        find.textContaining('Waiting in the cloud'),
        find.text('See new prices'),
        find.text('Add to order #13'),
        find.text('Send again'),
      ]) {
        await tester.scrollUntilVisible(f, 120, scrollable: list);
        expect(f, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      await tester.runAsync(() => db.close());
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('kitchen board renders at $label', (tester) async {
      addTearDown(tester.view.reset);
      late ClientDatabase db;
      late DeviceSync sync;
      await tester.runAsync(() async => (db, sync) = await seededDevice(role: 'kitchen'));
      await pump(tester, const KitchenBoardScreen(), size, [
        deviceRuntimeProvider.overrideWithValue(DeviceRuntime.forTesting(db, sync)),
      ]);
      await tester.runAsync(() => db.close());
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('pairing screen renders at $label', (tester) async {
      addTearDown(tester.view.reset);
      late ClientDatabase db;
      late DeviceSync sync;
      await tester.runAsync(() async {
        db = openInMemoryClientDatabase();
        sync = DeviceSync(db: db, secrets: MemorySecretStore(), clock: const SystemClock());
      });
      await pump(tester, const DeviceApp(), size, [
        deviceRuntimeProvider.overrideWithValue(DeviceRuntime.forTesting(db, sync)),
      ]);
      await tester.runAsync(() => db.close());
    }, timeout: const Timeout(Duration(minutes: 2)));

    testWidgets('POS connected devices screen renders at $label', (tester) async {
      addTearDown(tester.view.reset);
      late Harness h;
      late AppRuntime rt;
      await tester.runAsync(() async {
        h = await Harness.create();
        final dir = Directory.systemTemp.createTempSync('cafedesk_connected');
        rt = AppRuntime.forTesting(AppPaths(dir, dir), AppMode.production, h.db, h.clock);
      });
      final container = ProviderContainer(
        overrides: [runtimeProvider.overrideWithValue(rt), servicesProvider.overrideWithValue(rt.services)],
      );
      container.read(sessionProvider.notifier).login(h.owner);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(theme: buildTheme(), home: const ConnectedDevicesScreen()),
        ),
      );
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Let paired phones connect to this POS'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      await tester.runAsync(() => h.dispose());
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
