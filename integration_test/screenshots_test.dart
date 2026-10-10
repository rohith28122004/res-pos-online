// Walks the demo café and captures screenshots:
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/screenshots_test.dart -d <device>
// Screenshots land in build/screenshots/. Uses the demo database only.
import 'dart:io';

import 'package:cafedesk/app/app.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle(WidgetTester tester, [int seconds = 2]) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 1);
    await binding.takeScreenshot(name);
  }

  testWidgets('demo screenshots', (tester) async {
    ensureTimeZonesLoaded();
    await tester.pumpWidget(const ProviderScope(child: CafeDeskApp()));
    await settle(tester, 3);
    if (Platform.isAndroid) await binding.convertFlutterSurfaceToImage();

    if (find.text('Try the demo café').evaluate().isNotEmpty) {
      await shot(tester, '01_welcome');
      await tester.tap(find.text('Try the demo café'));
      await settle(tester, 20);
    }
    await shot(tester, '02_lock_screen');

    await tester.tap(find.text('Demo Owner'));
    await settle(tester);
    for (final d in ['2', '5', '8', '0']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await settle(tester, 6);

    // Open a shift through the Shift screen if needed.
    Future<void> go(String label) async {
      final rail = find.text(label);
      if (rail.evaluate().isNotEmpty) {
        await tester.tap(rail.last);
      } else {
        await tester.tap(find.text('More'));
        await settle(tester, 1);
        await tester.tap(find.text(label).last);
      }
      await settle(tester);
    }

    await go('Shift');
    if (find.text('Open shift').evaluate().isNotEmpty) {
      await tester.tap(find.text('Open shift').first);
      await settle(tester, 1);
      await tester.enterText(find.byType(TextField).last, '2000');
      await tester.tap(find.widgetWithText(FilledButton, 'Open shift').last);
      await settle(tester, 2);
    }

    await go('Sell');
    await tester.tap(find.text('New takeaway'));
    await settle(tester, 2);
    await tester.tap(find.text('Filter coffee'));
    await settle(tester, 1);
    await tester.tap(find.text('Masala chai'));
    await settle(tester, 1);
    await tester.tap(find.text('Veg puff'));
    await settle(tester, 1);
    await shot(tester, '03_pos');

    final viewCart = find.text('View cart');
    if (viewCart.evaluate().isNotEmpty) {
      await tester.tap(viewCart);
      await settle(tester);
      await shot(tester, '04_cart');
    }
    await tester.tap(find.textContaining('Pay ₹').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '200');
    await tester.scrollUntilVisible(
      find.text('I have received this payment'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('I have received this payment'));
    await settle(tester, 1);
    await shot(tester, '05_checkout');
    await tester.scrollUntilVisible(find.text('Complete sale'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Complete sale'));
    await settle(tester, 3);
    await shot(tester, '06_bill_saved');
    await tester.tap(find.text('Done'));
    await settle(tester);

    await go('Dashboard');
    await settle(tester, 3);
    await shot(tester, '07_dashboard');
    await go('Kitchen');
    await shot(tester, '08_kitchen');
    await go('Bills');
    await shot(tester, '09_bills');
  });
}
