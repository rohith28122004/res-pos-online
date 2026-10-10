// End-to-end run on a real device/desktop in demo mode:
//   flutter test integration_test -d windows      (or an Android device id)
// It writes to the app's data folder on that device (demo database only).
import 'package:cafedesk/app/app.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/setup/application/demo_seed.dart';
import 'package:cafedesk/shared/widgets/common.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo café: sign in, sell, pay, see the saved bill', (tester) async {
    ensureTimeZonesLoaded();
    await tester.pumpWidget(const ProviderScope(child: CafeDeskApp()));
    await settle(tester, 4);

    final tryDemo = find.text('Try the demo café');
    if (tryDemo.evaluate().isNotEmpty) {
      await tester.tap(tryDemo);
      // Seeding hashes the demo passwords; give it time.
      await settle(tester, 60);
    }
    // Leave production mode if the device was already set up as production.
    expect(
      find.textContaining('DEMO MODE'),
      findsWidgets,
      reason: 'run this test on a device whose CaféDesk is in demo mode or new',
    );

    // Tapping a name fills in the email; then the demo password.
    await tester.tap(find.widgetWithText(ActionChip, 'Demo Cashier'));
    await settle(tester, 1);
    await tester.enterText(find.byType(PasswordField), DemoLogins.password);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await settle(tester, 8);

    // Open a shift if needed (on phones "Shift" lives under "More").
    await go(tester, 'Shift');
    final open = find.text('Open shift');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open.first);
      await settle(tester, 1);
      await tester.enterText(find.byType(TextField).last, '1000');
      await tester.tap(find.widgetWithText(FilledButton, 'Open shift').last);
      await settle(tester, 2);
    }

    await go(tester, 'Sell');
    await tester.tap(find.text('New takeaway'));
    await settle(tester, 3);
    await tester.tap(find.text('Filter coffee').first);
    await settle(tester, 2);
    // Phones show a cart summary bar; open the full cart first.
    final viewCart = find.text('View cart');
    if (viewCart.evaluate().isNotEmpty) {
      await tester.tap(viewCart);
      await settle(tester, 2);
    }
    await tester.tap(find.textContaining('Pay ₹').first);
    await settle(tester, 2);
    await tester.scrollUntilVisible(
      find.text('I have received this payment'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('I have received this payment'));
    await settle(tester, 1);
    await tester.scrollUntilVisible(find.text('Complete sale'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Complete sale'));
    await settle(tester, 4);
    expect(find.textContaining('saved'), findsWidgets);
    expect(find.textContaining('Bill DEMO-'), findsOneWidget);
  });
}

/// Bounded pumping (a spinner never "settles").
Future<void> settle(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Navigates via the rail/bottom bar, or the "More" sheet on phones.
Future<void> go(WidgetTester tester, String label) async {
  final direct = find.text(label);
  if (direct.evaluate().isNotEmpty) {
    await tester.tap(direct.last);
  } else {
    await tester.tap(find.text('More'));
    await settle(tester, 1);
    await tester.tap(find.text(label).last);
  }
  await settle(tester, 2);
}
