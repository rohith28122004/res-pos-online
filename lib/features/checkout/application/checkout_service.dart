import 'package:drift/drift.dart';
import 'package:meta/meta.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/pricing/pricing_engine.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../bills/application/bill_service.dart';
import '../../bills/domain/payment_method.dart';
import '../../orders/domain/order_models.dart';

class FinalizeRequest {
  const FinalizeRequest({
    required this.orderId,
    required this.operationId,
    required this.tenders,
    required this.paymentConfirmed,
    this.approval,
  });

  final String orderId;

  /// Generated once when the payment screen opens. Double taps, retries and
  /// restarts reuse it, so the same order can never be billed twice.
  final String operationId;
  final List<TenderInput> tenders;

  /// Staff ticked "payment received". UPI/card are not verified by the app.
  final bool paymentConfirmed;
  final OwnerApproval? approval;
}

class FinalizeResult {
  const FinalizeResult({
    required this.billId,
    required this.receiptNo,
    required this.total,
    required this.change,
    required this.printJobIds,
    required this.alreadyFinalized,
  });

  final String billId;
  final String receiptNo;
  final int total;
  final int change;
  final List<String> printJobIds;

  /// True when this call found an earlier finalization of the same operation.
  final bool alreadyFinalized;
}

/// Atomic, idempotent checkout.
///
/// One transaction validates permissions and totals, allocates the receipt
/// number, writes the immutable bill + line snapshots + payments, closes the
/// order (releasing its table) and enqueues the receipt print job. Printing
/// happens later and its failure never touches the bill.
class CheckoutService {
  CheckoutService(this.ctx, {this.engine = const PricingEngine()}) : _printJobs = PrintJobWriter(ctx);

  final ServiceContext ctx;
  final PricingEngine engine;
  final PrintJobWriter _printJobs;

  /// Test hook: runs inside the transaction just before commit.
  @visibleForTesting
  Future<void> Function()? debugBeforeCommit;

  AppDatabase get _db => ctx.db;

  Future<FinalizeResult> finalize(Actor actor, FinalizeRequest request) async {
    actor.require(Permission.checkout);
    final opKey = 'finalize:${request.operationId}';

    final earlier = await _existing(opKey);
    if (earlier != null) return earlier;

    try {
      return await _db.transaction(() async {
        final again = await _existing(opKey);
        if (again != null) return again;

        final order = await (_db.select(_db.orders)..where((o) => o.id.equals(request.orderId))).getSingleOrNull();
        if (order == null) throw const NotFoundException('Order not found');
        if (order.status == OrderStatus.finalized) {
          final bill = await (_db.select(_db.bills)..where((b) => b.orderId.equals(order.id))).getSingle();
          throw ConflictException('This order was already billed as ${bill.receiptNo}');
        }
        if (order.status != OrderStatus.open) throw const ConflictException('This order was cancelled');

        final lines =
            (await (_db.select(_db.orderLines)
                      ..where((l) => l.orderId.equals(order.id))
                      ..orderBy([
                        (l) => OrderingTerm(expression: l.sortOrder),
                        (l) => OrderingTerm(expression: l.createdAt),
                      ]))
                    .get())
                .where((l) => l.quantity > 0)
                .toList();
        if (lines.isEmpty) throw const ValidationException('Add at least one item before taking payment');

        final settings = await ctx.settings();
        final pricing = engine.price(pricingInputFor(order, lines));
        if (pricing.discountExceeds(settings.cashierDiscountLimitBps) &&
            !actor.isOwner &&
            order.discountApprovedBy == null) {
          await ctx.verifyApproval(request.approval, 'give a discount above the cashier limit');
        }

        final tenders = _validateTenders(request, pricing.total);

        final shift = await (_db.select(_db.shifts)..where((s) => s.status.equals('open'))).getSingleOrNull();
        if (shift == null) throw const ConflictException('Open a shift before taking payment');

        final installation = await ctx.installation();
        final calendar = await ctx.calendar();
        final now = ctx.now();
        final nowMs = now.millisecondsSinceEpoch;
        final businessDate = calendar.businessDateOf(now).key;
        final seq = await _db.nextSequenceValue('receipt');
        final receiptNo = '${installation.receiptPrefix}-${seq.toString().padLeft(6, '0')}';
        final billId = ctx.ids.newId();
        final change = tenders.fold<int>(0, (a, t) => a + t.change);

        await _db
            .into(_db.bills)
            .insert(
              BillsCompanion.insert(
                id: billId,
                receiptNo: receiptNo,
                receiptSeq: seq,
                orderId: order.id,
                operationId: opKey,
                orderNo: order.orderNo,
                orderType: order.orderType,
                tableLabel: Value(order.tableLabel),
                customerName: Value(order.customerName),
                guestCount: Value(order.guestCount),
                businessDate: businessDate,
                localHour: calendar.localHourOf(now),
                createdAt: nowMs,
                staffId: actor.staffId,
                staffName: actor.name,
                shiftId: shift.id,
                itemCount: pricing.itemCount,
                itemsGrossEntered: pricing.itemsGrossEntered,
                discountEnteredTotal: pricing.discountEnteredTotal,
                itemsGrossEx: pricing.itemsGrossEx,
                itemsDiscountEx: pricing.itemsDiscountEx,
                itemsNetEx: pricing.itemsNetEx,
                chargesNetEx: pricing.chargesNetEx,
                taxTotal: pricing.taxTotal,
                subtotalBeforeRounding: pricing.subtotalBeforeRounding,
                roundingAdjustment: pricing.roundingAdjustment,
                total: pricing.total,
                changeTotal: change,
                discountReason: Value(order.discountReason),
                discountApprovedBy: Value(order.discountApprovedBy ?? request.approval?.ownerId),
                currencyCode: settings.currencyCode,
                timeZone: settings.timeZone,
                restaurantJson: RestaurantSnapshot.of(settings).encode(),
              ),
            );

        final linesById = {for (final l in lines) l.id: l};
        for (var i = 0; i < pricing.lines.length; i++) {
          final p = pricing.lines[i];
          final src = linesById[p.key]!;
          final billLineId = ctx.ids.newId();
          await _db
              .into(_db.billLines)
              .insert(
                BillLinesCompanion.insert(
                  id: billLineId,
                  billId: billId,
                  orderLineId: src.id,
                  itemId: Value(src.itemId),
                  itemName: src.itemName,
                  variantName: Value(src.variantName),
                  categoryId: Value(src.categoryId),
                  categoryName: Value(src.categoryName),
                  modifiersJson: src.modifiersJson,
                  note: Value(src.note),
                  quantity: p.quantity,
                  unitPriceEntered: p.unitPriceEntered,
                  grossEntered: p.grossEntered,
                  lineDiscountEntered: p.lineDiscountEntered,
                  billDiscountEntered: p.billDiscountEntered,
                  grossEx: p.grossEx,
                  discountEx: p.discountEx,
                  netEx: p.netEx,
                  taxMode: p.taxSnapshot.mode.name,
                  taxRateBps: p.taxSnapshot.effectiveRateBps,
                  tax: p.tax,
                  total: p.total,
                  sortOrder: i,
                ),
              );
          for (final c in p.components) {
            await _db
                .into(_db.billTaxComponents)
                .insert(
                  BillTaxComponentsCompanion.insert(
                    id: ctx.ids.newId(),
                    billId: billId,
                    billLineId: Value(billLineId),
                    name: c.name,
                    rateBps: c.rateBps,
                    amount: c.amount,
                  ),
                );
          }
        }
        for (final ch in pricing.charges) {
          final chargeId = ctx.ids.newId();
          await _db
              .into(_db.billCharges)
              .insert(
                BillChargesCompanion.insert(
                  id: chargeId,
                  billId: billId,
                  kind: ch.kind.name,
                  label: ch.label,
                  amountEntered: ch.amountEntered,
                  netEx: ch.netEx,
                  taxMode: ch.taxSnapshot.mode.name,
                  taxRateBps: ch.taxSnapshot.effectiveRateBps,
                  tax: ch.tax,
                  total: ch.total,
                ),
              );
          for (final c in ch.components) {
            await _db
                .into(_db.billTaxComponents)
                .insert(
                  BillTaxComponentsCompanion.insert(
                    id: ctx.ids.newId(),
                    billId: billId,
                    billChargeId: Value(chargeId),
                    name: c.name,
                    rateBps: c.rateBps,
                    amount: c.amount,
                  ),
                );
          }
        }

        for (final t in tenders) {
          await _db
              .into(_db.payments)
              .insert(
                PaymentsCompanion.insert(
                  id: ctx.ids.newId(),
                  billId: billId,
                  method: t.method.code,
                  applied: t.applied,
                  tendered: t.tendered,
                  changeGiven: t.change,
                  shiftId: shift.id,
                  businessDate: businessDate,
                  createdAt: nowMs,
                  confirmedBy: actor.staffId,
                  confirmedByName: actor.name,
                ),
              );
        }

        await (_db.update(_db.orders)..where((o) => o.id.equals(order.id))).write(
          OrdersCompanion(
            status: const Value(OrderStatus.finalized),
            finalizedAt: Value(nowMs),
            updatedAt: Value(nowMs),
            revision: Value(order.revision + 1),
          ),
        );

        await ctx.recordOperation(opKey, 'finalize', billId);
        await ctx.audit(
          actor,
          'bill.finalized',
          entityType: 'bill',
          entityId: billId,
          approval: request.approval,
          details: {
            'receiptNo': receiptNo,
            'total': pricing.total,
            'discount': pricing.discountEnteredTotal,
            'payments': {for (final t in tenders) t.method.code: t.applied},
          },
        );

        var jobIds = <String>[];
        if (settings.autoPrintReceipt) {
          final doc = BillService.buildReceiptDocument(await BillService(ctx).detail(billId));
          jobIds = await _printJobs.enqueueForRole(
            role: PrinterRole.receipt,
            documentType: DocumentType.receipt,
            documentRef: billId,
            payloadJson: doc.encode(),
            createdBy: actor.staffId,
          );
        }

        if (debugBeforeCommit != null) await debugBeforeCommit!();

        return FinalizeResult(
          billId: billId,
          receiptNo: receiptNo,
          total: pricing.total,
          change: change,
          printJobIds: jobIds,
          alreadyFinalized: false,
        );
      });
    } on Object {
      // A concurrent identical request may have won the race; report its bill.
      final winner = await _existing(opKey);
      if (winner != null) return winner;
      rethrow;
    }
  }

  List<TenderInput> _validateTenders(FinalizeRequest request, int total) {
    if (total == 0) {
      if (request.tenders.any((t) => t.applied != 0)) {
        throw const ValidationException('This bill is free; remove the payments');
      }
      return const [];
    }
    if (!request.paymentConfirmed) {
      throw const ValidationException('Confirm that the payment has been received');
    }
    if (request.tenders.isEmpty) throw const ValidationException('Add a payment');
    // Merge repeated methods.
    final merged = <PaymentMethod, TenderInput>{};
    for (final t in request.tenders) {
      if (t.applied <= 0) throw const ValidationException('Each payment must be more than zero');
      if (t.method != PaymentMethod.cash && t.tendered != t.applied) {
        throw ValidationException('${t.method.label} cannot have change');
      }
      if (t.tendered < t.applied) {
        throw ValidationException('${t.method.label}: amount received is less than the amount applied');
      }
      final prev = merged[t.method];
      merged[t.method] = prev == null
          ? t
          : TenderInput(method: t.method, applied: prev.applied + t.applied, tendered: prev.tendered + t.tendered);
    }
    final applied = merged.values.fold<int>(0, (a, t) => a + t.applied);
    if (applied < total) {
      throw const ValidationException('Payments are less than the bill total');
    }
    if (applied > total) {
      throw const ValidationException(
        'Payments are more than the bill total. Enter extra cash as "cash received" so it is shown as change.',
      );
    }
    return [
      for (final m in PaymentMethod.values)
        if (merged[m] != null) merged[m]!,
    ];
  }

  Future<FinalizeResult?> _existing(String opKey) async {
    final billId = await ctx.completedOperation(opKey);
    if (billId == null) return null;
    final bill = await (_db.select(_db.bills)..where((b) => b.id.equals(billId))).getSingle();
    final jobs =
        await (_db.select(_db.printJobs)..where(
              (j) => j.documentRef.equals(billId) & j.documentType.equals(DocumentType.receipt) & j.copyLabel.isNull(),
            ))
            .get();
    return FinalizeResult(
      billId: bill.id,
      receiptNo: bill.receiptNo,
      total: bill.total,
      change: bill.changeTotal,
      printJobIds: jobs.map((j) => j.id).toList(),
      alreadyFinalized: true,
    );
  }
}
