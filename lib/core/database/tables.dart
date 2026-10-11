// Drift table definitions. Conventions:
//  * ids are UUID text; human numbers (receipts, orders, KOTs) come from
//    `sequences` inside the same transaction that uses them
//  * money is INTEGER minor units (paise); rates are basis points
//  * timestamps are INTEGER UTC epoch milliseconds; financial rows also carry a
//    `business_date` key (YYYY-MM-DD) computed when the row was created
//  * bills, bill lines, payments, refunds and kitchen tickets are append-only;
//    services never UPDATE or DELETE them (except kitchen ticket status)
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';

@DataClassName('InstallationRow')
class Installation extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get installationId => text()();
  TextColumn get receiptPrefix => text()();
  BoolColumn get isDemo => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  TextColumn get createdByAppVersion => text()();

  @override
  Set<Column> get primaryKey => {singleton};
}

@DataClassName('SequenceRow')
class Sequences extends Table {
  TextColumn get name => text()();
  IntColumn get nextValue => integer().check(nextValue.isBiggerThanValue(0))();

  @override
  Set<Column> get primaryKey => {name};
}

@DataClassName('RestaurantSettingsRow')
class RestaurantSettings extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get name => text()();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get phone => text().nullable()();
  TextColumn get taxRegistrationId => text().nullable()();
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  TextColumn get timeZone => text().withDefault(const Constant('Asia/Kolkata'))();
  IntColumn get cutoffMinutes => integer().withDefault(const Constant(240))();
  TextColumn get receiptHeader => text().nullable()();
  TextColumn get receiptFooter => text().withDefault(const Constant('Thank you! Visit again.'))();
  IntColumn get cashierDiscountLimitBps => integer().withDefault(const Constant(1000))();
  IntColumn get serviceChargeBps => integer().withDefault(const Constant(0))();
  TextColumn get serviceChargeTaxProfileId => text().nullable()();
  IntColumn get deliveryChargeDefault => integer().withDefault(const Constant(0))();
  TextColumn get deliveryChargeTaxProfileId => text().nullable()();
  IntColumn get roundingUnit => integer().withDefault(const Constant(0))();
  IntColumn get lockTimeoutMinutes => integer().withDefault(const Constant(5))();
  BoolColumn get kotShowPrices => boolean().withDefault(const Constant(false))();
  BoolColumn get autoPrintReceipt => boolean().withDefault(const Constant(true))();
  BoolColumn get autoPrintKot => boolean().withDefault(const Constant(true))();

  /// Off when the café has no kitchen: no kitchen screen, and waiters prepare
  /// and mark orders ready themselves (schema v5).
  BoolColumn get kitchenEnabled => boolean().withDefault(const Constant(true))();
  TextColumn get backupDirectory => text().nullable()();
  IntColumn get backupIntervalHours => integer().withDefault(const Constant(24))();
  IntColumn get backupRetention => integer().withDefault(const Constant(14))();
  IntColumn get lastBackupAt => integer().nullable()();
  IntColumn get setupCompletedAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {singleton};
}

@DataClassName('StaffRow')
@TableIndex(name: 'staff_email', columns: {#email}, unique: true)
class Staff extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text()();

  /// Schema 1–2 signed in with PINs. Unused since v3 (email + password); empty
  /// for new accounts and cleared when a password is set.
  TextColumn get pinHash => text().clientDefault(() => '')();

  /// Trimmed, lower-case sign-in email. Null only on accounts from before v3
  /// until the owner gives them one.
  TextColumn get email => text().nullable()();

  /// Argon2id hash of the password. Null = cannot sign in yet.
  TextColumn get passwordHash => text().nullable()();

  /// Set when the owner chose the password; the person must pick their own
  /// at the next sign-in.
  BoolColumn get mustChangePassword => boolean().withDefault(const Constant(false))();
  BoolColumn get disabled => boolean().withDefault(const Constant(false))();
  IntColumn get failedAttempts => integer().withDefault(const Constant(0))();
  IntColumn get lockedUntil => integer().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OwnerRecoveryRow')
class OwnerRecovery extends Table {
  TextColumn get id => text()();
  TextColumn get codeHash => text()();
  TextColumn get createdBy => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get usedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('TaxProfileRow')
class TaxProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get mode => text()();
  IntColumn get rateBps => integer().check(rateBps.isBetweenValues(0, 10000))();
  TextColumn get componentsJson => text().withDefault(const Constant('[]'))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CategoryRow')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MenuItemRow')
@TableIndex(name: 'menu_items_category', columns: {#categoryId})
class MenuItems extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text().references(Categories, #id)();
  TextColumn get name => text()();
  IntColumn get price => integer().check(price.isBiggerOrEqualValue(0))();
  TextColumn get taxProfileId => text().nullable().references(TaxProfiles, #id)();
  BoolColumn get available => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get sku => text().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ItemVariantRow')
@TableIndex(name: 'item_variants_item', columns: {#itemId})
class ItemVariants extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(MenuItems, #id)();
  TextColumn get name => text()();
  IntColumn get price => integer().check(price.isBiggerOrEqualValue(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ItemModifierRow')
@TableIndex(name: 'item_modifiers_item', columns: {#itemId})
class ItemModifiers extends Table {
  TextColumn get id => text()();
  TextColumn get itemId => text().references(MenuItems, #id)();
  TextColumn get name => text()();
  IntColumn get price => integer().check(price.isBiggerOrEqualValue(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('DiningTableRow')
class DiningTables extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get capacity => integer().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OrderRow')
@TableIndex(name: 'orders_status', columns: {#status})
@TableIndex.sql(
  "CREATE UNIQUE INDEX orders_one_open_per_table ON orders (table_id) WHERE status = 'open' AND table_id IS NOT NULL",
)
class Orders extends Table {
  TextColumn get id => text()();
  IntColumn get orderNo => integer()();
  TextColumn get orderType => text()();
  TextColumn get tableId => text().nullable().references(DiningTables, #id)();
  TextColumn get tableLabel => text().nullable()();
  TextColumn get status => text()();
  TextColumn get createdBy => text().references(Staff, #id)();
  TextColumn get createdByName => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  TextColumn get businessDate => text()();
  TextColumn get customerName => text().nullable()();

  /// Added in schema v2: covers for dine-in orders (optional).
  IntColumn get guestCount => integer().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get billDiscountType => text().withDefault(const Constant('none'))();
  IntColumn get billDiscountValue => integer().withDefault(const Constant(0))();
  TextColumn get discountReason => text().nullable()();
  TextColumn get discountApprovedBy => text().nullable()();
  IntColumn get serviceChargeBps => integer().withDefault(const Constant(0))();
  TextColumn get serviceChargeTaxJson => text().nullable()();
  IntColumn get deliveryCharge => integer().withDefault(const Constant(0))();
  TextColumn get deliveryChargeTaxJson => text().nullable()();
  IntColumn get roundingUnit => integer().withDefault(const Constant(0))();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get cancelledAt => integer().nullable()();
  TextColumn get cancelledBy => text().nullable()();
  TextColumn get cancelReason => text().nullable()();
  TextColumn get cancelBusinessDate => text().nullable()();
  IntColumn get finalizedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('OrderLineRow')
@TableIndex(name: 'order_lines_order', columns: {#orderId})
class OrderLines extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  TextColumn get itemId => text().nullable().references(MenuItems, #id)();
  TextColumn get categoryId => text().nullable()();
  TextColumn get categoryName => text().nullable()();
  TextColumn get itemName => text()();
  TextColumn get variantId => text().nullable()();
  TextColumn get variantName => text().nullable()();
  IntColumn get unitPrice => integer().check(unitPrice.isBiggerOrEqualValue(0))();
  TextColumn get modifiersJson => text().withDefault(const Constant('[]'))();
  IntColumn get modifiersUnitTotal => integer().withDefault(const Constant(0))();
  IntColumn get quantity => integer().check(quantity.isBiggerOrEqualValue(0))();
  TextColumn get note => text().nullable()();
  TextColumn get lineDiscountType => text().withDefault(const Constant('none'))();
  IntColumn get lineDiscountValue => integer().withDefault(const Constant(0))();
  TextColumn get taxJson => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  TextColumn get createdBy => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('KitchenTicketRow')
@TableIndex(name: 'kitchen_tickets_order', columns: {#orderId})
@TableIndex(name: 'kitchen_tickets_status', columns: {#status})
class KitchenTickets extends Table {
  TextColumn get id => text()();
  TextColumn get orderId => text().references(Orders, #id)();
  IntColumn get ticketNo => integer()();
  TextColumn get kind => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get status => text()();
  TextColumn get operationId => text().nullable().unique()();
  TextColumn get orderRef => text()();
  TextColumn get tableLabel => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get createdByName => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  /// Added in schema v4: bumped on every status change, so a queued remote
  /// status update with an older revision is refused instead of regressing.
  IntColumn get revision => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('KitchenTicketLineRow')
@TableIndex(name: 'kitchen_ticket_lines_ticket', columns: {#ticketId})
@TableIndex(name: 'kitchen_ticket_lines_order_line', columns: {#orderLineId})
class KitchenTicketLines extends Table {
  TextColumn get id => text()();
  TextColumn get ticketId => text().references(KitchenTickets, #id)();
  TextColumn get orderLineId => text().references(OrderLines, #id)();
  IntColumn get orderLineRevision => integer()();
  TextColumn get itemName => text()();
  TextColumn get variantName => text().nullable()();
  TextColumn get modifiersText => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get quantityDelta => integer().check(quantityDelta.equals(0).not())();
  IntColumn get unitPrice => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ShiftRow')
@TableIndex.sql("CREATE UNIQUE INDEX shifts_one_open ON shifts (status) WHERE status = 'open'")
class Shifts extends Table {
  TextColumn get id => text()();
  TextColumn get openedBy => text().references(Staff, #id)();
  TextColumn get openedByName => text()();
  IntColumn get openedAt => integer()();
  IntColumn get openingFloat => integer().check(openingFloat.isBiggerOrEqualValue(0))();
  TextColumn get status => text()();
  TextColumn get businessDate => text()();
  IntColumn get lastClosedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ShiftClosureRow')
@TableIndex(name: 'shift_closures_shift', columns: {#shiftId})
class ShiftClosures extends Table {
  TextColumn get id => text()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get closedBy => text()();
  TextColumn get closedByName => text()();
  IntColumn get closedAt => integer()();
  IntColumn get countedCash => integer()();
  IntColumn get expectedCash => integer()();
  IntColumn get variance => integer()();
  TextColumn get summaryJson => text()();
  TextColumn get note => text().nullable()();
  IntColumn get carriedOpenOrders => integer().withDefault(const Constant(0))();
  TextColumn get approvedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CashMovementRow')
@TableIndex(name: 'cash_movements_shift', columns: {#shiftId})
@TableIndex(name: 'cash_movements_date', columns: {#businessDate})
class CashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get direction => text()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get reason => text()();
  TextColumn get createdBy => text()();
  TextColumn get createdByName => text()();
  IntColumn get createdAt => integer()();
  TextColumn get businessDate => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BillRow')
@TableIndex(name: 'bills_business_date', columns: {#businessDate})
@TableIndex(name: 'bills_shift', columns: {#shiftId})
@TableIndex(name: 'bills_created_at', columns: {#createdAt})
@TableIndex(name: 'bills_type_date', columns: {#orderType, #businessDate})
class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get receiptNo => text().unique()();
  IntColumn get receiptSeq => integer()();
  TextColumn get orderId => text().unique().references(Orders, #id)();
  TextColumn get operationId => text().unique()();
  IntColumn get orderNo => integer()();
  TextColumn get orderType => text()();
  TextColumn get tableLabel => text().nullable()();
  TextColumn get customerName => text().nullable()();

  /// Added in schema v2.
  IntColumn get guestCount => integer().nullable()();
  TextColumn get businessDate => text()();
  IntColumn get localHour => integer()();
  IntColumn get createdAt => integer()();
  TextColumn get staffId => text()();
  TextColumn get staffName => text()();
  TextColumn get shiftId => text().references(Shifts, #id)();
  IntColumn get itemCount => integer()();
  IntColumn get itemsGrossEntered => integer()();
  IntColumn get discountEnteredTotal => integer()();
  IntColumn get itemsGrossEx => integer()();
  IntColumn get itemsDiscountEx => integer()();
  IntColumn get itemsNetEx => integer()();
  IntColumn get chargesNetEx => integer()();
  IntColumn get taxTotal => integer()();
  IntColumn get subtotalBeforeRounding => integer()();
  IntColumn get roundingAdjustment => integer()();
  IntColumn get total => integer().check(total.isBiggerOrEqualValue(0))();
  IntColumn get changeTotal => integer()();
  TextColumn get discountReason => text().nullable()();
  TextColumn get discountApprovedBy => text().nullable()();
  TextColumn get currencyCode => text()();
  TextColumn get timeZone => text()();
  TextColumn get restaurantJson => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BillLineRow')
@TableIndex(name: 'bill_lines_bill', columns: {#billId})
@TableIndex(name: 'bill_lines_item', columns: {#itemId})
class BillLines extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get orderLineId => text().references(OrderLines, #id)();
  TextColumn get itemId => text().nullable()();
  TextColumn get itemName => text()();
  TextColumn get variantName => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get categoryName => text().nullable()();
  TextColumn get modifiersJson => text()();
  TextColumn get note => text().nullable()();
  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();
  IntColumn get unitPriceEntered => integer()();
  IntColumn get grossEntered => integer()();
  IntColumn get lineDiscountEntered => integer()();
  IntColumn get billDiscountEntered => integer()();
  IntColumn get grossEx => integer()();
  IntColumn get discountEx => integer()();
  IntColumn get netEx => integer()();
  TextColumn get taxMode => text()();
  IntColumn get taxRateBps => integer()();
  IntColumn get tax => integer()();
  IntColumn get total => integer()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BillChargeRow')
@TableIndex(name: 'bill_charges_bill', columns: {#billId})
class BillCharges extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get kind => text()();
  TextColumn get label => text()();
  IntColumn get amountEntered => integer()();
  IntColumn get netEx => integer()();
  TextColumn get taxMode => text()();
  IntColumn get taxRateBps => integer()();
  IntColumn get tax => integer()();
  IntColumn get total => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BillTaxComponentRow')
@TableIndex(name: 'bill_tax_components_bill', columns: {#billId})
class BillTaxComponents extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get billLineId => text().nullable().references(BillLines, #id)();
  TextColumn get billChargeId => text().nullable().references(BillCharges, #id)();
  TextColumn get name => text()();
  IntColumn get rateBps => integer()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PaymentRow')
@TableIndex(name: 'payments_bill', columns: {#billId})
@TableIndex(name: 'payments_date_method', columns: {#businessDate, #method})
@TableIndex(name: 'payments_shift', columns: {#shiftId})
class Payments extends Table {
  TextColumn get id => text()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get method => text()();
  IntColumn get applied => integer().check(applied.isBiggerThanValue(0))();
  IntColumn get tendered => integer()();
  IntColumn get changeGiven => integer().check(changeGiven.isBiggerOrEqualValue(0))();
  TextColumn get shiftId => text().references(Shifts, #id)();
  TextColumn get businessDate => text()();
  IntColumn get createdAt => integer()();
  TextColumn get confirmedBy => text()();
  TextColumn get confirmedByName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefundRow')
@TableIndex(name: 'refunds_bill', columns: {#billId})
@TableIndex(name: 'refunds_business_date', columns: {#businessDate})
class Refunds extends Table {
  TextColumn get id => text()();
  TextColumn get refundNo => text().unique()();
  TextColumn get billId => text().references(Bills, #id)();
  TextColumn get operationId => text().unique()();
  TextColumn get reason => text()();
  TextColumn get authorizedBy => text()();
  TextColumn get authorizedByName => text()();
  TextColumn get createdBy => text()();
  TextColumn get createdByName => text()();
  IntColumn get createdAt => integer()();
  TextColumn get businessDate => text()();
  IntColumn get localHour => integer()();
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();
  IntColumn get itemsGrossEx => integer()();
  IntColumn get itemsDiscountEx => integer()();
  IntColumn get itemsNetEx => integer()();
  IntColumn get chargesNetEx => integer()();
  IntColumn get taxTotal => integer()();
  IntColumn get roundingAdjustment => integer()();
  IntColumn get total => integer().check(total.isBiggerThanValue(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefundLineRow')
@TableIndex(name: 'refund_lines_refund', columns: {#refundId})
@TableIndex(name: 'refund_lines_bill_line', columns: {#billLineId})
class RefundLines extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get billLineId => text().references(BillLines, #id)();
  IntColumn get quantity => integer().check(quantity.isBiggerThanValue(0))();
  IntColumn get grossEx => integer()();
  IntColumn get discountEx => integer()();
  IntColumn get netEx => integer()();
  IntColumn get tax => integer()();
  IntColumn get total => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefundChargeRow')
@TableIndex(name: 'refund_charges_refund', columns: {#refundId})
class RefundCharges extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get billChargeId => text().references(BillCharges, #id)();
  IntColumn get netEx => integer()();
  IntColumn get tax => integer()();
  IntColumn get total => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefundTaxComponentRow')
@TableIndex(name: 'refund_tax_components_refund', columns: {#refundId})
class RefundTaxComponents extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get sourceComponentId => text().references(BillTaxComponents, #id)();
  TextColumn get refundLineId => text().nullable().references(RefundLines, #id)();
  TextColumn get refundChargeId => text().nullable().references(RefundCharges, #id)();
  TextColumn get name => text()();
  IntColumn get rateBps => integer()();
  IntColumn get amount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('RefundPaymentRow')
@TableIndex(name: 'refund_payments_refund', columns: {#refundId})
@TableIndex(name: 'refund_payments_date_method', columns: {#businessDate, #method})
class RefundPayments extends Table {
  TextColumn get id => text()();
  TextColumn get refundId => text().references(Refunds, #id)();
  TextColumn get method => text()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();
  TextColumn get businessDate => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('ExpenseRow')
@TableIndex(name: 'expenses_business_date', columns: {#businessDate})
@TableIndex(name: 'expenses_shift', columns: {#shiftId})
class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get category => text()();
  IntColumn get amount => integer().check(amount.isBiggerThanValue(0))();
  TextColumn get note => text().nullable()();
  TextColumn get createdBy => text()();
  TextColumn get createdByName => text()();
  IntColumn get createdAt => integer()();
  TextColumn get businessDate => text()();
  BoolColumn get paidFromDrawer => boolean()();
  TextColumn get shiftId => text().nullable().references(Shifts, #id)();
  IntColumn get voidedAt => integer().nullable()();
  TextColumn get voidedBy => text().nullable()();
  TextColumn get voidReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PrinterProfileRow')
class PrinterProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get role => text()();
  IntColumn get paperWidthMm => integer()();
  IntColumn get dotsWidth => integer()();
  IntColumn get charsPerLine => integer()();
  TextColumn get codePage => text()();
  TextColumn get renderMode => text()();
  TextColumn get cutter => text()();
  BoolColumn get drawerPulse => boolean().withDefault(const Constant(false))();
  TextColumn get transport => text()();
  TextColumn get endpoint => text()();
  IntColumn get port => integer().nullable()();
  IntColumn get timeoutMs => integer().withDefault(const Constant(8000))();
  IntColumn get feedLines => integer().withDefault(const Constant(3))();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PrintJobRow')
@TableIndex(name: 'print_jobs_state_printer', columns: {#state, #printerProfileId})
@TableIndex(name: 'print_jobs_created_at', columns: {#createdAt})
class PrintJobs extends Table {
  TextColumn get id => text()();
  TextColumn get printerProfileId => text().references(PrinterProfiles, #id)();
  TextColumn get documentType => text()();
  TextColumn get documentRef => text().nullable()();
  TextColumn get payloadJson => text()();
  TextColumn get copyLabel => text().nullable()();
  TextColumn get state => text()();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  TextColumn get createdBy => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PrintAttemptRow')
@TableIndex(name: 'print_attempts_job', columns: {#jobId})
class PrintAttempts extends Table {
  TextColumn get id => text()();
  TextColumn get jobId => text().references(PrintJobs, #id)();
  IntColumn get startedAt => integer()();
  IntColumn get finishedAt => integer().nullable()();
  TextColumn get outcome => text().nullable()();
  TextColumn get error => text().nullable()();
  IntColumn get byteCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('AuditEventRow')
@TableIndex(name: 'audit_events_at', columns: {#at})
@TableIndex(name: 'audit_events_action', columns: {#action})
class AuditEvents extends Table {
  TextColumn get id => text()();
  IntColumn get at => integer()();
  TextColumn get actorId => text().nullable()();
  TextColumn get actorName => text().nullable()();
  TextColumn get action => text()();
  TextColumn get entityType => text().nullable()();
  TextColumn get entityId => text().nullable()();
  TextColumn get detailsJson => text().nullable()();
  TextColumn get approvedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CompletedOperationRow')
class CompletedOperations extends Table {
  TextColumn get operationKey => text()();
  TextColumn get kind => text()();
  TextColumn get resultId => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {operationKey};
}

// ---- Connected mode (schema v4) ---------------------------------------------
// The POS host's identity, paired devices, staff sessions, command receipts and
// the event outbox. See docs/PROTOCOL.md and docs/CONNECTED_ARCHITECTURE.md.

/// One row: who this POS host is to its paired devices and the cloud. Keys and
/// credentials are NOT here — private keys and the cloud credential live in the
/// operating system's secure storage.
@DataClassName('HostIdentityRow')
class HostIdentity extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get restaurantId => text()();
  TextColumn get hostDeviceId => text()();

  /// Starts at 1; +1 after every restore so stale commands and duplicate
  /// uploads from before the restore can never be applied.
  IntColumn get hostEpoch => integer()();

  /// First event sequence of the current epoch.
  IntColumn get epochStartSequence => integer()();
  IntColumn get epochStartedAt => integer()();

  /// Self-signed TLS certificate (PEM) and the SHA-256 of its DER, which
  /// devices pin at pairing.
  TextColumn get tlsCertPem => text()();
  TextColumn get tlsCertSha256 => text()();

  /// Public halves of the host keys (b64url). Private halves: secure storage.
  TextColumn get signingPublicKey => text()();
  TextColumn get sealPublicKey => text()();
  IntColumn get lanPort => integer().withDefault(const Constant(47821))();
  BoolColumn get lanEnabled => boolean().withDefault(const Constant(false))();

  /// Cloud relay URL once enrolled; null = not enrolled.
  TextColumn get cloudUrl => text().nullable()();
  IntColumn get cloudEnrolledAt => integer().nullable()();

  /// Set after a restore: devices and the cloud stay disconnected until the
  /// owner reconnects (new epoch registered, old queued work quarantined).
  BoolColumn get reconcileRequired => boolean().withDefault(const Constant(false))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {singleton};
}

/// Waiter and kitchen devices paired with this host.
@DataClassName('PairedDeviceRow')
class PairedDevices extends Table {
  TextColumn get id => text()();
  TextColumn get role => text()();
  TextColumn get name => text()();
  TextColumn get platform => text().nullable()();
  TextColumn get appVersion => text().nullable()();

  /// sha256hex of the device credential; the credential itself is only on the
  /// device.
  TextColumn get credentialHash => text().unique()();
  IntColumn get createdAt => integer()();
  TextColumn get pairedBy => text()();
  TextColumn get pairedByName => text()();
  IntColumn get lastSeenAt => integer().nullable()();
  IntColumn get revokedAt => integer().nullable()();
  TextColumn get revokedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Short-lived, single-use pairing codes (hashed).
@DataClassName('PairingCodeRow')
class PairingCodes extends Table {
  TextColumn get id => text()();
  TextColumn get codeHash => text().unique()();
  TextColumn get role => text()();
  TextColumn get deviceName => text()();
  TextColumn get createdBy => text()();
  IntColumn get createdAt => integer()();
  IntColumn get expiresAt => integer()();
  IntColumn get usedAt => integer().nullable()();
  TextColumn get usedByDeviceId => text().nullable()();
  IntColumn get cancelledAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Staff signed in on a paired device. The token is host-signed; this row lets
/// the host revoke it and check it is still live.
@DataClassName('StaffSessionRow')
@TableIndex(name: 'staff_sessions_staff', columns: {#staffId})
@TableIndex(name: 'staff_sessions_device', columns: {#deviceId})
class StaffSessions extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text().references(Staff, #id)();
  TextColumn get deviceId => text().references(PairedDevices, #id)();
  IntColumn get createdAt => integer()();
  IntColumn get expiresAt => integer()();
  IntColumn get lastSeenAt => integer().nullable()();
  IntColumn get revokedAt => integer().nullable()();
  TextColumn get revokedReason => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Every remote command the host decided, with the hash of its exact body.
/// Written in the same transaction as the business change.
@DataClassName('CommandReceiptRow')
@TableIndex(name: 'command_receipts_received', columns: {#receivedAt})
class CommandReceipts extends Table {
  TextColumn get commandId => text()();
  TextColumn get bodyHash => text()();
  TextColumn get action => text()();
  TextColumn get deviceId => text()();
  TextColumn get staffId => text()();
  IntColumn get hostEpoch => integer()();
  TextColumn get state => text()();
  TextColumn get resultJson => text()();
  IntColumn get receivedAt => integer()();

  @override
  Set<Column> get primaryKey => {commandId};
}

/// The event outbox: one row per committed change, written in the same
/// transaction. Gap-free sequence per epoch. Immutable once written.
@DataClassName('HostEventRow')
@TableIndex(name: 'host_events_event_id', columns: {#eventId}, unique: true)
@TableIndex(name: 'host_events_cloud_pending', columns: {#cloudAckedAt})
class HostEvents extends Table {
  IntColumn get hostEpoch => integer()();
  IntColumn get sequence => integer()();
  TextColumn get eventId => text()();
  TextColumn get type => text()();
  TextColumn get aggregateType => text()();
  TextColumn get aggregateId => text()();
  IntColumn get revision => integer()();
  IntColumn get committedAt => integer()();
  TextColumn get businessDate => text().nullable()();

  /// 'devices' (devices + cloud) or 'cloud' (cloud only).
  TextColumn get audience => text()();

  /// The complete event envelope, canonical JSON.
  TextColumn get eventJson => text()();
  TextColumn get contentHash => text()();
  IntColumn get cloudAckedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {hostEpoch, sequence};
}

/// Progress markers for background sync work (e.g. cloud upload cursor).
@DataClassName('SyncCheckpointRow')
class SyncCheckpoints extends Table {
  TextColumn get name => text()();
  IntColumn get hostEpoch => integer()();
  IntColumn get sequence => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get lastSuccessAt => integer().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {name};
}
