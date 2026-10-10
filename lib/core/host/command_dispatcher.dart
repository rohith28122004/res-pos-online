import 'dart:convert';

import 'package:drift/drift.dart';

import '../../features/orders/application/order_service.dart';
import '../../features/orders/domain/order_models.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../protocol/protocol.dart';
import '../security/permissions.dart';
import '../service_context.dart';
import '../sync/host_outbox.dart';
import 'approvals.dart';

/// Device kinds that can be paired with the host.
abstract final class DeviceRole {
  static const waiter = 'waiter';
  static const kitchen = 'kitchen';
  static const all = {waiter, kitchen};
}

/// Who is calling: established by the transport layer from a verified device
/// credential and a verified, live staff session — never from the request
/// body.
class RemoteCaller {
  const RemoteCaller({
    required this.deviceId,
    required this.deviceRole,
    required this.actor,
    required this.sessionId,
  });

  final String deviceId;
  final String deviceRole;
  final Actor actor;
  final String sessionId;
}

/// Runs remote commands (docs/PROTOCOL.md §4) on the POS host through the
/// existing services. One transaction per command holds the business change,
/// the command receipt and the outbox events.
class CommandDispatcher {
  CommandDispatcher(this.ctx, {OrderService? orders, ApprovalRegistry? approvals})
    : orders = orders ?? OrderService(ctx),
      approvals = approvals ?? ApprovalRegistry(ctx.clock);

  final ServiceContext ctx;
  final OrderService orders;
  final ApprovalRegistry approvals;

  AppDatabase get _db => ctx.db;

  /// Codes that are business outcomes: stored so the same command always gets
  /// the same answer.
  static const _storedCodes = {
    ErrorCode.validation,
    ErrorCode.staleRevision,
    ErrorCode.tableOccupied,
    ErrorCode.orderClosed,
    ErrorCode.priceChanged,
    ErrorCode.itemUnavailable,
    ErrorCode.approvalRequired,
    ErrorCode.transitionNotAllowed,
    ErrorCode.conflict,
    ErrorCode.notFound,
  };

  static bool deviceMayRun(String deviceRole, String action) => switch (action) {
    CommandAction.ticketSetStatus => deviceRole == DeviceRole.kitchen,
    _ => deviceRole == DeviceRole.waiter,
  };

  static Permission permissionFor(String action) =>
      action == CommandAction.ticketSetStatus ? Permission.kitchenTickets : Permission.takeOrders;

  /// Handles [raw] (decoded JSON). Throws [ProtocolException] for failures
  /// that are not business outcomes (auth, version, epoch, id reuse).
  Future<CommandResult> handle(RemoteCaller caller, Object? raw) async {
    final command = Command.parse(raw);
    final identity = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (identity == null) {
      throw const ProtocolException(ErrorCode.forbidden, 'This POS is not set up for connected devices');
    }
    if (identity.reconcileRequired) {
      throw const ProtocolException(
        ErrorCode.epochChanged,
        'The POS was restored from a backup. The owner must reconnect devices on the POS first.',
      );
    }
    if (command.restaurantId != identity.restaurantId ||
        command.deviceId != caller.deviceId ||
        command.staffId != caller.actor.staffId) {
      throw const ProtocolException(ErrorCode.forbidden, 'This command does not belong to this device or account');
    }
    if (command.hostEpoch != identity.hostEpoch) {
      throw ProtocolException(
        ErrorCode.epochChanged,
        'The POS was restored since this was created. Check it before sending again.',
        details: {'hostEpoch': identity.hostEpoch},
      );
    }
    if (!deviceMayRun(caller.deviceRole, command.action) || !caller.actor.can(permissionFor(command.action))) {
      throw ProtocolException(
        ErrorCode.forbidden,
        '${caller.actor.role.label} accounts on a ${caller.deviceRole} device cannot do this',
      );
    }
    final hash = command.bodyHash;

    return _db.transaction(() async {
      final previous = await (_db.select(
        _db.commandReceipts,
      )..where((r) => r.commandId.equals(command.commandId))).getSingleOrNull();
      if (previous != null) {
        if (previous.bodyHash != hash) {
          throw const ProtocolException(
            ErrorCode.commandIdReused,
            'This command id was already used for a different request',
          );
        }
        return CommandResult.fromJson((jsonDecode(previous.resultJson) as Map).cast<String, Object?>());
      }

      CommandResult result;
      try {
        final (outcome, lastSequence) = await _db.transaction(
          () => ctx.outbox.batch(() => _run(command, caller)),
        );
        result = CommandResult(
          commandId: command.commandId,
          state: ResultState.accepted,
          hostEpoch: identity.hostEpoch,
          resultId: outcome.resultId,
          revision: outcome.revision,
          eventSequence: lastSequence,
          acceptedAt: ctx.nowMs(),
          result: outcome.data,
        );
      } on ProtocolException catch (e) {
        if (!_storedCodes.contains(e.code)) rethrow;
        result = _rejected(command, identity.hostEpoch, e);
      } on PermissionDeniedException catch (e) {
        throw ProtocolException(ErrorCode.forbidden, e.message);
      } on ApprovalRequiredException catch (e) {
        result = _rejected(command, identity.hostEpoch, ProtocolException(ErrorCode.approvalRequired, e.message));
      } on ValidationException catch (e) {
        result = _rejected(command, identity.hostEpoch, ProtocolException(ErrorCode.validation, e.message));
      } on NotFoundException catch (e) {
        result = _rejected(command, identity.hostEpoch, ProtocolException(ErrorCode.notFound, e.message));
      } on ConflictException catch (e) {
        result = _rejected(command, identity.hostEpoch, ProtocolException(ErrorCode.conflict, e.message));
      }

      await _db
          .into(_db.commandReceipts)
          .insert(
            CommandReceiptsCompanion.insert(
              commandId: command.commandId,
              bodyHash: hash,
              action: command.action,
              deviceId: caller.deviceId,
              staffId: caller.actor.staffId,
              hostEpoch: identity.hostEpoch,
              state: result.state,
              resultJson: jsonEncode(result.toJson()),
              receivedAt: ctx.nowMs(),
            ),
          );
      if (result.accepted) {
        await ctx.audit(
          caller.actor,
          'remote.${command.action}',
          entityType: 'command',
          entityId: command.commandId,
          details: {'device': caller.deviceId, 'resultId': result.resultId},
        );
      }
      return result;
    });
  }

  /// The stored result of a command this device sent, or null if the host
  /// never committed it.
  Future<CommandResult?> lookup(RemoteCaller caller, String commandId) async {
    final row = await (_db.select(
      _db.commandReceipts,
    )..where((r) => r.commandId.equals(commandId) & r.deviceId.equals(caller.deviceId))).getSingleOrNull();
    if (row == null) return null;
    return CommandResult.fromJson((jsonDecode(row.resultJson) as Map).cast<String, Object?>());
  }

  CommandResult _rejected(Command c, int epoch, ProtocolException e) =>
      CommandResult(commandId: c.commandId, state: ResultState.rejected, hostEpoch: epoch, error: e);

  // ---- Actions ----------------------------------------------------------------

  Future<_Outcome> _run(Command c, RemoteCaller caller) => switch (c.action) {
    CommandAction.orderPlace => _place(c, caller),
    CommandAction.orderAdd => _add(c, caller),
    CommandAction.orderChangeQuantity => _changeQuantity(c, caller),
    CommandAction.orderSendToKitchen => _sendToKitchen(c, caller),
    CommandAction.ticketSetStatus => _ticketStatus(c, caller),
    _ => throw ProtocolException(ErrorCode.updateRequired, 'Unknown action ${c.action}'),
  };

  Future<_Outcome> _place(Command c, RemoteCaller caller) async {
    final p = c.payload;
    if (c.aggregateId != null || c.expectedRevision != null) {
      throw const ProtocolException(ErrorCode.validation, 'A new order has no aggregateId or expectedRevision');
    }
    final type = switch (p['orderType']) {
      'dine_in' => OrderType.dineIn,
      'takeaway' => OrderType.takeaway,
      _ => throw const ProtocolException(ErrorCode.validation, 'orderType must be dine_in or takeaway'),
    };
    final tableId = optionalId(p, 'tableId');
    if (tableId != null && type != OrderType.dineIn) {
      throw const ProtocolException(ErrorCode.validation, 'Only dine-in orders can use a table');
    }
    final guests = optionalInt(p, 'guestCount', min: 1, max: 200);
    final note = optionalString(p, 'note');
    final lines = _parseLines(p);
    final send = _sendFlag(p);

    if (tableId != null) {
      final table = await (_db.select(_db.diningTables)..where((t) => t.id.equals(tableId))).getSingleOrNull();
      if (table == null || table.archived) throw const ProtocolException(ErrorCode.notFound, 'Table not found');
      final open = await (_db.select(
        _db.orders,
      )..where((o) => o.tableId.equals(tableId) & o.status.equals(OrderStatus.open))).getSingleOrNull();
      if (open != null) {
        throw ProtocolException(
          ErrorCode.tableOccupied,
          '${table.name} already has an open order (#${open.orderNo})',
          details: {
            'orderId': open.id,
            'orderNo': open.orderNo,
            'revision': open.revision,
            'createdByName': open.createdByName,
          },
        );
      }
    }
    await _checkLines(lines);

    final orderId = await orders.createOrder(caller.actor, type: type, tableId: tableId);
    if (guests != null || note != null) {
      await orders.updateDetails(caller.actor, orderId, guestCount: guests, note: note);
    }
    return _addAndSend(c, caller, orderId, lines, send);
  }

  Future<_Outcome> _add(Command c, RemoteCaller caller) async {
    final order = await _openOrderFor(c);
    final lines = _parseLines(c.payload);
    final send = _sendFlag(c.payload);
    await _checkLines(lines);
    return _addAndSend(c, caller, order.id, lines, send);
  }

  Future<_Outcome> _addAndSend(Command c, RemoteCaller caller, String orderId, List<_Line> lines, bool send) async {
    for (final l in lines) {
      await orders.addItem(
        caller.actor,
        orderId,
        itemId: l.itemId,
        variantId: l.variantId,
        modifierIds: l.modifierIds,
        quantity: l.quantity,
        note: l.note,
      );
    }
    String? ticketId;
    if (send) {
      ticketId = await orders.sendToKitchen(caller.actor, orderId, operationId: 'cmd:${c.commandId}');
    }
    return _orderOutcome(orderId, ticketId);
  }

  Future<_Outcome> _changeQuantity(Command c, RemoteCaller caller) async {
    if (c.expectedRevision == null) {
      throw const ProtocolException(ErrorCode.validation, 'expectedRevision is required to change a line');
    }
    final order = await _openOrderFor(c);
    final p = c.payload;
    final lineId = requireId(p, 'lineId');
    final quantity = requireInt(p, 'quantity', min: 0, max: 999);
    final reason = optionalString(p, 'reason', maxLength: 140);
    final approvalId = optionalId(p, 'approvalId');
    final line = await (_db.select(_db.orderLines)..where((l) => l.id.equals(lineId))).getSingleOrNull();
    if (line == null || line.orderId != order.id) {
      throw const ProtocolException(ErrorCode.notFound, 'That line is not on this order');
    }
    final approval = approvalId == null ? null : approvals.consume(approvalId, caller.deviceId);
    if (approvalId != null && approval == null) {
      throw const ProtocolException(ErrorCode.approvalRequired, 'The owner approval has expired or was already used');
    }
    final ticketsBefore = await _ticketIdsOf(order.id);
    await orders.changeQuantity(caller.actor, lineId, quantity, reason: reason, approval: approval);
    final created = (await _ticketIdsOf(order.id)).difference(ticketsBefore);
    return _orderOutcome(order.id, created.isEmpty ? null : created.first);
  }

  Future<_Outcome> _sendToKitchen(Command c, RemoteCaller caller) async {
    final order = await _openOrderFor(c);
    final ticketId = await orders.sendToKitchen(caller.actor, order.id, operationId: 'cmd:${c.commandId}');
    return _orderOutcome(order.id, ticketId);
  }

  static const _statusRank = {TicketStatus.pending: 0, TicketStatus.preparing: 1, TicketStatus.ready: 2};

  Future<_Outcome> _ticketStatus(Command c, RemoteCaller caller) async {
    final ticketId = c.aggregateId;
    if (ticketId == null) throw const ProtocolException(ErrorCode.validation, 'aggregateId (ticket) is required');
    if (c.expectedRevision == null) {
      throw const ProtocolException(ErrorCode.validation, 'expectedRevision is required to change a ticket');
    }
    final status = c.payload['status'];
    if (status != TicketStatus.preparing && status != TicketStatus.ready) {
      throw const ProtocolException(ErrorCode.validation, 'status must be preparing or ready');
    }
    final t = await (_db.select(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).getSingleOrNull();
    if (t == null) throw const ProtocolException(ErrorCode.notFound, 'Kitchen ticket not found');
    if (t.revision != c.expectedRevision) {
      throw ProtocolException(
        ErrorCode.staleRevision,
        'This ticket changed on another screen',
        details: {'ticket': await EventViews(ctx).ticketView(t.id)},
      );
    }
    if ((_statusRank[status]! <= (_statusRank[t.status] ?? 0))) {
      throw ProtocolException(
        ErrorCode.transitionNotAllowed,
        'This ticket is already ${TicketStatus.label(t.status).toLowerCase()}',
        details: {'ticket': await EventViews(ctx).ticketView(t.id)},
      );
    }
    await orders.setTicketStatus(caller.actor, ticketId, status! as String);
    final after = await (_db.select(_db.kitchenTickets)..where((k) => k.id.equals(ticketId))).getSingle();
    return _Outcome(
      resultId: ticketId,
      revision: after.revision,
      data: {'ticketId': ticketId, 'status': after.status, 'revision': after.revision},
    );
  }

  // ---- Helpers ------------------------------------------------------------------

  Future<OrderRow> _openOrderFor(Command c) async {
    final id = c.aggregateId;
    if (id == null) throw const ProtocolException(ErrorCode.validation, 'aggregateId (order) is required');
    final order = await (_db.select(_db.orders)..where((o) => o.id.equals(id))).getSingleOrNull();
    if (order == null) throw const ProtocolException(ErrorCode.notFound, 'Order not found');
    if (order.status != OrderStatus.open) {
      throw ProtocolException(
        ErrorCode.orderClosed,
        order.status == OrderStatus.finalized ? 'This order has already been billed' : 'This order was cancelled',
        details: {'status': order.status},
      );
    }
    if (c.expectedRevision != null && c.expectedRevision != order.revision) {
      throw ProtocolException(
        ErrorCode.staleRevision,
        'Someone else changed this order first',
        details: {'currentRevision': order.revision, 'order': await EventViews(ctx).orderView(order.id)},
      );
    }
    return order;
  }

  Future<Set<String>> _ticketIdsOf(String orderId) async =>
      (await (_db.select(_db.kitchenTickets)..where((t) => t.orderId.equals(orderId))).get()).map((t) => t.id).toSet();

  Future<_Outcome> _orderOutcome(String orderId, String? ticketId) async {
    final o = await (_db.select(_db.orders)..where((x) => x.id.equals(orderId))).getSingle();
    final view = await EventViews(ctx).orderView(orderId);
    int? ticketNo;
    if (ticketId != null) {
      ticketNo = (await (_db.select(_db.kitchenTickets)..where((t) => t.id.equals(ticketId))).getSingle()).ticketNo;
    }
    return _Outcome(
      resultId: orderId,
      revision: o.revision,
      data: {
        'orderId': orderId,
        'orderNo': o.orderNo,
        'orderRef': view!['orderRef'],
        'revision': o.revision,
        'ticketId': ticketId,
        'ticketNo': ticketNo,
        'estimatedTotal': view['estimatedTotal'],
      },
    );
  }

  static bool _sendFlag(Map<String, Object?> p) {
    final v = p['sendToKitchen'];
    if (v == null) return true;
    if (v is! bool) throw const ProtocolException(ErrorCode.validation, 'sendToKitchen must be true or false');
    return v;
  }

  static const maxLines = 50;

  static List<_Line> _parseLines(Map<String, Object?> p) {
    final raw = requireList(p, 'lines', maxLength: maxLines);
    if (raw.isEmpty) throw const ProtocolException(ErrorCode.validation, 'Add at least one item');
    return [
      for (final r in raw)
        if (r is Map)
          _Line.parse(r.cast<String, Object?>())
        else
          throw const ProtocolException(ErrorCode.validation, 'Each line must be an object'),
    ];
  }

  /// Validates availability and the price each line was shown at, against the
  /// host's menu. Nothing is written if any line fails.
  Future<void> _checkLines(List<_Line> lines) async {
    final unavailable = <Map<String, Object?>>[];
    final changed = <Map<String, Object?>>[];
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      final item = await (_db.select(_db.menuItems)..where((m) => m.id.equals(l.itemId))).getSingleOrNull();
      String? reason;
      int? unit;
      if (item == null || item.archived) {
        reason = 'removed';
      } else if (!item.available) {
        reason = 'sold_out';
      } else {
        final variants = await (_db.select(
          _db.itemVariants,
        )..where((v) => v.itemId.equals(item.id) & v.archived.equals(false))).get();
        ItemVariantRow? variant;
        if (variants.isEmpty) {
          if (l.variantId != null) reason = 'variant_unavailable';
        } else if (l.variantId == null) {
          if (variants.length == 1) {
            variant = variants.single;
          } else {
            reason = 'choose_variant';
          }
        } else {
          variant = variants.where((v) => v.id == l.variantId).firstOrNull;
          if (variant == null) reason = 'variant_unavailable';
        }
        if (reason == null) {
          final mods = await (_db.select(
            _db.itemModifiers,
          )..where((m) => m.itemId.equals(item.id) & m.archived.equals(false))).get();
          var modTotal = 0;
          for (final id in l.modifierIds) {
            final m = mods.where((x) => x.id == id).firstOrNull;
            if (m == null) {
              reason = 'modifier_unavailable';
              break;
            }
            modTotal += m.price;
          }
          unit = (variant?.price ?? item.price) + modTotal;
        }
      }
      if (reason != null) {
        unavailable.add({'index': i, 'itemId': l.itemId, 'itemName': item?.name, 'reason': reason});
      } else if (unit != l.expectedUnitPrice) {
        changed.add({
          'index': i,
          'itemId': l.itemId,
          'itemName': item!.name,
          'expected': l.expectedUnitPrice,
          'current': unit,
        });
      }
    }
    if (unavailable.isNotEmpty) {
      throw ProtocolException(
        ErrorCode.itemUnavailable,
        'Some items are no longer available',
        details: {'lines': unavailable},
      );
    }
    if (changed.isNotEmpty) {
      throw ProtocolException(
        ErrorCode.priceChanged,
        'Prices changed. Check the new prices and send again.',
        details: {'lines': changed},
      );
    }
  }
}

class _Outcome {
  const _Outcome({required this.resultId, required this.revision, required this.data});
  final String resultId;
  final int revision;
  final Map<String, Object?> data;
}

class _Line {
  const _Line({
    required this.itemId,
    required this.variantId,
    required this.modifierIds,
    required this.quantity,
    required this.note,
    required this.expectedUnitPrice,
  });

  final String itemId;
  final String? variantId;
  final List<String> modifierIds;
  final int quantity;
  final String? note;
  final int expectedUnitPrice;

  static _Line parse(Map<String, Object?> j) {
    final mods = requireList(j, 'modifierIds', maxLength: 20);
    final ids = <String>[];
    for (final m in mods) {
      if (m is! String || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(m)) {
        throw const ProtocolException(ErrorCode.validation, 'modifierIds must be ids');
      }
      if (!ids.contains(m)) ids.add(m);
    }
    return _Line(
      itemId: requireId(j, 'itemId'),
      variantId: optionalId(j, 'variantId'),
      modifierIds: ids,
      quantity: requireInt(j, 'quantity', min: 1, max: 99),
      note: optionalString(j, 'note', maxLength: 140),
      expectedUnitPrice: requireInt(j, 'expectedUnitPrice', min: 0),
    );
  }
}
