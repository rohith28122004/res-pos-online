import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/money/money.dart';
import '../../../core/pricing/refund_calculator.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';
import '../../bills/application/bill_service.dart';
import '../../bills/domain/payment_method.dart';

class RefundableLineState {
  const RefundableLineState({required this.line, required this.refundedQuantity, required this.calc});
  final BillLineRow line;
  final int refundedQuantity;
  final RefundableLine calc;
  int get remaining => line.quantity - refundedQuantity;
}

class RefundableChargeState {
  const RefundableChargeState({required this.charge, required this.refunded});
  final BillChargeRow charge;
  final bool refunded;
}

class RefundableState {
  const RefundableState({
    required this.bill,
    required this.lines,
    required this.charges,
    required this.paidByMethod,
    required this.refundedByMethod,
    required this.refundedTotal,
    required this.roundingRefunded,
  });

  final BillRow bill;
  final List<RefundableLineState> lines;
  final List<RefundableChargeState> charges;
  final Map<String, int> paidByMethod;
  final Map<String, int> refundedByMethod;
  final int refundedTotal;
  final bool roundingRefunded;

  Map<String, int> get refundableByMethod => {
    for (final e in paidByMethod.entries) e.key: e.value - (refundedByMethod[e.key] ?? 0),
  };

  bool get fullyRefunded => lines.every((l) => l.remaining == 0) && charges.every((c) => c.refunded);
}

class RefundRequest {
  const RefundRequest({
    required this.billId,
    required this.operationId,
    required this.lineQuantities,
    this.chargeIds = const [],
    this.tenders,
    required this.reason,
    this.approval,
  });

  final String billId;
  final String operationId;

  /// bill_line id → quantity to refund now.
  final Map<String, int> lineQuantities;

  /// Service/delivery charges to refund (each refunds in full, once).
  final List<String> chargeIds;

  /// method code → amount. Null = default split over the original methods.
  final Map<String, int>? tenders;
  final String reason;
  final OwnerApproval? approval;
}

class RefundPreview {
  const RefundPreview({
    required this.lines,
    required this.charges,
    required this.roundingAdjustment,
    required this.defaultTenders,
  });

  final List<LineRefundAmounts> lines;
  final List<(BillChargeRow, int netEx, int tax)> charges;
  final int roundingAdjustment;
  final Map<String, int> defaultTenders;

  int get itemsNetEx => lines.fold(0, (a, l) => a + l.netEx);
  int get itemsDiscountEx => lines.fold(0, (a, l) => a + l.discountEx);
  int get itemsGrossEx => lines.fold(0, (a, l) => a + l.grossEx);
  int get chargesNetEx => charges.fold(0, (a, c) => a + c.$2);
  int get taxTotal => lines.fold(0, (a, l) => a + l.tax) + charges.fold(0, (a, c) => a + c.$3);
  int get total =>
      lines.fold<int>(0, (a, l) => a + l.total) + charges.fold<int>(0, (a, c) => a + c.$2 + c.$3) + roundingAdjustment;
}

class RefundResult {
  const RefundResult({
    required this.refundId,
    required this.refundNo,
    required this.total,
    required this.alreadyIssued,
  });
  final String refundId;
  final String refundNo;
  final int total;
  final bool alreadyIssued;
}

/// Owner-authorised full/partial refunds that reverse the original captured
/// amounts and stay linked to the original bill, lines and payment methods.
class RefundService {
  RefundService(this.ctx) : _printJobs = PrintJobWriter(ctx);

  final ServiceContext ctx;
  final PrintJobWriter _printJobs;
  AppDatabase get _db => ctx.db;

  Future<RefundableState> refundableState(String billId) async {
    final bill = await (_db.select(_db.bills)..where((b) => b.id.equals(billId))).getSingleOrNull();
    if (bill == null) throw const NotFoundException('Bill not found');
    final lines =
        await (_db.select(_db.billLines)
              ..where((l) => l.billId.equals(billId))
              ..orderBy([(l) => OrderingTerm(expression: l.sortOrder)]))
            .get();
    final charges = await (_db.select(_db.billCharges)..where((c) => c.billId.equals(billId))).get();
    final comps = await (_db.select(_db.billTaxComponents)..where((c) => c.billId.equals(billId))).get();
    final refunds = await (_db.select(_db.refunds)..where((r) => r.billId.equals(billId))).get();
    final refundIds = refunds.map((r) => r.id).toList();
    final refundLines = refundIds.isEmpty
        ? <RefundLineRow>[]
        : await (_db.select(_db.refundLines)..where((l) => l.refundId.isIn(refundIds))).get();
    final refundCharges = refundIds.isEmpty
        ? <RefundChargeRow>[]
        : await (_db.select(_db.refundCharges)..where((c) => c.refundId.isIn(refundIds))).get();
    final refundPayments = refundIds.isEmpty
        ? <RefundPaymentRow>[]
        : await (_db.select(_db.refundPayments)..where((p) => p.refundId.isIn(refundIds))).get();
    final payments = await (_db.select(_db.payments)..where((p) => p.billId.equals(billId))).get();

    final refundedQty = <String, int>{};
    for (final rl in refundLines) {
      refundedQty.update(rl.billLineId, (v) => v + rl.quantity, ifAbsent: () => rl.quantity);
    }
    final refundedCharges = refundCharges.map((c) => c.billChargeId).toSet();
    final paid = <String, int>{};
    for (final p in payments) {
      paid.update(p.method, (v) => v + p.applied, ifAbsent: () => p.applied);
    }
    final refundedByMethod = <String, int>{};
    for (final p in refundPayments) {
      refundedByMethod.update(p.method, (v) => v + p.amount, ifAbsent: () => p.amount);
    }
    return RefundableState(
      bill: bill,
      lines: [
        for (final l in lines)
          RefundableLineState(
            line: l,
            refundedQuantity: refundedQty[l.id] ?? 0,
            calc: RefundableLine(
              billLineId: l.id,
              quantity: l.quantity,
              netEx: l.netEx,
              discountEx: l.discountEx,
              alreadyRefundedQuantity: refundedQty[l.id] ?? 0,
              components: [
                for (final c in comps.where((c) => c.billLineId == l.id))
                  RefundableComponent(id: c.id, name: c.name, rateBps: c.rateBps, amount: c.amount),
              ],
            ),
          ),
      ],
      charges: [for (final c in charges) RefundableChargeState(charge: c, refunded: refundedCharges.contains(c.id))],
      paidByMethod: paid,
      refundedByMethod: refundedByMethod,
      refundedTotal: refunds.fold(0, (a, r) => a + r.total),
      roundingRefunded: refunds.any((r) => r.roundingAdjustment != 0),
    );
  }

  RefundPreview preview(RefundableState state, Map<String, int> lineQuantities, List<String> chargeIds) {
    final lines = <LineRefundAmounts>[];
    for (final e in lineQuantities.entries) {
      if (e.value == 0) continue;
      final ls = state.lines.where((l) => l.line.id == e.key).firstOrNull;
      if (ls == null) throw const ValidationException('That line is not on this bill');
      lines.add(computeLineRefund(ls.calc, e.value));
    }
    final charges = <(BillChargeRow, int, int)>[];
    for (final id in chargeIds.toSet()) {
      final cs = state.charges.where((c) => c.charge.id == id).firstOrNull;
      if (cs == null) throw const ValidationException('That charge is not on this bill');
      if (cs.refunded) throw ValidationException('${cs.charge.label} was already refunded');
      charges.add((cs.charge, cs.charge.netEx, cs.charge.tax));
    }
    // Rounding is returned only by the refund that completes the bill, so
    // cumulative refunds equal the bill total exactly.
    final completes =
        state.lines.every((l) => l.remaining - (lineQuantities[l.line.id] ?? 0) == 0) &&
        state.charges.every((c) => c.refunded || chargeIds.contains(c.charge.id));
    final rounding = completes && !state.roundingRefunded ? state.bill.roundingAdjustment : 0;
    final provisional = RefundPreview(
      lines: lines,
      charges: charges,
      roundingAdjustment: rounding,
      defaultTenders: const {},
    );
    final total = provisional.total;
    final tenders = total <= 0 ? <String, int>{} : defaultRefundTender(total, state.refundableByMethod);
    return RefundPreview(lines: lines, charges: charges, roundingAdjustment: rounding, defaultTenders: tenders);
  }

  Future<RefundResult> issueRefund(Actor actor, RefundRequest request) async {
    actor.require(Permission.viewBills);
    final why = requireText(request.reason, 'Refund reason', max: 200);
    final opKey = 'refund:${request.operationId}';
    final previous = await ctx.completedOperation(opKey);
    if (previous != null) return _existing(previous);

    final String authorizedBy;
    final String authorizedByName;
    if (actor.can(Permission.refund)) {
      authorizedBy = actor.staffId;
      authorizedByName = actor.name;
    } else {
      await ctx.verifyApproval(request.approval, 'issue a refund');
      authorizedBy = request.approval!.ownerId;
      authorizedByName = request.approval!.ownerName;
    }

    try {
      return await _db.transaction(() async {
        final again = await ctx.completedOperation(opKey);
        if (again != null) return _existing(again);

        // Recomputed inside the transaction: cumulative limits are enforced
        // against committed refunds, never against a stale screen.
        final state = await refundableState(request.billId);
        final p = preview(state, request.lineQuantities, request.chargeIds);
        if (p.lines.isEmpty && p.charges.isEmpty) {
          throw const ValidationException('Choose at least one item or charge to refund');
        }
        final total = p.total;
        if (total <= 0) throw const ValidationException('Refund total must be more than zero');
        if (state.refundedTotal + total > state.bill.total) {
          throw const ValidationException('Refunds cannot exceed the bill total');
        }
        final tenders = request.tenders ?? p.defaultTenders;
        final refundable = state.refundableByMethod;
        var tenderSum = 0;
        for (final e in tenders.entries) {
          if (e.value < 0) throw const ValidationException('Refund amounts cannot be negative');
          if (e.value == 0) continue;
          final cap = refundable[e.key] ?? 0;
          if (e.value > cap) {
            throw ValidationException(
              '${PaymentMethod.parse(e.key).label} refund is more than was paid by ${PaymentMethod.parse(e.key).label} (still refundable: ${CurrencyFormat.forCode(state.bill.currencyCode).format(cap)})',
            );
          }
          tenderSum += e.value;
        }
        if (tenderSum != total) {
          throw const ValidationException('Refund payments must add up to the refund total');
        }

        final shift = await (_db.select(_db.shifts)..where((s) => s.status.equals('open'))).getSingleOrNull();
        if ((tenders[PaymentMethod.cash.code] ?? 0) > 0 && shift == null) {
          throw const ConflictException('Open a shift to pay a cash refund from the drawer');
        }

        final installation = await ctx.installation();
        final calendar = await ctx.calendar();
        final now = ctx.now();
        final nowMs = now.millisecondsSinceEpoch;
        final businessDate = calendar.businessDateOf(now).key;
        final seq = await _db.nextSequenceValue('refund');
        final refundNo = '${installation.receiptPrefix}-R${seq.toString().padLeft(5, '0')}';
        final refundId = ctx.ids.newId();

        await _db
            .into(_db.refunds)
            .insert(
              RefundsCompanion.insert(
                id: refundId,
                refundNo: refundNo,
                billId: state.bill.id,
                operationId: opKey,
                reason: why,
                authorizedBy: authorizedBy,
                authorizedByName: authorizedByName,
                createdBy: actor.staffId,
                createdByName: actor.name,
                createdAt: nowMs,
                businessDate: businessDate,
                localHour: calendar.localHourOf(now),
                shiftId: Value(shift?.id),
                itemsGrossEx: p.itemsGrossEx,
                itemsDiscountEx: p.itemsDiscountEx,
                itemsNetEx: p.itemsNetEx,
                chargesNetEx: p.chargesNetEx,
                taxTotal: p.taxTotal,
                roundingAdjustment: p.roundingAdjustment,
                total: total,
              ),
            );
        for (final l in p.lines) {
          final rlId = ctx.ids.newId();
          await _db
              .into(_db.refundLines)
              .insert(
                RefundLinesCompanion.insert(
                  id: rlId,
                  refundId: refundId,
                  billLineId: l.billLineId,
                  quantity: l.quantity,
                  grossEx: l.grossEx,
                  discountEx: l.discountEx,
                  netEx: l.netEx,
                  tax: l.tax,
                  total: l.total,
                ),
              );
          for (final c in l.components) {
            if (c.amount == 0) continue;
            await _db
                .into(_db.refundTaxComponents)
                .insert(
                  RefundTaxComponentsCompanion.insert(
                    id: ctx.ids.newId(),
                    refundId: refundId,
                    sourceComponentId: c.component.id,
                    refundLineId: Value(rlId),
                    name: c.component.name,
                    rateBps: c.component.rateBps,
                    amount: c.amount,
                  ),
                );
          }
        }
        final comps = await (_db.select(_db.billTaxComponents)..where((c) => c.billId.equals(state.bill.id))).get();
        for (final (charge, netEx, tax) in p.charges) {
          final rcId = ctx.ids.newId();
          await _db
              .into(_db.refundCharges)
              .insert(
                RefundChargesCompanion.insert(
                  id: rcId,
                  refundId: refundId,
                  billChargeId: charge.id,
                  netEx: netEx,
                  tax: tax,
                  total: netEx + tax,
                ),
              );
          for (final c in comps.where((c) => c.billChargeId == charge.id && c.amount != 0)) {
            await _db
                .into(_db.refundTaxComponents)
                .insert(
                  RefundTaxComponentsCompanion.insert(
                    id: ctx.ids.newId(),
                    refundId: refundId,
                    sourceComponentId: c.id,
                    refundChargeId: Value(rcId),
                    name: c.name,
                    rateBps: c.rateBps,
                    amount: c.amount,
                  ),
                );
          }
        }
        for (final e in tenders.entries.where((e) => e.value > 0)) {
          await _db
              .into(_db.refundPayments)
              .insert(
                RefundPaymentsCompanion.insert(
                  id: ctx.ids.newId(),
                  refundId: refundId,
                  method: e.key,
                  amount: e.value,
                  shiftId: Value(shift?.id),
                  businessDate: businessDate,
                  createdAt: nowMs,
                ),
              );
        }
        await ctx.recordOperation(opKey, 'refund', refundId);
        await ctx.audit(
          actor,
          'refund.issued',
          entityType: 'refund',
          entityId: refundId,
          approval: request.approval,
          details: {
            'refundNo': refundNo,
            'billReceiptNo': state.bill.receiptNo,
            'total': total,
            'reason': why,
            'authorizedBy': authorizedByName,
            'tenders': tenders,
          },
        );

        final settings = await ctx.settings();
        if (settings.autoPrintReceipt) {
          final doc = await refundDocument(refundId);
          await _printJobs.enqueueForRole(
            role: PrinterRole.receipt,
            documentType: DocumentType.refund,
            documentRef: refundId,
            payloadJson: doc.encode(),
            createdBy: actor.staffId,
          );
        }
        return RefundResult(refundId: refundId, refundNo: refundNo, total: total, alreadyIssued: false);
      });
    } on Object {
      final winner = await ctx.completedOperation(opKey);
      if (winner != null) return _existing(winner);
      rethrow;
    }
  }

  Future<RefundResult> _existing(String refundId) async {
    final r = await (_db.select(_db.refunds)..where((x) => x.id.equals(refundId))).getSingle();
    return RefundResult(refundId: r.id, refundNo: r.refundNo, total: r.total, alreadyIssued: true);
  }

  Future<ReceiptDocument> refundDocument(String refundId, {String? copyLabel}) async {
    final r = await (_db.select(_db.refunds)..where((x) => x.id.equals(refundId))).getSingleOrNull();
    if (r == null) throw const NotFoundException('Refund not found');
    final bill = await (_db.select(_db.bills)..where((b) => b.id.equals(r.billId))).getSingle();
    final lines = await (_db.select(_db.refundLines)..where((l) => l.refundId.equals(refundId))).get();
    final billLines = {
      for (final l in await (_db.select(_db.billLines)..where((l) => l.billId.equals(bill.id))).get()) l.id: l,
    };
    final charges = await (_db.select(_db.refundCharges)..where((c) => c.refundId.equals(refundId))).get();
    final billCharges = {
      for (final c in await (_db.select(_db.billCharges)..where((c) => c.billId.equals(bill.id))).get()) c.id: c,
    };
    final comps = await (_db.select(_db.refundTaxComponents)..where((c) => c.refundId.equals(refundId))).get();
    final pays = await (_db.select(_db.refundPayments)..where((p) => p.refundId.equals(refundId))).get();
    final restaurant = RestaurantSnapshot.decode(bill.restaurantJson);
    final calendar = BusinessCalendar(timeZone: bill.timeZone, cutoffMinutes: 0);

    final taxRows = <(String, int), int>{};
    for (final c in comps) {
      taxRows.update((c.name, c.rateBps), (v) => v + c.amount, ifAbsent: () => c.amount);
    }
    return ReceiptDocument(
      title: 'REFUND',
      restaurantName: restaurant.name,
      headerLines: restaurant.headerLines,
      number: r.refundNo,
      dateTime: calendar.formatLocal(DateTime.fromMillisecondsSinceEpoch(r.createdAt, isUtc: true)),
      infoLines: ['Reason: ${r.reason}', 'Approved by: ${r.authorizedByName}', 'Processed by: ${r.createdByName}'],
      referenceLine: 'Against receipt ${bill.receiptNo}',
      lines: [
        for (final l in lines)
          ReceiptLineDoc(
            quantity: l.quantity,
            name: billLines[l.billLineId]!.itemName,
            variant: billLines[l.billLineId]!.variantName,
            unitPrice: billLines[l.billLineId]!.unitPriceEntered,
            amount: l.total,
          ),
      ],
      summary: [
        AmountRow('Items (excl. tax)', r.itemsNetEx),
        for (final c in charges) AmountRow(billCharges[c.billChargeId]!.label, c.netEx),
        for (final e in taxRows.entries) AmountRow('${e.key.$1} ${formatBps(e.key.$2)} reversed', e.value),
        if (r.roundingAdjustment != 0) AmountRow('Rounding', r.roundingAdjustment),
      ],
      total: r.total,
      payments: [for (final p in pays) AmountRow('Refunded by ${PaymentMethod.parse(p.method).label}', p.amount)],
      footerLines: const [],
      currencyCode: bill.currencyCode,
      copyLabel: copyLabel,
    );
  }

  Future<List<RefundRow>> refundsForBill(String billId) =>
      (_db.select(_db.refunds)..where((r) => r.billId.equals(billId))).get();

  Future<List<String>> reprintRefund(Actor actor, String refundId) async {
    actor.require(Permission.reprint);
    final doc = await refundDocument(refundId, copyLabel: CopyLabel.copy);
    return _db.transaction(() async {
      final ids = await _printJobs.enqueueForRole(
        role: PrinterRole.receipt,
        documentType: DocumentType.refund,
        documentRef: refundId,
        payloadJson: doc.encode(),
        copyLabel: CopyLabel.copy,
        createdBy: actor.staffId,
      );
      await ctx.audit(actor, 'refund.reprinted', entityType: 'refund', entityId: refundId);
      return ids;
    });
  }
}
