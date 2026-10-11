// ignore_for_file: unused_local_variable, unused_import, prefer_single_quotes
import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/bills/application/bill_service.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/checkout/application/checkout_service.dart';
import 'package:cafedesk/features/orders/application/order_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/core/security/password_hasher.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/auth/application/auth_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;
import 'generated/schema_v4.dart' as v4;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SchemaVerifier verifier;

  setUpAll(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('every schema upgrade produces the expected schema', () {
    const versions = GeneratedHelper.versions;
    for (final (i, fromVersion) in versions.indexed) {
      group('from $fromVersion', () {
        for (final toVersion in versions.skip(i + 1)) {
          test('to $toVersion', () async {
            final schema = await verifier.schemaAt(fromVersion);
            final db = AppDatabase(schema.newConnection());
            await verifier.migrateAndValidate(db, toVersion);
            await db.close();
          });
        }
      });
    }
  });

  test('v1 → v2 keeps a populated database intact and usable', () async {
    final schema = await verifier.schemaAt(1);
    final old = v1.DatabaseAtV1(schema.newConnection());
    // A realistic v1 installation: settings, staff, menu, a billed order,
    // an open order and an open shift — written with raw SQL as v1 did.
    const now = 1759638600000; // 2025-10-05T04:30:00Z
    final statements = <String>[
      "INSERT INTO installation (singleton, installation_id, receipt_prefix, is_demo, created_at, created_by_app_version) VALUES (1, 'inst-1', 'OLD', 0, $now, '1.0.0')",
      "INSERT INTO sequences (name, next_value) VALUES ('receipt', 2), ('order', 3), ('kot', 1), ('refund', 1)",
      "INSERT INTO restaurant_settings (singleton, name, address, currency_code, time_zone, cutoff_minutes, receipt_footer, cashier_discount_limit_bps, service_charge_bps, delivery_charge_default, rounding_unit, lock_timeout_minutes, kot_show_prices, auto_print_receipt, auto_print_kot, backup_interval_hours, backup_retention, setup_completed_at, updated_at, version) "
          "VALUES (1, 'Old Café', 'Somewhere', 'INR', 'Asia/Kolkata', 240, 'Thanks', 1000, 0, 0, 0, 5, 0, 1, 1, 24, 14, $now, $now, 1)",
      "INSERT INTO staff (id, name, role, pin_hash, disabled, failed_attempts, created_at, updated_at) VALUES ('owner-1', 'Owner', 'owner', 'x', 0, 0, $now, $now)",
      "INSERT INTO categories (id, name, sort_order, archived, updated_at) VALUES ('cat-1', 'Coffee', 0, 0, $now)",
      "INSERT INTO menu_items (id, category_id, name, price, available, archived, sort_order, updated_at) VALUES ('item-1', 'cat-1', 'Coffee', 10000, 1, 0, 0, $now)",
      "INSERT INTO shifts (id, opened_by, opened_by_name, opened_at, opening_float, status, business_date) VALUES ('shift-1', 'owner-1', 'Owner', $now, 50000, 'open', '2025-10-05')",
      "INSERT INTO orders (id, order_no, order_type, status, created_by, created_by_name, created_at, updated_at, business_date, bill_discount_type, bill_discount_value, service_charge_bps, delivery_charge, rounding_unit, revision, finalized_at) "
          "VALUES ('order-1', 1, 'takeaway', 'finalized', 'owner-1', 'Owner', $now, $now, '2025-10-05', 'none', 0, 0, 0, 0, 2, $now)",
      "INSERT INTO order_lines (id, order_id, item_id, item_name, unit_price, modifiers_json, modifiers_unit_total, quantity, line_discount_type, line_discount_value, tax_json, revision, sort_order, created_by, created_at, updated_at) "
          "VALUES ('line-1', 'order-1', 'item-1', 'Coffee', 10000, '[]', 0, 2, 'none', 0, '{\"mode\":\"disabled\",\"rateBps\":0,\"components\":[]}', 1, 0, 'owner-1', $now, $now)",
      "INSERT INTO bills (id, receipt_no, receipt_seq, order_id, operation_id, order_no, order_type, business_date, local_hour, created_at, staff_id, staff_name, shift_id, item_count, items_gross_entered, discount_entered_total, items_gross_ex, items_discount_ex, items_net_ex, charges_net_ex, tax_total, subtotal_before_rounding, rounding_adjustment, total, change_total, currency_code, time_zone, restaurant_json) "
          "VALUES ('bill-1', 'OLD-000001', 1, 'order-1', 'finalize:op-1', 1, 'takeaway', '2025-10-05', 10, $now, 'owner-1', 'Owner', 'shift-1', 2, 20000, 0, 20000, 0, 20000, 0, 0, 20000, 0, 20000, 0, 'INR', 'Asia/Kolkata', '{\"name\":\"Old Café\",\"address\":\"Somewhere\",\"footer\":\"Thanks\"}')",
      "INSERT INTO bill_lines (id, bill_id, order_line_id, item_id, item_name, modifiers_json, quantity, unit_price_entered, gross_entered, line_discount_entered, bill_discount_entered, gross_ex, discount_ex, net_ex, tax_mode, tax_rate_bps, tax, total, sort_order) "
          "VALUES ('bl-1', 'bill-1', 'line-1', 'item-1', 'Coffee', '[]', 2, 10000, 20000, 0, 0, 20000, 0, 20000, 'disabled', 0, 0, 20000, 0)",
      "INSERT INTO payments (id, bill_id, method, applied, tendered, change_given, shift_id, business_date, created_at, confirmed_by, confirmed_by_name) "
          "VALUES ('pay-1', 'bill-1', 'cash', 20000, 20000, 0, 'shift-1', '2025-10-05', $now, 'owner-1', 'Owner')",
      "INSERT INTO orders (id, order_no, order_type, status, created_by, created_by_name, created_at, updated_at, business_date, bill_discount_type, bill_discount_value, service_charge_bps, delivery_charge, rounding_unit, revision) "
          "VALUES ('order-2', 2, 'dine_in', 'open', 'owner-1', 'Owner', $now, $now, '2025-10-05', 'none', 0, 0, 0, 0, 1)",
      "INSERT INTO order_lines (id, order_id, item_id, item_name, unit_price, modifiers_json, modifiers_unit_total, quantity, line_discount_type, line_discount_value, tax_json, revision, sort_order, created_by, created_at, updated_at) "
          "VALUES ('line-2', 'order-2', 'item-1', 'Coffee', 10000, '[]', 0, 1, 'none', 0, '{\"mode\":\"disabled\",\"rateBps\":0,\"components\":[]}', 1, 0, 'owner-1', $now, $now)",
    ];
    for (final s in statements) {
      await old.customStatement(s);
    }
    await old.close();

    final db = AppDatabase(schema.newConnection());
    // The app always runs the whole chain, so migrate to the latest schema.
    await verifier.migrateAndValidate(db, AppDatabase.latestSchemaVersion);

    final bills = await db.select(db.bills).get();
    expect(bills.single.receiptNo, 'OLD-000001');
    expect(bills.single.total, 20000);
    expect(bills.single.guestCount, isNull, reason: 'new column defaults to null');
    expect((await db.select(db.billLines).get()).single.netEx, 20000);
    expect((await db.select(db.payments).get()).single.applied, 20000);
    expect(await db.peekSequenceValue('receipt'), 2);
    final open = await (db.select(db.orders)..where((o) => o.status.equals('open'))).get();
    expect(open.single.id, 'order-2');

    // The migrated database works with today's services: bill the open order.
    final ctx = ServiceContext(db: db, clock: FixedClock(DateTime.utc(2025, 10, 5, 6)));
    const owner = Actor(staffId: 'owner-1', name: 'Owner', role: StaffRole.owner);
    await OrderService(ctx).updateDetails(owner, 'order-2', guestCount: 3);
    final r = await CheckoutService(ctx).finalize(
      owner,
      const FinalizeRequest(
        orderId: 'order-2',
        operationId: 'after-migration',
        tenders: [TenderInput(method: PaymentMethod.cash, applied: 10000)],
        paymentConfirmed: true,
      ),
    );
    expect(r.receiptNo, 'OLD-000002');
    final receipt = await BillService(ctx).receiptDocument(r.billId);
    expect(receipt.infoLines, contains('Guests: 3'));
    // The old receipt still reproduces from its snapshot.
    final oldReceipt = await BillService(ctx).receiptDocument('bill-1');
    expect(oldReceipt.restaurantName, 'Old Café');
    await db.close();
  });

  test('v2 → v3 keeps PIN-era staff and lets the owner get in with the recovery code', () async {
    const hasher = PasswordHasher.fastForTests();
    const code = 'ABCD-EFGH-JKLM-NPQR';
    final codeHash = await hasher.hash(PasswordHasher.normalizeRecoveryCode(code));
    final schema = await verifier.schemaAt(2);
    final old = v2.DatabaseAtV2(schema.newConnection());
    const now = 1759638600000;
    for (final s in <String>[
      "INSERT INTO installation (singleton, installation_id, receipt_prefix, is_demo, created_at, created_by_app_version) VALUES (1, 'inst-1', 'OLD', 0, $now, '1.0.0')",
      "INSERT INTO staff (id, name, role, pin_hash, disabled, failed_attempts, created_at, updated_at) VALUES ('owner-1', 'Owner', 'owner', 'old-pin-hash', 0, 0, $now, $now)",
      "INSERT INTO staff (id, name, role, pin_hash, disabled, failed_attempts, created_at, updated_at) VALUES ('cashier-1', 'Cashier', 'cashier', 'old-pin-hash', 0, 0, $now, $now)",
      "INSERT INTO owner_recovery (id, code_hash, created_by, created_at) VALUES ('rec-1', '$codeHash', 'owner-1', $now)",
    ]) {
      await old.customStatement(s);
    }
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, AppDatabase.latestSchemaVersion);
    final staff = await db.select(db.staff).get();
    expect(staff.length, 2);
    for (final s in staff) {
      expect(s.email, isNull);
      expect(s.passwordHash, isNull);
      expect(s.mustChangePassword, isFalse);
      expect(s.pinHash, 'old-pin-hash', reason: 'the migration does not rewrite old rows');
    }

    final ctx = ServiceContext(db: db, clock: FixedClock(DateTime.utc(2025, 10, 5, 6)));
    final auth = AuthService(ctx, hasher: hasher);
    await auth.resetOwnerPasswordWithRecoveryCode('owner-1', code, 'new-owner-pass', email: 'owner@old.cafe');
    final owner = await auth.login('owner@old.cafe', 'new-owner-pass');
    expect(owner.isOwner, isTrue);
    // The owner then gives the cashier an email and a starting password.
    await auth.updateStaff(owner, 'cashier-1', email: 'cashier@old.cafe');
    await auth.resetPassword(owner, 'cashier-1', 'start-pass-1');
    expect((await auth.login('cashier@old.cafe', 'start-pass-1')).mustChangePassword, isTrue);
    await db.close();
  });

  test('v3 → v4 (connected) keeps sales, open orders and tickets; new tables start empty', () async {
    final schema = await verifier.schemaAt(3);
    final old = v3.DatabaseAtV3(schema.newConnection());
    const now = 1759638600000;
    final statements = <String>[
      "INSERT INTO installation (singleton, installation_id, receipt_prefix, is_demo, created_at, created_by_app_version) VALUES (1, 'inst-1', 'OLD', 0, $now, '1.0.0')",
      "INSERT INTO sequences (name, next_value) VALUES ('receipt', 2), ('order', 3), ('kot', 2), ('refund', 1)",
      "INSERT INTO restaurant_settings (singleton, name, address, currency_code, time_zone, cutoff_minutes, receipt_footer, cashier_discount_limit_bps, service_charge_bps, delivery_charge_default, rounding_unit, lock_timeout_minutes, kot_show_prices, auto_print_receipt, auto_print_kot, backup_interval_hours, backup_retention, setup_completed_at, updated_at, version) "
          "VALUES (1, 'Old Café', 'Somewhere', 'INR', 'Asia/Kolkata', 240, 'Thanks', 1000, 0, 0, 0, 5, 0, 1, 1, 24, 14, $now, $now, 1)",
      "INSERT INTO staff (id, name, role, pin_hash, email, password_hash, must_change_password, disabled, failed_attempts, created_at, updated_at) VALUES ('owner-1', 'Owner', 'owner', '', 'owner@old.cafe', 'x', 0, 0, 0, $now, $now)",
      "INSERT INTO categories (id, name, sort_order, archived, updated_at) VALUES ('cat-1', 'Coffee', 0, 0, $now)",
      "INSERT INTO menu_items (id, category_id, name, price, available, archived, sort_order, updated_at) VALUES ('item-1', 'cat-1', 'Coffee', 10000, 1, 0, 0, $now)",
      "INSERT INTO shifts (id, opened_by, opened_by_name, opened_at, opening_float, status, business_date) VALUES ('shift-1', 'owner-1', 'Owner', $now, 50000, 'open', '2025-10-05')",
      "INSERT INTO orders (id, order_no, order_type, status, created_by, created_by_name, created_at, updated_at, business_date, bill_discount_type, bill_discount_value, service_charge_bps, delivery_charge, rounding_unit, revision, finalized_at) "
          "VALUES ('order-1', 1, 'takeaway', 'finalized', 'owner-1', 'Owner', $now, $now, '2025-10-05', 'none', 0, 0, 0, 0, 2, $now)",
      "INSERT INTO order_lines (id, order_id, item_id, item_name, unit_price, modifiers_json, modifiers_unit_total, quantity, line_discount_type, line_discount_value, tax_json, revision, sort_order, created_by, created_at, updated_at) "
          "VALUES ('line-1', 'order-1', 'item-1', 'Coffee', 10000, '[]', 0, 2, 'none', 0, '{\"mode\":\"disabled\",\"rateBps\":0,\"components\":[]}', 1, 0, 'owner-1', $now, $now)",
      "INSERT INTO bills (id, receipt_no, receipt_seq, order_id, operation_id, order_no, order_type, business_date, local_hour, created_at, staff_id, staff_name, shift_id, item_count, items_gross_entered, discount_entered_total, items_gross_ex, items_discount_ex, items_net_ex, charges_net_ex, tax_total, subtotal_before_rounding, rounding_adjustment, total, change_total, currency_code, time_zone, restaurant_json) "
          "VALUES ('bill-1', 'OLD-000001', 1, 'order-1', 'finalize:op-1', 1, 'takeaway', '2025-10-05', 10, $now, 'owner-1', 'Owner', 'shift-1', 2, 20000, 0, 20000, 0, 20000, 0, 0, 20000, 0, 20000, 0, 'INR', 'Asia/Kolkata', '{\"name\":\"Old Café\",\"address\":\"Somewhere\",\"footer\":\"Thanks\"}')",
      "INSERT INTO payments (id, bill_id, method, applied, tendered, change_given, shift_id, business_date, created_at, confirmed_by, confirmed_by_name) "
          "VALUES ('pay-1', 'bill-1', 'cash', 20000, 20000, 0, 'shift-1', '2025-10-05', $now, 'owner-1', 'Owner')",
      "INSERT INTO orders (id, order_no, order_type, status, created_by, created_by_name, created_at, updated_at, business_date, bill_discount_type, bill_discount_value, service_charge_bps, delivery_charge, rounding_unit, revision) "
          "VALUES ('order-2', 2, 'takeaway', 'open', 'owner-1', 'Owner', $now, $now, '2025-10-05', 'none', 0, 0, 0, 0, 3)",
      "INSERT INTO order_lines (id, order_id, item_id, item_name, unit_price, modifiers_json, modifiers_unit_total, quantity, line_discount_type, line_discount_value, tax_json, revision, sort_order, created_by, created_at, updated_at) "
          "VALUES ('line-2', 'order-2', 'item-1', 'Coffee', 10000, '[]', 0, 1, 'none', 0, '{\"mode\":\"disabled\",\"rateBps\":0,\"components\":[]}', 1, 0, 'owner-1', $now, $now)",
      "INSERT INTO kitchen_tickets (id, order_id, ticket_no, kind, status, operation_id, order_ref, created_by, created_by_name, created_at, updated_at) "
          "VALUES ('kt-1', 'order-2', 1, 'order', 'preparing', 'kot:op-2', 'Takeaway #2', 'owner-1', 'Owner', $now, $now)",
      "INSERT INTO kitchen_ticket_lines (id, ticket_id, order_line_id, order_line_revision, item_name, quantity_delta, unit_price) "
          "VALUES ('ktl-1', 'kt-1', 'line-2', 1, 'Coffee', 1, 10000)",
    ];
    for (final s in statements) {
      await old.customStatement(s);
    }
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, AppDatabase.latestSchemaVersion);

    // Historical financial values are untouched.
    final bill = await db.select(db.bills).getSingle();
    expect((bill.receiptNo, bill.total, bill.businessDate), ('OLD-000001', 20000, '2025-10-05'));
    expect((await db.select(db.payments).getSingle()).applied, 20000);
    // Existing tickets start at revision 1 and keep their status.
    final ticket = await db.select(db.kitchenTickets).getSingle();
    expect((ticket.status, ticket.revision), ('preparing', 1));
    // Connected tables exist and are empty until the owner sets up devices.
    expect(await db.select(db.hostIdentity).get(), isEmpty);
    expect(await db.select(db.pairedDevices).get(), isEmpty);
    expect(await db.select(db.hostEvents).get(), isEmpty);
    expect(await db.select(db.commandReceipts).get(), isEmpty);

    // Today's services work on the upgraded database and start the outbox at 1.
    final ctx = ServiceContext(db: db, clock: FixedClock(DateTime.utc(2025, 10, 5, 6)));
    const owner = Actor(staffId: 'owner-1', name: 'Owner', role: StaffRole.owner);
    await OrderService(ctx).setTicketStatus(owner, 'kt-1', TicketStatus.ready);
    final events = await db.select(db.hostEvents).get();
    expect(events.single.sequence, 1);
    expect(events.single.revision, 2);
    expect((await db.select(db.kitchenTickets).getSingle()).revision, 2);
    await db.close();
  });

  test('v4 → v5 keeps the settings and turns the kitchen on by default', () async {
    final schema = await verifier.schemaAt(4);
    final old = v4.DatabaseAtV4(schema.newConnection());
    const now = 1760000000000;
    await old.customStatement(
      "INSERT INTO restaurant_settings (singleton, name, address, currency_code, time_zone, cutoff_minutes, receipt_footer, cashier_discount_limit_bps, service_charge_bps, delivery_charge_default, rounding_unit, lock_timeout_minutes, kot_show_prices, auto_print_receipt, auto_print_kot, backup_interval_hours, backup_retention, setup_completed_at, updated_at, version) "
      "VALUES (1, 'Old Café', 'Somewhere', 'INR', 'Asia/Kolkata', 240, 'Thanks', 1500, 500, 0, 0, 7, 1, 1, 0, 24, 14, $now, $now, 3)",
    );
    await old.close();

    final db = AppDatabase(schema.newConnection());
    await verifier.migrateAndValidate(db, 5);
    final s = await db.select(db.restaurantSettings).getSingle();
    expect(
      (s.name, s.cashierDiscountLimitBps, s.lockTimeoutMinutes, s.autoPrintKot, s.version),
      (
        'Old Café',
        1500,
        7,
        false,
        3,
      ),
    );
    expect(s.kitchenEnabled, isTrue, reason: 'existing cafés keep their kitchen');
    await db.close();
  });
}
