import 'dart:async';

import 'package:drift/drift.dart';

import '../../features/orders/domain/order_models.dart';
import '../database/app_database.dart';
import '../pricing/pricing_engine.dart';
import '../protocol/canonical_json.dart';
import '../protocol/protocol.dart';
import '../service_context.dart';

/// Aggregates whose changes produce events (docs/PROTOCOL.md §5.2).
enum Aggregate { order, ticket, bill, refund, expense, shift, cashMovement, menu, tables }

/// The host's event outbox. Services call [changed] at the end of their
/// transaction; the event (with a full snapshot of the aggregate) is written in
/// that same transaction, with the next gap-free sequence number.
///
/// Inside [batch] (used by the remote command dispatcher) repeated changes of
/// one aggregate collapse into a single event written when the batch ends —
/// still inside the caller's transaction.
class HostOutbox {
  HostOutbox(this.ctx);

  final ServiceContext ctx;

  static final _batchKey = Object();

  AppDatabase get _db => ctx.db;

  /// Runs [body] collecting changes; writes their events at the end. Must be
  /// called inside a transaction. Returns the body's value and the highest
  /// sequence written (0 if none).
  Future<(T, int)> batch<T>(Future<T> Function() body) async {
    final pending = <(Aggregate, String)>{};
    final value = await runZoned(body, zoneValues: {_batchKey: pending});
    var last = 0;
    for (final (kind, id) in pending) {
      last = await _writeFor(kind, id);
    }
    return (value, last);
  }

  /// Records that [id] of [kind] changed. Call inside the transaction that made
  /// the change, after the change.
  Future<void> changed(Aggregate kind, String id) async {
    final pending = Zone.current[_batchKey] as Set<(Aggregate, String)>?;
    if (pending != null) {
      // Re-adding moves nothing; the event is built once, from the final state.
      pending.add((kind, id));
      return;
    }
    await _writeFor(kind, id);
  }

  /// Writes an event with an explicit payload (device, session and staff
  /// access events). Returns its sequence.
  Future<int> emit({
    required String type,
    required String aggregateType,
    required String aggregateId,
    int revision = 1,
    String? businessDate,
    required Map<String, Object?> payload,
  }) => _append(
    type: type,
    aggregateType: aggregateType,
    aggregateId: aggregateId,
    revision: revision,
    businessDate: businessDate,
    payload: payload,
  );

  Future<int> _writeFor(Aggregate kind, String id) async {
    switch (kind) {
      case Aggregate.order:
        final view = await EventViews(ctx).orderView(id);
        if (view == null) return 0;
        return _append(
          type: EventType.orderUpdated,
          aggregateType: 'order',
          aggregateId: id,
          revision: view['revision']! as int,
          businessDate: view['businessDate'] as String?,
          payload: view,
        );
      case Aggregate.ticket:
        final view = await EventViews(ctx).ticketView(id);
        if (view == null) return 0;
        return _append(
          type: EventType.ticketUpdated,
          aggregateType: 'kitchen_ticket',
          aggregateId: id,
          revision: view['revision']! as int,
          payload: view,
        );
      case Aggregate.bill:
        final p = await EventViews(ctx).billPayload(id);
        return _append(
          type: EventType.billFinalized,
          aggregateType: 'bill',
          aggregateId: id,
          businessDate: (p['bill']! as Map)['businessDate'] as String?,
          payload: p,
        );
      case Aggregate.refund:
        final p = await EventViews(ctx).refundPayload(id);
        return _append(
          type: EventType.refundCreated,
          aggregateType: 'refund',
          aggregateId: id,
          businessDate: (p['refund']! as Map)['businessDate'] as String?,
          payload: p,
        );
      case Aggregate.expense:
        final row = await (_db.select(_db.expenses)..where((e) => e.id.equals(id))).getSingle();
        return _append(
          type: row.voidedAt == null ? EventType.expenseRecorded : EventType.expenseVoided,
          aggregateType: 'expense',
          aggregateId: id,
          revision: row.voidedAt == null ? 1 : 2,
          businessDate: row.businessDate,
          payload: {'expense': row.toJson()},
        );
      case Aggregate.shift:
        final shift = await (_db.select(_db.shifts)..where((s) => s.id.equals(id))).getSingle();
        final closures =
            await (_db.select(_db.shiftClosures)
                  ..where((c) => c.shiftId.equals(id))
                  ..orderBy([(c) => OrderingTerm(expression: c.closedAt)]))
                .get();
        return _append(
          type: EventType.shiftUpdated,
          aggregateType: 'shift',
          aggregateId: id,
          // open → 1, closed → 2, reopened → 3, closed again → 4 …
          revision: closures.length * 2 + (shift.status == 'open' ? 1 : 0),
          businessDate: shift.businessDate,
          payload: {
            'shift': shift.toJson(),
            'closures': [for (final c in closures) c.toJson()],
          },
        );
      case Aggregate.cashMovement:
        final row = await (_db.select(_db.cashMovements)..where((m) => m.id.equals(id))).getSingle();
        return _append(
          type: EventType.cashMovementRecorded,
          aggregateType: 'cash_movement',
          aggregateId: id,
          businessDate: row.businessDate,
          payload: {'movement': row.toJson()},
        );
      case Aggregate.menu:
        return _append(type: EventType.menuChanged, aggregateType: 'menu', aggregateId: 'menu', payload: const {});
      case Aggregate.tables:
        return _append(
          type: EventType.tablesChanged,
          aggregateType: 'dining_tables',
          aggregateId: 'tables',
          payload: const {},
        );
    }
  }

  Future<int> _append({
    required String type,
    required String aggregateType,
    required String aggregateId,
    int revision = 1,
    String? businessDate,
    required Map<String, Object?> payload,
  }) async {
    final epoch = await currentEpoch();
    final sequence = await _db.nextSequenceValue('event');
    final now = ctx.nowMs();
    final event = {
      'protocolVersion': ProtocolVersion.current,
      'eventId': ctx.ids.newId(),
      'hostEpoch': epoch,
      'sequence': sequence,
      'type': type,
      'aggregateType': aggregateType,
      'aggregateId': aggregateId,
      'revision': revision,
      'committedAtUtc': now,
      'businessDate': businessDate,
      'payload': payload,
    };
    final json = canonicalJson(event);
    await _db
        .into(_db.hostEvents)
        .insert(
          HostEventsCompanion.insert(
            hostEpoch: epoch,
            sequence: sequence,
            eventId: event['eventId']! as String,
            type: type,
            aggregateType: aggregateType,
            aggregateId: aggregateId,
            revision: revision,
            committedAt: now,
            businessDate: Value(businessDate),
            audience: EventType.deviceAudience.contains(type) ? EventAudience.devices : EventAudience.cloud,
            eventJson: json,
            contentHash: sha256Hex(json),
          ),
        );
    return sequence;
  }

  /// The host epoch events are written under. Before the host identity exists
  /// (a POS that has never been set up for devices) this is epoch 1, which is
  /// where the identity starts.
  Future<int> currentEpoch() async {
    final row = await _db.select(_db.hostIdentity).getSingleOrNull();
    return row?.hostEpoch ?? 1;
  }

  /// Highest event sequence written so far (0 when none).
  Future<int> latestSequence() async => (await _db.peekSequenceValue('event')) - 1;

  /// How long events stay after they are no longer needed. Phones that were
  /// away longer reload a snapshot instead of replaying.
  static const keep = Duration(days: 7);

  /// Deletes events older than [keep] that nothing still needs. With a cloud
  /// connected, an event of the current epoch stays until the cloud has
  /// acknowledged it; older epochs were replaced by the restore re-send.
  /// Sequence numbers come from a counter, so they are never reused.
  Future<int> prune() async {
    final cutoff = ctx.nowMs() - keep.inMilliseconds;
    final identity = await _db.select(_db.hostIdentity).getSingleOrNull();
    final epoch = identity?.hostEpoch ?? 1;
    final cloud = identity?.cloudUrl != null;
    return (_db.delete(_db.hostEvents)..where(
          (e) =>
              e.committedAt.isSmallerThanValue(cutoff) &
              (cloud ? e.cloudAckedAt.isNotNull() | e.hostEpoch.isSmallerThanValue(epoch) : const Constant(true)),
        ))
        .go();
  }
}

/// Builds the device-facing views and the cloud payloads from database rows.
class EventViews {
  EventViews(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  Future<Map<String, String>> _staffNames(Iterable<String> ids) async {
    final set = ids.toSet();
    if (set.isEmpty) return const {};
    final rows = await (_db.select(_db.staff)..where((s) => s.id.isIn(set))).get();
    return {for (final r in rows) r.id: r.name};
  }

  Future<Map<String, int>> _sent(String orderId) async {
    final rows = await _db
        .customSelect(
          'SELECT ktl.order_line_id AS line_id, SUM(ktl.quantity_delta) AS sent '
          'FROM kitchen_ticket_lines ktl JOIN kitchen_tickets kt ON kt.id = ktl.ticket_id '
          'WHERE kt.order_id = ? GROUP BY ktl.order_line_id',
          variables: [Variable.withString(orderId)],
          readsFrom: {_db.kitchenTicketLines, _db.kitchenTickets},
        )
        .get();
    return {for (final r in rows) r.read<String>('line_id'): r.read<int>('sent')};
  }

  /// `OrderView` (docs/PROTOCOL.md §5.2), or null if the order is unknown.
  Future<Map<String, Object?>?> orderView(String orderId) async {
    final o = await (_db.select(_db.orders)..where((x) => x.id.equals(orderId))).getSingleOrNull();
    if (o == null) return null;
    final lines =
        await (_db.select(_db.orderLines)
              ..where((l) => l.orderId.equals(orderId))
              ..orderBy([(l) => OrderingTerm(expression: l.sortOrder), (l) => OrderingTerm(expression: l.createdAt)]))
            .get();
    final sent = await _sent(orderId);
    final names = await _staffNames([o.createdBy, ...lines.map((l) => l.createdBy)]);
    int? estimated;
    try {
      estimated = const PricingEngine().price(pricingInputFor(o, lines)).total;
    } on Object {
      estimated = null;
    }
    return {
      'orderId': o.id,
      'orderNo': o.orderNo,
      'orderRef': orderReference(orderNo: o.orderNo, orderType: o.orderType, tableLabel: o.tableLabel),
      'orderType': o.orderType,
      'tableId': o.tableId,
      'tableLabel': o.tableLabel,
      'status': o.status,
      'revision': o.revision,
      'createdBy': o.createdBy,
      'createdByName': o.createdByName,
      'createdAt': o.createdAt,
      'businessDate': o.businessDate,
      'guestCount': o.guestCount,
      'note': o.note,
      'cancelledAt': o.cancelledAt,
      'cancelBusinessDate': o.cancelBusinessDate,
      'estimatedTotal': estimated,
      'lines': [
        for (final l in lines)
          if (l.quantity > 0 || (sent[l.id] ?? 0) > 0)
            {
              'lineId': l.id,
              'itemId': l.itemId,
              'itemName': l.itemName,
              'variantName': l.variantName,
              'modifiers': [for (final m in LineModifier.decodeList(l.modifiersJson)) m.name],
              'note': l.note,
              'quantity': l.quantity,
              'sentQuantity': sent[l.id] ?? 0,
              'unitPrice': l.unitPrice + l.modifiersUnitTotal,
              'revision': l.revision,
              'createdBy': l.createdBy,
              'createdByName': names[l.createdBy],
            },
      ],
    };
  }

  /// `TicketView`, or null if the ticket is unknown.
  Future<Map<String, Object?>?> ticketView(String ticketId) async {
    final t = await (_db.select(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).getSingleOrNull();
    if (t == null) return null;
    final lines = await (_db.select(_db.kitchenTicketLines)..where((l) => l.ticketId.equals(ticketId))).get();
    return ticketViewOf(t, lines);
  }

  static Map<String, Object?> ticketViewOf(KitchenTicketRow t, List<KitchenTicketLineRow> lines) => {
    'ticketId': t.id,
    'ticketNo': t.ticketNo,
    'orderId': t.orderId,
    'orderRef': t.orderRef,
    'tableLabel': t.tableLabel,
    'kind': t.kind,
    'reason': t.reason,
    'status': t.status,
    'revision': t.revision,
    'createdBy': t.createdBy,
    'createdByName': t.createdByName,
    'createdAt': t.createdAt,
    'lines': [
      for (final l in lines)
        {
          'itemName': l.itemName,
          'variantName': l.variantName,
          'modifiersText': l.modifiersText,
          'note': l.note,
          'quantityDelta': l.quantityDelta,
        },
    ],
  };

  Future<Map<String, Object?>> billPayload(String billId) async {
    final bill = await (_db.select(_db.bills)..where((b) => b.id.equals(billId))).getSingle();
    final lines =
        await (_db.select(_db.billLines)
              ..where((l) => l.billId.equals(billId))
              ..orderBy([(l) => OrderingTerm(expression: l.sortOrder)]))
            .get();
    final charges = await (_db.select(_db.billCharges)..where((c) => c.billId.equals(billId))).get();
    final tax = await (_db.select(_db.billTaxComponents)..where((c) => c.billId.equals(billId))).get();
    final payments = await (_db.select(_db.payments)..where((p) => p.billId.equals(billId))).get();
    return {
      'bill': bill.toJson(),
      'lines': [for (final r in lines) r.toJson()],
      'charges': [for (final r in charges) r.toJson()],
      'taxComponents': [for (final r in _sortedById(tax)) r.toJson()],
      'payments': [for (final r in _sortedById(payments)) r.toJson()],
    };
  }

  Future<Map<String, Object?>> refundPayload(String refundId) async {
    final refund = await (_db.select(_db.refunds)..where((r) => r.id.equals(refundId))).getSingle();
    final lines = await (_db.select(_db.refundLines)..where((l) => l.refundId.equals(refundId))).get();
    final charges = await (_db.select(_db.refundCharges)..where((c) => c.refundId.equals(refundId))).get();
    final tax = await (_db.select(_db.refundTaxComponents)..where((c) => c.refundId.equals(refundId))).get();
    final payments = await (_db.select(_db.refundPayments)..where((p) => p.refundId.equals(refundId))).get();
    return {
      'refund': refund.toJson(),
      'lines': [for (final r in _sortedById(lines)) r.toJson()],
      'charges': [for (final r in _sortedById(charges)) r.toJson()],
      'taxComponents': [for (final r in _sortedById(tax)) r.toJson()],
      'payments': [for (final r in _sortedById(payments)) r.toJson()],
    };
  }

  static List<T> _sortedById<T extends DataClass>(List<T> rows) =>
      [...rows]..sort((a, b) => (a.toJson()['id']! as String).compareTo(b.toJson()['id']! as String));
}
