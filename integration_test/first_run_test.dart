// End-to-end run on a real device or desktop, starting like a new install:
//   flutter test integration_test -d windows      (or an Android device id)
// Everything happens in a temporary folder that is deleted afterwards: the
// café data already on the device is never opened or changed.
import 'dart:io';

import 'package:cafedesk/app/app.dart';
import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('new install: set up the café, sign in as admin, open a shift, sell, pay', (tester) async {
    ensureTimeZonesLoaded();
    final tmp = Directory.systemTemp.createTempSync('cafedesk_first_run');
    final paths = AppPaths(
      Directory(p.join(tmp.path, 'data'))..createSync(),
      Directory(p.join(tmp.path, 'backups'))..createSync(),
    );
    final container = ProviderContainer(
      overrides: [appControllerProvider.overrideWith(() => AppController(paths: paths))],
    );
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const CafeDeskApp()));
    await settle(tester, 3);

    // First screen: what is this device for?
    expect(find.text('What is this device for?'), findsOneWidget);
    expect(find.textContaining('demo'), findsNothing, reason: 'no demo café or built-in accounts');
    await tester.tap(find.text('Set up my restaurant'));
    await settleUntil(tester, () => find.text('Set up your restaurant').evaluate().isNotEmpty);

    // The admin creates their own account.
    await type(tester, 'Restaurant name *', 'Test Café');
    await type(tester, 'Admin name *', 'Asha Admin');
    await type(tester, 'Admin email *', 'asha@test.cafe');
    await type(tester, 'Admin password *', 'first-run-pass');
    await type(tester, 'Repeat password *', 'first-run-pass');
    await tap(tester, 'Create restaurant');
    await settleUntil(tester, () => find.text('Write down your admin recovery code').evaluate().isNotEmpty);
    await tap(tester, 'I have written the recovery code down');
    await tap(tester, 'Continue');
    await settleUntil(tester, () => find.text('Shift & cash').evaluate().isNotEmpty);
    final admin = container.read(sessionProvider)!;
    expect(admin.name, 'Asha Admin');

    // A small menu (adding items has its own widget tests).
    final menu = container.read(servicesProvider).menu;
    final coffee = await menu.createCategory(admin, 'Coffee');
    await menu.saveItem(admin, ItemInput(categoryId: coffee, name: 'Filter coffee', price: 4000));

    await tap(tester, 'Shift & cash');
    await tap(tester, 'Open shift');
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.tap(find.widgetWithText(FilledButton, 'Open shift').last);
    await settle(tester, 2);
    await tester.pageBack();
    await settle(tester, 2);

    await tap(tester, 'New order');
    await tap(tester, 'Takeaway');
    await tap(tester, 'Filter coffee');
    // Phones show a cart summary bar; open the full cart first.
    if (find.text('View cart').evaluate().isNotEmpty) await tap(tester, 'View cart');
    await tester.tap(find.textContaining('Pay ₹').first);
    await settle(tester, 2);
    await tap(tester, 'I have received this payment');
    await tap(tester, 'Complete sale');
    await settle(tester, 2);
    expect(find.textContaining('-000001 saved'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await settle(tester, 2);
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // The OS may still hold the database file for a moment; it is a temp folder.
    }
  });
}

/// Bounded pumping (a spinner never "settles").
Future<void> settle(WidgetTester tester, int seconds) async {
  for (var i = 0; i < seconds * 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Keeps pumping (up to 30 s) until [done]: password hashing takes a while.
Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 120 && !done(); i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  await settle(tester, 1);
}

/// Scrolls [text] into view and taps it.
Future<void> tap(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(find.text(text).last);
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(find.text(text).last);
  await settle(tester, 2);
}

/// Types into the text field labelled [label].
Future<void> type(WidgetTester tester, String label, String value) async {
  final field = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == label);
  if (field.evaluate().isEmpty) {
    await tester.scrollUntilVisible(field, 200, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump(const Duration(milliseconds: 100));
}
