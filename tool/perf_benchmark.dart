// Performance benchmark: 1,000 menu items and 50,000 bills in a file database.
//
//   dart run tool/perf_benchmark.dart [bills] [items]
//
// Prints timings for menu load/search, an order edit round trip, a checkout,
// and dashboard queries over a month and the full range. Run it on the device
// class you care about and record the results in docs/MANUAL_TEST_CHECKLIST.md
// with the machine description — numbers from one machine say nothing about
// another.
import 'dart:io';
import 'dart:math';

import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/security/pin_hasher.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/checkout/application/checkout_service.dart';
import 'package:cafedesk/features/dashboard/application/report_service.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/application/order_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/setup/application/setup_service.dart';
import 'package:cafedesk/features/shifts/application/shift_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';

Future<void> main(List<String> args) async {
  final billCount = args.isNotEmpty ? int.parse(args[0]) : 50000;
  final itemCount = args.length > 1 ? int.parse(args[1]) : 1000;
  ensureTimeZonesLoaded();
  final dir = await Directory.systemTemp.createTemp('cafedesk_perf');
  final file = File('${dir.path}${Platform.pathSeparator}perf.sqlite');
  final db = AppDatabase(NativeDatabase.createInBackground(file, setup: configureConnection));
  final clock = FixedClock(DateTime.utc(2026, 9, 30, 4));
  final ctx = ServiceContext(db: db, clock: clock);
  final sw = Stopwatch();
  String ms() => '${sw.elapsedMilliseconds} ms';

  stdout.writeln(
    'CaféDesk benchmark on ${Platform.operatingSystem} ${Platform.operatingSystemVersion}, '
    '${Platform.numberOfProcessors} logical CPUs',
  );
  final setup = await SetupService(ctx, hasher: const PinHasher.fastForTests()).completeSetup(
    const SetupInput(restaurantName: 'Perf Café', ownerName: 'Owner', ownerPin: '4826', receiptPrefix: 'PRF'),
  );
  final owner = setup.owner;
  final menu = MenuService(ctx);

  sw.start();
  final cats = <String>[];
  for (var c = 0; c < 20; c++) {
    cats.add(await menu.createCategory(owner, 'Category $c'));
  }
  await db.batch((b) {
    for (var i = 0; i < itemCount; i++) {
      b.insert(
        db.menuItems,
        MenuItemsCompanion.insert(
          id: 'item-$i',
          categoryId: cats[i % cats.length],
          name: 'Menu item number $i ${['Latte', 'Dosa', 'Sandwich', 'Tea', 'Cake'][i % 5]}',
          price: 5000 + (i % 40) * 500,
          updatedAt: clock.nowUtc().millisecondsSinceEpoch,
        ),
      );
    }
  });
  stdout.writeln('Inserted $itemCount items: ${ms()}');

  sw.reset();
  final data = await menu.loadMenu();
  stdout.writeln('Load full menu (${data.items.length} items): ${ms()}');
  sw.reset();
  var hits = 0;
  for (final q in ['latte', 'item number 9', 'cake', 'zzz']) {
    hits += data.items.where((i) => i.name.toLowerCase().contains(q)).length;
  }
  stdout.writeln('4 in-memory searches ($hits hits): ${sw.elapsedMicroseconds} µs');

  // Bulk-load bills directly (fast), spread over 120 business days.
  sw.reset();
  final shiftId = await ShiftService(ctx).openShift(owner, openingFloat: 0);
  final rnd = Random(42);
  const chunk = 2000;
  for (var start = 0; start < billCount; start += chunk) {
    await db.batch((b) {
      for (var n = start; n < min(start + chunk, billCount); n++) {
        final day = BusinessDate(2026, 6, 1).addDays(n % 120);
        final total = 10000 + rnd.nextInt(90000);
        final at = DateTime.utc(day.year, day.month, day.day, 6 + rnd.nextInt(14)).millisecondsSinceEpoch;
        b.insert(
          db.orders,
          OrdersCompanion.insert(
            id: 'o$n',
            orderNo: n + 10,
            orderType: n.isEven ? 'takeaway' : 'dine_in',
            status: OrderStatus.finalized,
            createdBy: owner.staffId,
            createdByName: owner.name,
            createdAt: at,
            updatedAt: at,
            businessDate: day.key,
          ),
        );
        b.insert(
          db.orderLines,
          OrderLinesCompanion.insert(
            id: 'ol$n',
            orderId: 'o$n',
            itemName: 'Item ${n % itemCount}',
            unitPrice: total,
            quantity: 1,
            taxJson: '{"mode":"disabled","rateBps":0,"components":[]}',
            createdBy: owner.staffId,
            createdAt: at,
            updatedAt: at,
          ),
        );
        b.insert(
          db.bills,
          BillsCompanion.insert(
            id: 'b$n',
            receiptNo: 'PRF-${(n + 1000).toString().padLeft(6, '0')}',
            receiptSeq: n + 1000,
            orderId: 'o$n',
            operationId: 'op$n',
            orderNo: n + 10,
            orderType: n.isEven ? 'takeaway' : 'dine_in',
            businessDate: day.key,
            localHour: 8 + n % 12,
            createdAt: at,
            staffId: owner.staffId,
            staffName: owner.name,
            shiftId: shiftId,
            itemCount: 1,
            itemsGrossEntered: total,
            discountEnteredTotal: 0,
            itemsGrossEx: total,
            itemsDiscountEx: 0,
            itemsNetEx: total,
            chargesNetEx: 0,
            taxTotal: 0,
            subtotalBeforeRounding: total,
            roundingAdjustment: 0,
            total: total,
            changeTotal: 0,
            currencyCode: 'INR',
            timeZone: 'Asia/Kolkata',
            restaurantJson: '{"name":"Perf Café","address":"","footer":""}',
          ),
        );
        b.insert(
          db.billLines,
          BillLinesCompanion.insert(
            id: 'bl$n',
            billId: 'b$n',
            orderLineId: 'ol$n',
            itemId: Value('item-${n % itemCount}'),
            itemName: 'Item ${n % itemCount}',
            categoryName: Value('Category ${n % 20}'),
            modifiersJson: '[]',
            quantity: 1,
            unitPriceEntered: total,
            grossEntered: total,
            lineDiscountEntered: 0,
            billDiscountEntered: 0,
            grossEx: total,
            discountEx: 0,
            netEx: total,
            taxMode: 'disabled',
            taxRateBps: 0,
            tax: 0,
            total: total,
            sortOrder: 0,
          ),
        );
        b.insert(
          db.payments,
          PaymentsCompanion.insert(
            id: 'p$n',
            billId: 'b$n',
            method: ['cash', 'upi', 'card'][n % 3],
            applied: total,
            tendered: total,
            changeGiven: 0,
            shiftId: shiftId,
            businessDate: day.key,
            createdAt: at,
            confirmedBy: owner.staffId,
            confirmedByName: owner.name,
          ),
        );
      }
    });
  }
  await db
      .into(db.sequences)
      .insertOnConflictUpdate(SequencesCompanion.insert(name: 'receipt', nextValue: billCount + 2000));
  stdout.writeln('Inserted $billCount bills: ${ms()}');

  final reports = ReportService(ctx);
  for (final (label, range) in [
    ('One day', BusinessDateRange(BusinessDate(2026, 7, 15), BusinessDate(2026, 7, 16))),
    ('One month (July)', BusinessDateRange(BusinessDate(2026, 7, 1), BusinessDate(2026, 8, 1))),
    ('All 120 days', BusinessDateRange(BusinessDate(2026, 6, 1), BusinessDate(2026, 10, 1))),
  ]) {
    sw.reset();
    final d = await reports.dashboard(owner, range);
    stdout.writeln('Dashboard $label (${d.billCount} bills): ${ms()}');
  }

  // An order edit and a full checkout on the large database.
  final orders = OrderService(ctx);
  sw.reset();
  final orderId = await orders.createOrder(owner, type: OrderType.takeaway);
  await orders.addItem(owner, orderId, itemId: 'item-1', quantity: 2);
  await orders.addItem(owner, orderId, itemId: 'item-2');
  stdout.writeln('Create order + 2 adds: ${ms()}');
  sw.reset();
  final detail = await orders.loadOrder(orderId);
  stdout.writeln('Reload order with pricing: ${ms()}');
  sw.reset();
  await CheckoutService(ctx).finalize(
    owner,
    FinalizeRequest(
      orderId: orderId,
      operationId: 'perf-checkout',
      tenders: [TenderInput(method: PaymentMethod.cash, applied: detail.pricing!.total)],
      paymentConfirmed: true,
    ),
  );
  stdout.writeln('Checkout: ${ms()}');
  stdout.writeln('Database size: ${(await file.length()) ~/ 1024} KB');

  await db.close();
  await dir.delete(recursive: true);
}
