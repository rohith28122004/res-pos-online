// End-to-end run on a real device/desktop in demo mode:
//   flutter test integration_test -d windows      (or an Android device id)
// It writes to the app's data folder on that device (demo database only).
import 'package:cafedesk/app/app.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('demo café: sign in, sell, pay, see the saved bill', (tester) async {
    ensureTimeZonesLoaded();
    await tester.pumpWidget(const ProviderScope(child: CafeDeskApp()));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final tryDemo = find.text('Try the demo café');
    if (tryDemo.evaluate().isNotEmpty) {
      await tester.tap(tryDemo);
      // Seeding hashes demo PINs; give it time.
      await tester.pumpAndSettle(const Duration(seconds: 15));
    }
    // Leave production mode if the device was already set up as production.
    expect(
      find.textContaining('DEMO MODE'),
      findsWidgets,
      reason: 'run this test on a device whose CaféDesk is in demo mode or new',
    );

    await tester.tap(find.text('Demo Cashier'));
    await tester.pumpAndSettle();
    for (final d in ['1', '3', '5', '7']) {
      await tester.tap(find.widgetWithText(OutlinedButton, d));
    }
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Open a shift if needed.
    await tester.tap(find.text('Shift').last);
    await tester.pumpAndSettle();
    final open = find.text('Open shift');
    if (open.evaluate().isNotEmpty) {
      await tester.tap(open.first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1000');
      await tester.tap(find.widgetWithText(FilledButton, 'Open shift'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }

    await tester.tap(find.text('Sell').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New takeaway'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Filter coffee'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.textContaining('Pay ₹'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I have received this payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('saved'), findsWidgets);
  });
}
