import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_errors.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/pricing/pricing_engine.dart';
import '../../../core/pricing/tax.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/sync/host_outbox.dart';
import '../../settings/application/settings_service.dart';
import '../domain/order_models.dart';

/// Durable open orders, cart edits and kitchen ticket (KOT) submission.
///
/// Every edit is committed immediately so a crash or restart loses nothing.
/// Lines capture name, variant, price, modifiers and tax when created; menu
/// edits never reprice them.
class OrderService {
  OrderService(this.ctx, {this.engine = const PricingEngine()}) : _printJobs = PrintJobWriter(ctx);

  final ServiceContext ctx;
  final PricingEngine engine;
  final PrintJobWriter _printJobs;

  AppDatabase get _db => ctx.db;

  // ---- Reading -------------------------------------------------------------

  Future<OrderRow> _order(String id) async {
    final row = await (_db.select(_db.orders)..where((o) => o.id.equals(id))).getSingleOrNull();
    if (row == null) throw const NotFoundException('Order not found');
    return row;
  }

  Future<OrderRow> _openOrder(String id) async {
    final row = await _order(id);
    if (row.status != OrderStatus.open) {
      throw ConflictException(
        row.status == OrderStatus.finalized ? 'This order has already been billed' : 'This order was cancelled',
      );
    }
    return row;
  }

  Future<List<OrderLineRow>> _lines(String orderId) =>
      (_db.select(_db.orderLines)
            ..where((l) => l.orderId.equals(orderId))
            ..orderBy([(l) => OrderingTerm(expression: l.sortOrder), (l) => OrderingTerm(expression: l.createdAt)]))
          .get();

  /// Net quantity sent to the kitchen per order line.
  Future<Map<String, int>> sentQuantities(String orderId) async {
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

  Future<OrderDetail> loadOrder(String orderId) async {
    final order = await _order(orderId);
    final lines = await _lines(orderId);
    final sent = await sentQuantities(orderId);
    PricingResult? pricing;
    String? error;
    try {
      pricing = engine.price(pricingInputFor(order, lines));
    } on AppException catch (e) {
      error = e.message;
    }
    return OrderDetail(
      order: order,
      lines: [
        for (final l in lines)
          OrderLineView(row: l, sentQuantity: sent[l.id] ?? 0, modifiers: LineModifier.decodeList(l.modifiersJson)),
      ],
      pricing: pricing,
      pricingError: error,
    );
  }

  Stream<OrderDetail> watchOrder(String orderId) async* {
    yield await loadOrder(orderId);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.orders, _db.orderLines, _db.kitchenTickets, _db.kitchenTicketLines]),
    )) {
      yield await loadOrder(orderId);
    }
  }

  Future<List<OpenOrderSummary>> openOrders() async {
    final orders =
        await (_db.select(_db.orders)
              ..where((o) => o.status.equals(OrderStatus.open))
              ..orderBy([(o) => OrderingTerm(expression: o.createdAt)]))
            .get();
    final result = <OpenOrderSummary>[];
    for (final o in orders) {
      final lines = await _lines(o.id);
      final sent = await sentQuantities(o.id);
      var total = 0;
      try {
        total = engine.price(pricingInputFor(o, lines)).total;
      } on AppException {
        total = 0;
      }
      result.add(
        OpenOrderSummary(
          order: o,
          itemCount: lines.fold(0, (a, l) => a + l.quantity),
          total: total,
          hasUnsent: lines.any((l) => l.quantity > (sent[l.id] ?? 0)),
        ),
      );
    }
    return result;
  }

  Stream<List<OpenOrderSummary>> watchOpenOrders() async* {
    yield await openOrders();
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.orders, _db.orderLines, _db.kitchenTicketLines]),
    )) {
      yield await openOrders();
    }
  }

  // ---- Creating ---------------------------------------------------------------

  Future<String> createOrder(Actor actor, {required OrderType type, String? tableId, String? customerName}) async {
    actor.require(Permission.takeOrders);
    final settings = await ctx.settings();
    final settingsService = SettingsService(ctx);
    final serviceTax = await settingsService.snapshotFor(settings.serviceChargeTaxProfileId);
    final deliveryTax = await settingsService.snapshotFor(settings.deliveryChargeTaxProfileId);
    final calendar = await ctx.calendar();
    final now = ctx.now();
    final id = ctx.ids.newId();

    try {
      await _db.transaction(() async {
        String? tableLabel;
        if (tableId != null) {
          if (type != OrderType.dineIn) {
            throw const ValidationException('Only dine-in orders can use a table');
          }
          final table = await (_db.select(_db.diningTables)..where((t) => t.id.equals(tableId))).getSingleOrNull();
          if (table == null || table.archived) throw const NotFoundException('Table not found');
          final open = await (_db.select(
            _db.orders,
          )..where((o) => o.tableId.equals(tableId) & o.status.equals(OrderStatus.open))).getSingleOrNull();
          if (open != null) {
            throw ConflictException('${table.name} already has an open order (#${open.orderNo})');
          }
          tableLabel = table.name;
        }
        final orderNo = await _db.nextSequenceValue('order');
        await _db
            .into(_db.orders)
            .insert(
              OrdersCompanion.insert(
                id: id,
                orderNo: orderNo,
                orderType: type.code,
                tableId: Value(tableId),
                tableLabel: Value(tableLabel),
                status: OrderStatus.open,
                createdBy: actor.staffId,
                createdByName: actor.name,
                createdAt: now.millisecondsSinceEpoch,
                updatedAt: now.millisecondsSinceEpoch,
                businessDate: calendar.businessDateOf(now).key,
                customerName: Value(optionalText(customerName, max: 60)),
                serviceChargeBps: Value(type == OrderType.dineIn ? settings.serviceChargeBps : 0),
                serviceChargeTaxJson: Value(serviceTax.encode()),
                deliveryCharge: Value(type == OrderType.delivery ? settings.deliveryChargeDefault : 0),
                deliveryChargeTaxJson: Value(deliveryTax.encode()),
                roundingUnit: Value(settings.roundingUnit),
              ),
            );
        await ctx.audit(
          actor,
          'order.created',
          entityType: 'order',
          entityId: id,
          details: {'orderNo': orderNo, 'type': type.code, 'table': tableLabel},
        );
        await ctx.outbox.changed(Aggregate.order, id);
      });
    } on Object catch (e) {
      if (isUniqueViolation(e)) throw const ConflictException('That table already has an open order');
      rethrow;
    }
    return id;
  }

  // ---- Lines ---------------------------------------------------------------------

  /// Adds an item (or bumps an identical line). Captures current menu data.
  Future<String> addItem(
    Actor actor,
    String orderId, {
    required String itemId,
    String? variantId,
    List<String> modifierIds = const [],
    int quantity = 1,
    String? note,
  }) async {
    actor.require(Permission.takeOrders);
    if (quantity < 1 || quantity > 999) throw const ValidationException('Quantity must be between 1 and 999');
    final cleanNote = optionalText(note, max: 140);
    return _db.transaction(() async {
      final order = await _openOrder(orderId);
      final item = await (_db.select(_db.menuItems)..where((i) => i.id.equals(itemId))).getSingleOrNull();
      if (item == null || item.archived) throw const NotFoundException('Menu item not found');
      if (!item.available) throw ConflictException('${item.name} is sold out');
      final category = await (_db.select(_db.categories)..where((c) => c.id.equals(item.categoryId))).getSingleOrNull();

      final variants = await (_db.select(
        _db.itemVariants,
      )..where((v) => v.itemId.equals(itemId) & v.archived.equals(false))).get();
      ItemVariantRow? variant;
      if (variants.isNotEmpty) {
        if (variantId == null) {
          if (variants.length == 1) {
            variant = variants.single;
          } else {
            throw ValidationException('Choose a size/variant for ${item.name}');
          }
        } else {
          variant = variants.where((v) => v.id == variantId).firstOrNull;
          if (variant == null) throw const ValidationException('That variant is not available');
        }
      } else if (variantId != null) {
        throw const ValidationException('This item has no variants');
      }

      final mods = <LineModifier>[];
      if (modifierIds.isNotEmpty) {
        final available = await (_db.select(
          _db.itemModifiers,
        )..where((m) => m.itemId.equals(itemId) & m.archived.equals(false))).get();
        for (final mid in modifierIds.toSet()) {
          final m = available.where((x) => x.id == mid).firstOrNull;
          if (m == null) throw const ValidationException('A selected modifier is no longer available');
          mods.add(LineModifier(id: m.id, name: m.name, price: m.price));
        }
        mods.sort((a, b) => a.name.compareTo(b.name));
      }
      final unitPrice = variant?.price ?? item.price;
      final modTotal = mods.fold<int>(0, (a, m) => a + m.price);
      final tax = await SettingsService(ctx).snapshotFor(item.taxProfileId);
      final taxJson = tax.encode();
      final modsJson = LineModifier.encodeList(mods);
      final now = ctx.nowMs();

      // Merge into an identical, undiscounted line captured at the same price.
      final existing =
          await (_db.select(_db.orderLines)..where(
                (l) =>
                    l.orderId.equals(orderId) &
                    l.itemId.equals(itemId) &
                    l.quantity.isBiggerThanValue(0) &
                    l.lineDiscountType.equals('none') &
                    l.unitPrice.equals(unitPrice) &
                    l.modifiersJson.equals(modsJson) &
                    l.taxJson.equals(taxJson),
              ))
              .get();
      final same = existing.where((l) => l.variantId == variant?.id && l.note == cleanNote).firstOrNull;
      if (same != null) {
        if (same.quantity + quantity > 999) throw const ValidationException('Quantity must be at most 999');
        await (_db.update(_db.orderLines)..where((l) => l.id.equals(same.id))).write(
          OrderLinesCompanion(
            quantity: Value(same.quantity + quantity),
            revision: Value(same.revision + 1),
            updatedAt: Value(now),
          ),
        );
        await _touch(order);
        return same.id;
      }

      final lineId = ctx.ids.newId();
      final count = (await _lines(orderId)).length;
      await _db
          .into(_db.orderLines)
          .insert(
            OrderLinesCompanion.insert(
              id: lineId,
              orderId: orderId,
              itemId: Value(itemId),
              categoryId: Value(item.categoryId),
              categoryName: Value(category?.name),
              itemName: item.name,
              variantId: Value(variant?.id),
              variantName: Value(variant?.name),
              unitPrice: unitPrice,
              modifiersJson: Value(modsJson),
              modifiersUnitTotal: Value(modTotal),
              quantity: quantity,
              note: Value(cleanNote),
              taxJson: taxJson,
              sortOrder: Value(count),
              createdBy: actor.staffId,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _touch(order);
      return lineId;
    });
  }

  /// Bumps the order revision and records the change for the event outbox.
  Future<void> _touch(OrderRow order) async {
    await (_db.update(_db.orders)..where((o) => o.id.equals(order.id))).write(
      OrdersCompanion(
        updatedAt: Value(ctx.nowMs()),
        revision: Value(order.revision + 1),
      ),
    );
    await ctx.outbox.changed(Aggregate.order, order.id);
  }

  Future<(OrderLineRow, OrderRow)> _lineForEdit(String lineId) async {
    final line = await (_db.select(_db.orderLines)..where((l) => l.id.equals(lineId))).getSingleOrNull();
    if (line == null) throw const NotFoundException('Order line not found');
    final order = await _openOrder(line.orderId);
    return (line, order);
  }

  /// Changes a line's quantity. Going below what the kitchen already received
  /// is a void after KOT: it needs a reason and owner approval and produces a
  /// correction ticket immediately.
  Future<void> changeQuantity(
    Actor actor,
    String lineId,
    int newQuantity, {
    String? reason,
    OwnerApproval? approval,
  }) async {
    actor.require(Permission.takeOrders);
    if (newQuantity < 0 || newQuantity > 999) {
      throw const ValidationException('Quantity must be between 0 and 999');
    }
    await _db.transaction(() async {
      final (line, order) = await _lineForEdit(lineId);
      final sent = (await sentQuantities(order.id))[lineId] ?? 0;
      final now = ctx.nowMs();
      if (newQuantity == line.quantity) return;
      if (newQuantity < sent) {
        final why = optionalText(reason, max: 140);
        if (why == null) throw const ValidationException('Give a reason for cancelling items the kitchen already has');
        await ctx.requireOwnerOrApproval(actor, approval, 'cancel items already sent to the kitchen');
        await (_db.update(_db.orderLines)..where((l) => l.id.equals(lineId))).write(
          OrderLinesCompanion(
            quantity: Value(newQuantity),
            revision: Value(line.revision + 1),
            updatedAt: Value(now),
          ),
        );
        await _writeCorrectionTicket(actor, order, [(line, newQuantity - sent)], why);
        await ctx.audit(
          actor,
          'order.void_after_kot',
          entityType: 'order_line',
          entityId: lineId,
          approval: approval,
          details: {'item': line.itemName, 'from': line.quantity, 'to': newQuantity, 'sent': sent, 'reason': why},
        );
      } else if (newQuantity == 0 && sent == 0) {
        // Never sent: a draft line can simply be removed.
        await (_db.delete(_db.orderLines)..where((l) => l.id.equals(lineId))).go();
        await ctx.audit(
          actor,
          'order.line_removed',
          entityType: 'order',
          entityId: order.id,
          details: {'item': line.itemName, 'quantity': line.quantity},
        );
      } else {
        await (_db.update(_db.orderLines)..where((l) => l.id.equals(lineId))).write(
          OrderLinesCompanion(
            quantity: Value(newQuantity),
            revision: Value(line.revision + 1),
            updatedAt: Value(now),
          ),
        );
      }
      await _touch(order);
    });
  }

  Future<void> updateLineNote(Actor actor, String lineId, String? note) async {
    actor.require(Permission.takeOrders);
    await _db.transaction(() async {
      final (line, order) = await _lineForEdit(lineId);
      final sent = (await sentQuantities(order.id))[lineId] ?? 0;
      if (sent > 0) {
        throw const ConflictException('The kitchen already has this line. Add a new line with the new note instead.');
      }
      await (_db.update(_db.orderLines)..where((l) => l.id.equals(lineId))).write(
        OrderLinesCompanion(
          note: Value(optionalText(note, max: 140)),
          revision: Value(line.revision + 1),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await _touch(order);
    });
  }

  Future<void> setLineDiscount(Actor actor, String lineId, Discount discount, {OwnerApproval? approval}) async {
    actor.require(Permission.takeOrders);
    await _db.transaction(() async {
      final (line, order) = await _lineForEdit(lineId);
      await (_db.update(_db.orderLines)..where((l) => l.id.equals(lineId))).write(
        OrderLinesCompanion(
          lineDiscountType: Value(discount.isNone ? 'none' : discount.type.name),
          lineDiscountValue: Value(discount.isNone ? 0 : discount.value),
          revision: Value(line.revision + 1),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await _checkDiscountLimit(actor, order.id, approval);
      await _touch(order);
      await ctx.audit(
        actor,
        'order.line_discount',
        entityType: 'order_line',
        entityId: lineId,
        approval: approval,
        details: {'item': line.itemName, 'type': discount.type.name, 'value': discount.value},
      );
    });
  }

  Future<void> setBillDiscount(
    Actor actor,
    String orderId,
    Discount discount, {
    String? reason,
    OwnerApproval? approval,
  }) async {
    actor.require(Permission.takeOrders);
    await _db.transaction(() async {
      final order = await _openOrder(orderId);
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          billDiscountType: Value(discount.isNone ? 'none' : discount.type.name),
          billDiscountValue: Value(discount.isNone ? 0 : discount.value),
          discountReason: Value(discount.isNone ? null : optionalText(reason, max: 140)),
          updatedAt: Value(ctx.nowMs()),
          revision: Value(order.revision + 1),
        ),
      );
      await _checkDiscountLimit(actor, orderId, approval);
      await ctx.audit(
        actor,
        'order.bill_discount',
        entityType: 'order',
        entityId: orderId,
        approval: approval,
        details: {'type': discount.type.name, 'value': discount.value, 'reason': reason},
      );
      await ctx.outbox.changed(Aggregate.order, orderId);
    });
  }

  /// Validates the discounts price correctly and enforces the cashier limit.
  /// Runs inside the caller's transaction, so a rejection rolls back the edit.
  Future<void> _checkDiscountLimit(Actor actor, String orderId, OwnerApproval? approval) async {
    final order = await _order(orderId);
    final result = engine.price(pricingInputFor(order, await _lines(orderId)));
    final limit = (await ctx.settings()).cashierDiscountLimitBps;
    String? approvedBy;
    // Roles without the discount permission (waiters) need approval for any
    // discount; others only above the cashier limit.
    final needsApproval = actor.can(Permission.discount)
        ? result.discountExceeds(limit)
        : result.discountEnteredTotal > 0;
    if (needsApproval) {
      if (!actor.isOwner) {
        await ctx.verifyApproval(approval, 'give a discount above the cashier limit');
        approvedBy = approval!.ownerId;
      } else {
        approvedBy = actor.staffId;
      }
    }
    await (_db.update(
      _db.orders,
    )..where((o) => o.id.equals(orderId))).write(OrdersCompanion(discountApprovedBy: Value(approvedBy)));
  }

  Future<void> setDeliveryCharge(Actor actor, String orderId, int amount) async {
    actor.require(Permission.discount);
    if (amount < 0) throw const ValidationException('Delivery charge cannot be negative');
    await _db.transaction(() async {
      final order = await _openOrder(orderId);
      if (order.orderType != OrderType.delivery.code) {
        throw const ValidationException('Only delivery orders have a delivery charge');
      }
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          deliveryCharge: Value(amount),
          updatedAt: Value(ctx.nowMs()),
          revision: Value(order.revision + 1),
        ),
      );
      await ctx.audit(
        actor,
        'order.delivery_charge',
        entityType: 'order',
        entityId: orderId,
        details: {'amount': amount},
      );
      await ctx.outbox.changed(Aggregate.order, orderId);
    });
  }

  Future<void> setServiceCharge(Actor actor, String orderId, {required bool enabled}) async {
    actor.require(Permission.discount);
    await _db.transaction(() async {
      final order = await _openOrder(orderId);
      final settings = await ctx.settings();
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          serviceChargeBps: Value(enabled ? settings.serviceChargeBps : 0),
          updatedAt: Value(ctx.nowMs()),
          revision: Value(order.revision + 1),
        ),
      );
      await ctx.audit(
        actor,
        enabled ? 'order.service_charge_on' : 'order.service_charge_off',
        entityType: 'order',
        entityId: orderId,
      );
      await ctx.outbox.changed(Aggregate.order, orderId);
    });
  }

  Future<void> updateDetails(Actor actor, String orderId, {String? customerName, String? note, int? guestCount}) async {
    actor.require(Permission.takeOrders);
    if (guestCount != null && (guestCount < 1 || guestCount > 200)) {
      throw const ValidationException('Guests must be between 1 and 200');
    }
    await _db.transaction(() async {
      final order = await _openOrder(orderId);
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          customerName: Value(optionalText(customerName, max: 60)),
          note: Value(optionalText(note, max: 200)),
          guestCount: Value(guestCount),
          updatedAt: Value(ctx.nowMs()),
          revision: Value(order.revision + 1),
        ),
      );
      await ctx.outbox.changed(Aggregate.order, orderId);
    });
  }

  Future<void> moveToTable(Actor actor, String orderId, String? tableId) async {
    actor.require(Permission.takeOrders);
    try {
      await _db.transaction(() async {
        final order = await _openOrder(orderId);
        if (order.orderType != OrderType.dineIn.code) {
          throw const ValidationException('Only dine-in orders can use a table');
        }
        String? label;
        if (tableId != null) {
          final table = await (_db.select(_db.diningTables)..where((t) => t.id.equals(tableId))).getSingleOrNull();
          if (table == null || table.archived) throw const NotFoundException('Table not found');
          final open = await (_db.select(
            _db.orders,
          )..where((o) => o.tableId.equals(tableId) & o.status.equals(OrderStatus.open))).getSingleOrNull();
          if (open != null && open.id != orderId) throw ConflictException('${table.name} already has an open order');
          label = table.name;
        }
        await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
          OrdersCompanion(
            tableId: Value(tableId),
            tableLabel: Value(label),
            updatedAt: Value(ctx.nowMs()),
            revision: Value(order.revision + 1),
          ),
        );
        await ctx.audit(
          actor,
          'order.moved',
          entityType: 'order',
          entityId: orderId,
          details: {'from': order.tableLabel, 'to': label},
        );
        await ctx.outbox.changed(Aggregate.order, orderId);
      });
    } on Object catch (e) {
      if (isUniqueViolation(e)) throw const ConflictException('That table already has an open order');
      rethrow;
    }
  }

  /// Cancels an open order. If the kitchen already has items, a reason and
  /// owner approval are required and a cancellation ticket is issued.
  Future<void> cancelOrder(Actor actor, String orderId, {required String reason, OwnerApproval? approval}) async {
    actor.require(Permission.takeOrders);
    final why = requireText(reason, 'Reason', max: 140);
    await _db.transaction(() async {
      final order = await _openOrder(orderId);
      final lines = await _lines(orderId);
      final sent = await sentQuantities(orderId);
      final sentLines = [
        for (final l in lines)
          if ((sent[l.id] ?? 0) > 0) (l, -(sent[l.id] ?? 0)),
      ];
      if (sentLines.isNotEmpty) {
        await ctx.requireOwnerOrApproval(actor, approval, 'cancel an order the kitchen has started');
        await _writeCorrectionTicket(actor, order, sentLines, why);
      }
      final now = ctx.now();
      final calendar = await ctx.calendar();
      for (final l in lines) {
        await (_db.update(_db.orderLines)..where((x) => x.id.equals(l.id))).write(
          OrderLinesCompanion(
            quantity: const Value(0),
            revision: Value(l.revision + 1),
            updatedAt: Value(now.millisecondsSinceEpoch),
          ),
        );
      }
      await (_db.update(_db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          status: const Value(OrderStatus.cancelled),
          cancelledAt: Value(now.millisecondsSinceEpoch),
          cancelledBy: Value(actor.staffId),
          cancelReason: Value(why),
          cancelBusinessDate: Value(calendar.businessDateOf(now).key),
          updatedAt: Value(now.millisecondsSinceEpoch),
          revision: Value(order.revision + 1),
        ),
      );
      await ctx.audit(
        actor,
        'order.cancelled',
        entityType: 'order',
        entityId: orderId,
        approval: approval,
        details: {'orderNo': order.orderNo, 'reason': why, 'itemsSentToKitchen': sentLines.length},
      );
      await ctx.outbox.changed(Aggregate.order, orderId);
    });
  }

  // ---- Kitchen tickets --------------------------------------------------------

  /// Sends everything added since the last submission as one immutable ticket.
  /// [operationId] is generated once per tap; retrying with the same id returns
  /// the same ticket instead of creating another. Returns null when there is
  /// nothing new to send.
  Future<String?> sendToKitchen(Actor actor, String orderId, {required String operationId}) async {
    actor.require(Permission.takeOrders);
    final opKey = 'kot:$operationId';
    return _db.transaction(() async {
      final previous = await ctx.completedOperation(opKey);
      if (previous != null) return previous;
      final order = await _openOrder(orderId);
      final lines = await _lines(orderId);
      final sent = await sentQuantities(orderId);
      final additions = [
        for (final l in lines)
          if (l.quantity > (sent[l.id] ?? 0)) (l, l.quantity - (sent[l.id] ?? 0)),
      ];
      if (additions.isEmpty) return null;
      final ticketId = await _writeTicket(actor, order, additions, kind: TicketKind.order, operationId: opKey);
      await ctx.recordOperation(opKey, 'kot', ticketId);
      await ctx.audit(
        actor,
        'kot.sent',
        entityType: 'kitchen_ticket',
        entityId: ticketId,
        details: {'orderNo': order.orderNo, 'lines': additions.length},
      );
      return ticketId;
    });
  }

  Future<String> _writeCorrectionTicket(Actor actor, OrderRow order, List<(OrderLineRow, int)> deltas, String reason) =>
      _writeTicket(actor, order, deltas, kind: TicketKind.correction, reason: reason);

  Future<String> _writeTicket(
    Actor actor,
    OrderRow order,
    List<(OrderLineRow, int)> deltas, {
    required String kind,
    String? reason,
    String? operationId,
  }) async {
    final ticketId = ctx.ids.newId();
    final ticketNo = await _db.nextSequenceValue('kot');
    final now = ctx.now();
    final ref = orderReference(orderNo: order.orderNo, orderType: order.orderType, tableLabel: order.tableLabel);
    await _db
        .into(_db.kitchenTickets)
        .insert(
          KitchenTicketsCompanion.insert(
            id: ticketId,
            orderId: order.id,
            ticketNo: ticketNo,
            kind: kind,
            reason: Value(reason),
            status: TicketStatus.pending,
            operationId: Value(operationId),
            orderRef: ref,
            tableLabel: Value(order.tableLabel),
            createdBy: actor.staffId,
            createdByName: actor.name,
            createdAt: now.millisecondsSinceEpoch,
            updatedAt: now.millisecondsSinceEpoch,
          ),
        );
    final docLines = <KotLineDoc>[];
    for (final (line, delta) in deltas) {
      final mods = LineModifier.decodeList(line.modifiersJson);
      await _db
          .into(_db.kitchenTicketLines)
          .insert(
            KitchenTicketLinesCompanion.insert(
              id: ctx.ids.newId(),
              ticketId: ticketId,
              orderLineId: line.id,
              orderLineRevision: line.revision,
              itemName: line.itemName,
              variantName: Value(line.variantName),
              modifiersText: Value(mods.isEmpty ? null : mods.map((m) => m.name).join(', ')),
              note: Value(line.note),
              quantityDelta: delta,
              unitPrice: line.unitPrice + line.modifiersUnitTotal,
            ),
          );
      docLines.add(
        KotLineDoc(
          quantity: delta,
          name: line.itemName,
          variant: line.variantName,
          modifiers: [for (final m in mods) m.name],
          note: line.note,
          unitPrice: line.unitPrice + line.modifiersUnitTotal,
        ),
      );
    }
    final settings = await ctx.settings();
    if (settings.autoPrintKot) {
      final calendar = await ctx.calendar();
      final doc = KotDocument(
        ticketNo: ticketNo,
        kind: kind,
        orderRef: ref,
        orderTypeLabel: OrderType.parse(order.orderType).label,
        tableLabel: order.tableLabel,
        dateTime: calendar.formatLocal(now),
        staffName: actor.name,
        reason: reason,
        lines: docLines,
        showPrices: settings.kotShowPrices,
        currencyCode: settings.currencyCode,
      );
      await _printJobs.enqueueForRole(
        role: PrinterRole.kot,
        documentType: DocumentType.kot,
        documentRef: ticketId,
        payloadJson: doc.encode(),
        createdBy: actor.staffId,
      );
    }
    // The order's sent quantities changed too.
    await ctx.outbox.changed(Aggregate.ticket, ticketId);
    await ctx.outbox.changed(Aggregate.order, order.id);
    return ticketId;
  }

  /// Rebuilds a ticket's document from its immutable rows (for reprints).
  Future<KotDocument> kotDocument(String ticketId) async {
    final t = await (_db.select(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).getSingleOrNull();
    if (t == null) throw const NotFoundException('Kitchen ticket not found');
    final lines = await (_db.select(_db.kitchenTicketLines)..where((l) => l.ticketId.equals(ticketId))).get();
    final order = await _order(t.orderId);
    final settings = await ctx.settings();
    final calendar = await ctx.calendar();
    return KotDocument(
      ticketNo: t.ticketNo,
      kind: t.kind,
      orderRef: t.orderRef,
      orderTypeLabel: OrderType.parse(order.orderType).label,
      tableLabel: t.tableLabel,
      dateTime: calendar.formatLocal(DateTime.fromMillisecondsSinceEpoch(t.createdAt, isUtc: true)),
      staffName: t.createdByName,
      reason: t.reason,
      showPrices: settings.kotShowPrices,
      currencyCode: settings.currencyCode,
      lines: [
        for (final l in lines)
          KotLineDoc(
            quantity: l.quantityDelta,
            name: l.itemName,
            variant: l.variantName,
            modifiers: l.modifiersText == null ? const [] : l.modifiersText!.split(', '),
            note: l.note,
            unitPrice: l.unitPrice,
          ),
      ],
    );
  }

  Future<List<String>> reprintKot(Actor actor, String ticketId) async {
    actor.require(Permission.kitchenTickets);
    final doc = (await kotDocument(ticketId)).withCopyLabel(CopyLabel.copy);
    return _db.transaction(() async {
      final ids = await _printJobs.enqueueForRole(
        role: PrinterRole.kot,
        documentType: DocumentType.kot,
        documentRef: ticketId,
        payloadJson: doc.encode(),
        copyLabel: CopyLabel.copy,
        createdBy: actor.staffId,
      );
      await ctx.audit(actor, 'kot.reprinted', entityType: 'kitchen_ticket', entityId: ticketId);
      return ids;
    });
  }

  Stream<List<KitchenTicketView>> watchTickets({bool includeReady = true, int limit = 100}) async* {
    yield await tickets(includeReady: includeReady, limit: limit);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.kitchenTickets, _db.kitchenTicketLines]),
    )) {
      yield await tickets(includeReady: includeReady, limit: limit);
    }
  }

  Future<List<KitchenTicketView>> tickets({bool includeReady = true, int limit = 100}) async {
    final q = _db.select(_db.kitchenTickets)
      ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
      ..limit(limit);
    if (!includeReady) q.where((t) => t.status.isNotValue(TicketStatus.ready));
    final ts = await q.get();
    if (ts.isEmpty) return const [];
    final lines = await (_db.select(_db.kitchenTicketLines)..where((l) => l.ticketId.isIn(ts.map((t) => t.id)))).get();
    final byTicket = <String, List<KitchenTicketLineRow>>{};
    for (final l in lines) {
      byTicket.putIfAbsent(l.ticketId, () => []).add(l);
    }
    return [for (final t in ts) KitchenTicketView(ticket: t, lines: byTicket[t.id] ?? const [])];
  }

  /// Who may move a ticket: kitchen staff (and cashiers/admins); when the café
  /// has no kitchen, also the people who take orders, since they prepare them.
  Future<bool> canUpdateTickets(Actor actor) async {
    if (actor.can(Permission.kitchenTickets)) return true;
    return actor.can(Permission.takeOrders) && !(await ctx.settings()).kitchenEnabled;
  }

  Future<void> setTicketStatus(Actor actor, String ticketId, String status) async {
    if (!await canUpdateTickets(actor)) actor.require(Permission.kitchenTickets);
    if (!TicketStatus.all.contains(status)) throw const ValidationException('Unknown ticket status');
    await _db.transaction(() async {
      final t = await (_db.select(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).getSingleOrNull();
      if (t == null) throw const NotFoundException('Kitchen ticket not found');
      if (t.status == status) return;
      await (_db.update(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).write(
        KitchenTicketsCompanion(
          status: Value(status),
          updatedAt: Value(ctx.nowMs()),
          revision: Value(t.revision + 1),
        ),
      );
      await ctx.outbox.changed(Aggregate.ticket, ticketId);
      await ctx.audit(
        actor,
        'kot.status',
        entityType: 'kitchen_ticket',
        entityId: ticketId,
        details: {'from': t.status, 'to': status},
      );
    });
  }

  /// Exposed for checkout and UI previews.
  PricingResult price(OrderRow order, List<OrderLineRow> lines) => engine.price(pricingInputFor(order, lines));

  Future<List<OrderLineRow>> linesOf(String orderId) => _lines(orderId);

  TaxSnapshot decodeTax(String json) => TaxSnapshot.decode(json);
}

class KitchenTicketView {
  const KitchenTicketView({required this.ticket, required this.lines});
  final KitchenTicketRow ticket;
  final List<KitchenTicketLineRow> lines;
}
