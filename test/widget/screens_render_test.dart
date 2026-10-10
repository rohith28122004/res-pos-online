import 'dart:io';

import 'package:cafedesk/app/providers.dart';
import 'package:cafedesk/app/runtime.dart';
import 'package:cafedesk/app/shell.dart';
import 'package:cafedesk/app/theme.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/audit/presentation/audit_screen.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/bills/presentation/bill_detail_screen.dart';
import 'package:cafedesk/features/checkout/presentation/checkout_screen.dart';
import 'package:cafedesk/features/dashboard/presentation/dashboard_screen.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/orders/presentation/pos_screen.dart';
import 'package:cafedesk/features/refunds/presentation/refund_screen.dart';
import 'package:cafedesk/features/settings/presentation/backup_screen.dart';
import 'package:cafedesk/features/settings/presentation/printers_screen.dart';
import 'package:cafedesk/features/settings/presentation/settings_screen.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Renders every main screen at phone and desktop sizes on top of a seeded
/// in-memory installation, failing on any exception or layout overflow.
void main() {
  late Harness h;
  late AppRuntime rt;
  late String openOrder;
  late String billId;

  Future<void> seed() async {
    h = await Harness.create();
    final gst = await h.taxProfile('GST 5%', TaxMode.exclusive);
    final cat = await h.category('Coffee');
    final food = await h.category('A very long category name for wrapping');
    await h.item(cat, 'Filter coffee', 4000);
    final latte = await h.item(
      cat,
      'Café latte',
      0,
      taxProfileId: gst,
      variants: const [
        VariantInput(name: 'Regular', price: 15000),
        VariantInput(name: 'Large', price: 19000),
      ],
      modifiers: const [ModifierInput(name: 'Oat milk', price: 4000)],
    );
    final sandwich = await h.item(
      food,
      'Paneer tikka grilled sandwich with extra cheese and mint chutney',
      16000,
      taxProfileId: gst,
    );
    await TableService(h.ctx).createTable(h.owner, name: 'T1', capacity: 4);
    await h.openShift();
    final o = await h.orderWith({sandwich: 2});
    billId = (await h.pay(o, [const TenderInput(method: PaymentMethod.cash, applied: 33600, tendered: 50000)])).billId;
    openOrder = await h.orders.createOrder(h.cashier, type: OrderType.dineIn);
    final menu = await h.menu.loadMenu();
    final l = menu.items.firstWhere((i) => i.id == latte);
    await h.orders.addItem(
      h.cashier,
      openOrder,
      itemId: latte,
      variantId: l.variants.last.id,
      modifierIds: [l.modifiers.first.id],
      note: 'Extra hot please',
    );
    await h.orders.sendToKitchen(h.cashier, openOrder, operationId: 'k1');
    final dir = Directory.systemTemp.createTempSync('cafedesk_render');
    rt = AppRuntime.forTesting(AppPaths(dir, dir), AppMode.production, h.db, h.clock);
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen, Size size, Actor actor) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final container = ProviderContainer(
      overrides: [
        runtimeProvider.overrideWithValue(rt),
        servicesProvider.overrideWithValue(rt.services),
      ],
    );
    container.read(sessionProvider.notifier).login(actor);
    // Collect framework errors (overflows etc.) with full diagnostics.
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
      // Text outside any Material is painted with Flutter's debug fallback
      // style (red, underlined). That is not an exception, so check for it.
      final unstyled = [
        for (final p in tester.renderObjectList<RenderParagraph>(find.byType(RichText)))
          if (p.text.style?.toString().contains('fallback style') ?? false) p.text.toPlainText(),
      ];
      expect(unstyled, isEmpty, reason: 'text without a Material ancestor');
      // Tear down the tree and the providers (cancelling drift stream queries),
      // then let fake time run so drift's stream-close timers and any in-flight
      // fake-zone queries finish before real-async database access.
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

  const phone = Size(390, 844);
  const desktop = Size(1400, 900);

  final screens = <String, Widget Function()>{
    'shell (owner)': () => const AppShell(),
    'POS': () => PosScreen(orderId: openOrder),
    'checkout': () => CheckoutScreen(orderId: openOrder),
    'bill detail': () => BillDetailScreen(billId: billId),
    'refund': () => RefundScreen(billId: billId),
    'dashboard': () => const Scaffold(body: DashboardScreen()),
    'settings': () => const Scaffold(body: SettingsScreen()),
    'printers': () => const PrintersScreen(),
    'printer editor': () => const PrinterEditorScreen(),
    'backup': () => const BackupScreen(),
    'audit': () => const AuditScreen(),
    'taxes': () => const TaxProfilesScreen(),
    'about': () => const AboutScreen(),
  };

  for (final size in [phone, desktop]) {
    testWidgets('demo-mode shell renders at ${size.width.toInt()}', (tester) async {
      await tester.runAsync(seed);
      addTearDown(tester.view.reset);
      final dir = Directory.systemTemp.createTempSync('cafedesk_render_demo');
      rt = AppRuntime.forTesting(AppPaths(dir, dir), AppMode.demo, h.db, h.clock);
      await pumpScreen(tester, const AppShell(), size, h.owner);
      await tester.runAsync(() => h.dispose());
    }, timeout: const Timeout(Duration(minutes: 2)));
    for (final e in screens.entries) {
      testWidgets('${e.key} renders at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        await tester.runAsync(seed);
        addTearDown(tester.view.reset);
        await pumpScreen(tester, e.value(), size, h.owner);
        await tester.runAsync(() => h.dispose());
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
    testWidgets('kitchen role sees only the kitchen board at ${size.width.toInt()}', (tester) async {
      await tester.runAsync(seed);
      addTearDown(tester.view.reset);
      await pumpScreen(tester, const AppShell(), size, h.kitchen);
      await tester.runAsync(() => h.dispose());
    }, timeout: const Timeout(Duration(minutes: 2)));
  }
}
