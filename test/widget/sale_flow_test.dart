import 'dart:io';

import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/app/theme.dart';
import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/auth/presentation/lock_screen.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/orders/presentation/pos_screen.dart';
import 'package:cafedesk/shared/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  /// A seeded installation behind real providers (runtime + services).
  Future<(Harness, ProviderContainer)> boot(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late Harness h;
    await tester.runAsync(() async => h = await Harness.create());
    final dir = Directory.systemTemp.createTempSync('cafedesk_auth_ui');
    final rt = AppRuntime.forTesting(AppPaths(dir, dir), AppMode.production, h.db, h.clock);
    final container = ProviderContainer(
      overrides: [runtimeProvider.overrideWithValue(rt), servicesProvider.overrideWithValue(rt.services)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    );
    await _settle(tester);
    return (h, container);
  }

  testWidgets('lock screen: tap a name, wrong password errors, right password signs in', (tester) async {
    final (h, container) = await boot(tester, const LockScreen());
    expect(find.text('Sign in to use the till'), findsOneWidget);

    await tester.tap(find.widgetWithText(ActionChip, 'Cara Cashier'));
    await _settle(tester);
    expect(find.text(cashierEmail), findsOneWidget, reason: 'tapping a name fills in the email');

    await tester.enterText(find.byType(PasswordField), 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _settleUntil(tester, () => find.text('Email or password is wrong').evaluate().isNotEmpty);
    expect(find.text('Email or password is wrong'), findsOneWidget);
    expect(container.read(sessionProvider), isNull);

    await tester.enterText(find.byType(PasswordField), cashierPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await _settleUntil(tester, () => container.read(sessionProvider) != null);
    expect(container.read(sessionProvider)?.staffId, h.cashier.staffId);

    await _teardown(tester, container);
    await tester.runAsync(() => h.dispose());
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('a new account must choose its own password before using the app', (tester) async {
    late Harness h;
    late Actor asha;
    final (booted, container) = await boot(tester, const SizedBox());
    h = booted;
    await tester.runAsync(() async {
      await h.auth.createStaff(
        h.owner,
        name: 'Asha',
        email: 'asha@test.cafe',
        role: StaffRole.cashier,
        password: 'starting-pass',
      );
      asha = await h.auth.login('asha@test.cafe', 'starting-pass');
    });
    expect(asha.mustChangePassword, isTrue);
    container.read(sessionProvider.notifier).login(asha);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildTheme(),
          home: PasswordChangeRequiredScreen(actor: asha),
        ),
      ),
    );
    await _settle(tester);

    final fields = find.byType(PasswordField);
    await tester.enterText(fields.at(0), 'my-own-secret');
    await tester.enterText(fields.at(1), 'does-not-match');
    await tester.tap(find.text('Save and continue'));
    await tester.pump();
    expect(find.text('Passwords do not match'), findsOneWidget);

    await tester.enterText(fields.at(1), 'my-own-secret');
    await tester.tap(find.text('Save and continue'));
    await _settleUntil(tester, () => container.read(sessionProvider)?.mustChangePassword == false);
    expect(container.read(sessionProvider)?.mustChangePassword, isFalse);

    await _teardown(tester, container);
    await tester.runAsync(() async {
      expect((await h.auth.login('asha@test.cafe', 'my-own-secret')).mustChangePassword, isFalse);
      await h.dispose();
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

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

/// Like [_settle], but keeps going (up to ~10 s of real time) until [done]:
/// password hashing runs on a real background isolate.
Future<void> _settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await _settle(tester);
}

/// Removes the tree, disposes the providers (closing drift stream queries),
/// then lets fake time run so stream-close timers and fake-zone queries finish
/// before any real-async database access.
Future<void> _teardown(WidgetTester tester, ProviderContainer container) async {
  await tester.pumpWidget(const SizedBox());
  container.dispose();
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
  }
}
