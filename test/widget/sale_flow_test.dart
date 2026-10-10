import 'dart:io';

import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/app/theme.dart';
import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/features/auth/presentation/lock_screen.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/orders/presentation/pos_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  testWidgets('PIN pad submits digits and shows errors', (tester) async {
    String? submitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PinEntry(
            onSubmit: (pin) async {
              submitted = pin;
              if (pin != '4826') throw StateError('Wrong PIN');
            },
          ),
        ),
      ),
    );
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(submitted, '1234');
    expect(find.textContaining('Wrong PIN'), findsOneWidget);
    for (final d in ['4', '8', '2', '6']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle();
    expect(submitted, '4826');
    expect(find.textContaining('Wrong PIN'), findsNothing);
  });

  testWidgets('tap items, pay cash with change, bill is saved', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late Harness h;
    late String orderId;
    await tester.runAsync(() async {
      h = await Harness.create();
      final cat = await h.category('Coffee');
      await h.item(cat, 'Filter coffee', 4000);
      await h.item(cat, 'Masala chai', 3000);
      await h.openShift();
      orderId = await h.orders.createOrder(h.cashier, type: OrderType.takeaway);
    });
    final services = Services(
      h.ctx,
      backupService: BackupService(
        h.ctx,
        databaseFile: File('unused.sqlite'),
        defaultBackupDir: Directory.systemTemp,
        workDir: Directory.systemTemp,
      ),
    );

    final container = ProviderContainer(overrides: [servicesProvider.overrideWithValue(services)]);
    addTearDown(container.dispose);
    container.read(sessionProvider.notifier).login(h.cashier);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: PosScreen(orderId: orderId),
        ),
      ),
    );
    await _settle(tester);

    await tester.tap(menuItem('Filter coffee'));
    await _settle(tester);
    await tester.tap(menuItem('Filter coffee'));
    await _settle(tester);
    await tester.tap(menuItem('Masala chai'));
    await _settle(tester);
    expect(find.text('Pay ₹110.00'), findsOneWidget);

    await tester.tap(find.text('Pay ₹110.00'));
    await _settle(tester);
    expect(find.text('Amount due'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '200');
    await _settle(tester);
    expect(find.text('₹90.00'), findsWidgets, reason: 'change shown');
    await tester.tap(find.text('I have received this payment'));
    await _settle(tester);
    await tester.tap(find.text('Complete sale'));
    await _settle(tester);
    expect(find.textContaining('Bill TST-000001 saved'), findsOneWidget);
    expect(find.text('Give change'), findsOneWidget);
    expect(find.text('₹110.00'), findsWidgets);

    // Tear the UI down and flush its in-flight (fake-zone) queries before any
    // real-async database access, otherwise drift's lock deadlocks the test.
    await disposeTree(tester);
    await tester.runAsync(() async {
      final bills = await h.db.select(h.db.bills).get();
      expect(bills.single.total, 11000);
      expect(bills.single.changeTotal, 9000);
      await h.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 2)));
}

/// Lets database futures (real async) and route animations finish. Bounded
/// pumps instead of pumpAndSettle: a spinner would never "settle".
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Replaces the tree and pumps until stream subscriptions are cancelled and
/// pending fake-zone database futures have completed.
Future<void> disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}

/// The menu button (not the cart line) with [name].
Finder menuItem(String name) => find.descendant(of: find.byType(GridView), matching: find.text(name));
