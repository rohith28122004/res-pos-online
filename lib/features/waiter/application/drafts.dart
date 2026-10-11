import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/protocol/protocol.dart';
import '../../../core/sync/client_database.dart';
import '../../../core/sync/device_sync.dart';
import '../../../core/time/business_time.dart';

/// One line of an order being put together on the phone. The price is the
/// phone's estimate from its cached menu; the POS decides the real price.
class DraftLine {
  const DraftLine({
    required this.key,
    required this.itemId,
    required this.itemName,
    this.variantId,
    this.variantName,
    this.modifierIds = const [],
    this.modifierNames = const [],
    required this.quantity,
    this.note,
    required this.unitPrice,
  });

  final String key;
  final String itemId;
  final String itemName;
  final String? variantId;
  final String? variantName;
  final List<String> modifierIds;
  final List<String> modifierNames;
  final int quantity;
  final String? note;

  /// Unit price + modifiers, from the cached menu (paise).
  final int unitPrice;

  int get lineTotal => unitPrice * quantity;

  String get description => [
    itemName,
    if (variantName != null) '($variantName)',
    if (modifierNames.isNotEmpty) '+ ${modifierNames.join(', ')}',
  ].join(' ');

  DraftLine copyWith({int? quantity}) => DraftLine(
    key: key,
    itemId: itemId,
    itemName: itemName,
    variantId: variantId,
    variantName: variantName,
    modifierIds: modifierIds,
    modifierNames: modifierNames,
    quantity: quantity ?? this.quantity,
    note: note,
    unitPrice: unitPrice,
  );

  Map<String, Object?> toJson() => {
    'key': key,
    'itemId': itemId,
    'itemName': itemName,
    'variantId': variantId,
    'variantName': variantName,
    'modifierIds': modifierIds,
    'modifierNames': modifierNames,
    'quantity': quantity,
    'note': note,
    'unitPrice': unitPrice,
  };

  static DraftLine fromJson(Map<String, Object?> j) => DraftLine(
    key: j['key']! as String,
    itemId: j['itemId']! as String,
    itemName: j['itemName']! as String,
    variantId: j['variantId'] as String?,
    variantName: j['variantName'] as String?,
    modifierIds: (j['modifierIds'] as List?)?.cast<String>() ?? const [],
    modifierNames: (j['modifierNames'] as List?)?.cast<String>() ?? const [],
    quantity: j['quantity']! as int,
    note: j['note'] as String?,
    unitPrice: j['unitPrice']! as int,
  );

  /// The protocol `Line` (docs/PROTOCOL.md §4.4).
  Map<String, Object?> toProtocol() => {
    'itemId': itemId,
    'variantId': variantId,
    'modifierIds': modifierIds,
    'quantity': quantity,
    'note': note,
    'expectedUnitPrice': unitPrice,
  };
}

/// Drafts on this phone, kept per staff member and per table/order.
class DraftStore {
  DraftStore(this.db, this.clock);

  final ClientDatabase db;
  final Clock clock;
  static const _uuid = Uuid();

  int _now() => clock.nowUtc().millisecondsSinceEpoch;

  Stream<List<DraftRow>> watch(String staffId) =>
      (db.select(db.drafts)..where((d) => d.staffId.equals(staffId))).watch();

  /// The draft for this table / order / takeaway, created if needed.
  Future<DraftRow> open({
    required String staffId,
    required String orderType,
    String? tableId,
    String? tableLabel,
    String? orderId,
  }) async {
    final q = db.select(db.drafts)..where((d) => d.staffId.equals(staffId) & d.orderType.equals(orderType));
    if (orderId != null) {
      q.where((d) => d.orderId.equals(orderId));
    } else if (tableId != null) {
      q.where((d) => d.tableId.equals(tableId) & d.orderId.isNull());
    } else {
      q.where((d) => d.tableId.isNull() & d.orderId.isNull());
    }
    final existing = await q.getSingleOrNull();
    if (existing != null) return existing;
    final now = _now();
    final id = _uuid.v4();
    await db
        .into(db.drafts)
        .insert(
          DraftsCompanion.insert(
            id: id,
            staffId: staffId,
            orderType: orderType,
            tableId: Value(tableId),
            tableLabel: Value(tableLabel),
            orderId: Value(orderId),
            linesJson: '[]',
            createdAt: now,
            updatedAt: now,
          ),
        );
    return (db.select(db.drafts)..where((d) => d.id.equals(id))).getSingle();
  }

  static List<DraftLine> linesOf(DraftRow d) => [
    for (final l in jsonDecode(d.linesJson) as List) DraftLine.fromJson((l! as Map).cast<String, Object?>()),
  ];

  Future<void> save(String id, List<DraftLine> lines, {int? guestCount}) =>
      (db.update(db.drafts)..where((d) => d.id.equals(id))).write(
        DraftsCompanion(
          linesJson: Value(jsonEncode([for (final l in lines) l.toJson()])),
          guestCount: guestCount == null ? const Value.absent() : Value(guestCount),
          updatedAt: Value(_now()),
        ),
      );

  Future<void> delete(String id) => (db.delete(db.drafts)..where((d) => d.id.equals(id))).go();

  /// Turns the draft into a command (saved on the phone, then sent). The
  /// draft is removed; the command keeps its exact content.
  Future<String> send(DeviceSync sync, DraftRow draft, List<DraftLine> lines, {int? guestCount}) async {
    if (lines.isEmpty) throw StateError('Nothing to send');
    final count = lines.fold<int>(0, (a, l) => a + l.quantity);
    final where = draft.tableLabel ?? (draft.orderType == 'takeaway' ? 'Takeaway' : 'Order');
    final summary = '$where: $count item${count == 1 ? '' : 's'}';
    final protocolLines = [for (final l in lines) l.toProtocol()];
    final String id;
    if (draft.orderId != null) {
      id = await sync.enqueue(
        action: CommandAction.orderAdd,
        aggregateId: draft.orderId,
        payload: {'lines': protocolLines, 'sendToKitchen': true},
        summary: '$summary (added)',
      );
    } else {
      id = await sync.enqueue(
        action: CommandAction.orderPlace,
        payload: {
          'orderType': draft.orderType,
          'tableId': ?draft.tableId,
          'guestCount': ?guestCount,
          'lines': protocolLines,
          'sendToKitchen': true,
        },
        summary: summary,
      );
    }
    await delete(draft.id);
    return id;
  }
}
