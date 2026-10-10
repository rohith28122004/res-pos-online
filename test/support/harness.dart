import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/security/pin_hasher.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/auth/application/auth_service.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/checkout/application/checkout_service.dart';
import 'package:cafedesk/features/menu/application/menu_service.dart';
import 'package:cafedesk/features/orders/application/order_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/settings/application/settings_service.dart';
import 'package:cafedesk/features/setup/application/setup_service.dart';
import 'package:cafedesk/features/shifts/application/shift_service.dart';
import 'package:drift/drift.dart';

const ownerPin = '4826';
const cashierPin = '7391';
const fastHasher = PinHasher.fastForTests();

const gst5Components = [TaxComponentRate(name: 'CGST', rateBps: 250), TaxComponentRate(name: 'SGST', rateBps: 250)];

/// An in-memory installation built through the real services.
class Harness {
  Harness._(this.db, this.clock, this.ctx);

  final AppDatabase db;
  final FixedClock clock;
  final ServiceContext ctx;
  late Actor owner;
  late Actor cashier;
  late Actor kitchen;

  AuthService get auth => AuthService(ctx, hasher: fastHasher);
  OrderService get orders => OrderService(ctx);
  CheckoutService get checkout => CheckoutService(ctx);
  MenuService get menu => MenuService(ctx);
  SettingsService get settings => SettingsService(ctx);
  ShiftService get shifts => ShiftService(ctx);

  static Future<Harness> create({DateTime? start, AppDatabase? database}) async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    final db = database ?? openInMemoryDatabase();
    final clock = FixedClock(start ?? DateTime.utc(2026, 10, 5, 3, 30)); // 09:00 IST
    final ctx = ServiceContext(db: db, clock: clock);
    final h = Harness._(db, clock, ctx);
    final result = await SetupService(ctx, hasher: fastHasher).completeSetup(
      const SetupInput(
        restaurantName: 'Test Café',
        address: '1 Main Road',
        ownerName: 'Olivia Owner',
        ownerPin: ownerPin,
        receiptPrefix: 'TST',
      ),
    );
    h.owner = result.owner;
    final cashierId = await h.auth.createStaff(h.owner, name: 'Cara Cashier', role: StaffRole.cashier, pin: cashierPin);
    h.cashier = Actor(staffId: cashierId, name: 'Cara Cashier', role: StaffRole.cashier);
    final kitchenId = await h.auth.createStaff(h.owner, name: 'Ken Kitchen', role: StaffRole.kitchen, pin: '5927');
    h.kitchen = Actor(staffId: kitchenId, name: 'Ken Kitchen', role: StaffRole.kitchen);
    return h;
  }

  Future<OwnerApproval> approval() async {
    final owners = await auth.activeOwners();
    return auth.approveAsOwner(owners.first.id, ownerPin);
  }

  Future<String> taxProfile(
    String name,
    TaxMode mode, {
    int rateBps = 500,
    List<TaxComponentRate> components = gst5Components,
  }) => settings.createTaxProfile(
    owner,
    TaxProfileInput(name: name, mode: mode, rateBps: rateBps, components: components),
  );

  Future<String> category(String name) => menu.createCategory(owner, name);

  Future<String> item(
    String categoryId,
    String name,
    int price, {
    String? taxProfileId,
    List<VariantInput> variants = const [],
    List<ModifierInput> modifiers = const [],
  }) => menu.saveItem(
    owner,
    ItemInput(
      categoryId: categoryId,
      name: name,
      price: price,
      taxProfileId: taxProfileId,
      variants: variants,
      modifiers: modifiers,
    ),
  );

  Future<String> openShift({int float = 100000}) => shifts.openShift(cashier, openingFloat: float);

  /// Creates an order with [items] (itemId → quantity) and returns its id.
  Future<String> orderWith(
    Map<String, int> items, {
    OrderType type = OrderType.takeaway,
    String? tableId,
    Actor? actor,
  }) async {
    final a = actor ?? cashier;
    final id = await orders.createOrder(a, type: type, tableId: tableId);
    for (final e in items.entries) {
      await orders.addItem(a, id, itemId: e.key, quantity: e.value);
    }
    return id;
  }

  Future<FinalizeResult> pay(
    String orderId,
    List<TenderInput> tenders, {
    Actor? actor,
    String? operationId,
    OwnerApproval? approval,
  }) {
    return checkout.finalize(
      actor ?? cashier,
      FinalizeRequest(
        orderId: orderId,
        operationId: operationId ?? ctx.ids.newId(),
        tenders: tenders,
        paymentConfirmed: true,
        approval: approval,
      ),
    );
  }

  Future<int> count(TableInfo<Table, Object?> table) async {
    final c = countAll();
    final q = db.selectOnly(table)..addColumns([c]);
    return (await q.getSingle()).read(c)!;
  }

  /// Moves the fixed clock to a local IST wall-clock time.
  void setIst(int year, int month, int day, int hour, [int minute = 0]) {
    clock.set(DateTime.utc(year, month, day, hour, minute).subtract(const Duration(hours: 5, minutes: 30)));
  }

  Future<void> dispose() => db.close();
}
