import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../../../core/pricing/pricing_engine.dart';
import '../../../core/pricing/tax.dart';

enum OrderType {
  dineIn('dine_in', 'Dine-in'),
  takeaway('takeaway', 'Takeaway'),
  delivery('delivery', 'Delivery');

  const OrderType(this.code, this.label);
  final String code;
  final String label;

  static OrderType parse(String code) => OrderType.values.firstWhere((t) => t.code == code);
}

abstract final class OrderStatus {
  static const open = 'open';
  static const finalized = 'finalized';
  static const cancelled = 'cancelled';
}

abstract final class TicketStatus {
  static const pending = 'pending';
  static const preparing = 'preparing';
  static const ready = 'ready';
  static const all = [pending, preparing, ready];

  static String label(String s) => switch (s) {
    pending => 'Pending',
    preparing => 'Preparing',
    ready => 'Ready',
    _ => s,
  };
}

abstract final class TicketKind {
  static const order = 'order';
  static const correction = 'correction';
}

class LineModifier {
  const LineModifier({required this.id, required this.name, required this.price});
  final String id;
  final String name;
  final int price;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'price': price};

  static LineModifier fromJson(Map<String, Object?> j) =>
      LineModifier(id: j['id']! as String, name: j['name']! as String, price: j['price']! as int);

  static List<LineModifier> decodeList(String? text) {
    if (text == null || text.isEmpty) return const [];
    return [for (final m in jsonDecode(text) as List<Object?>) fromJson((m! as Map).cast<String, Object?>())];
  }

  static String encodeList(List<LineModifier> mods) => jsonEncode([for (final m in mods) m.toJson()]);
}

/// Human order reference: "T4 · #23" for tables, "Takeaway #24".
String orderReference({required int orderNo, required String orderType, String? tableLabel}) {
  final type = OrderType.parse(orderType);
  if (type == OrderType.dineIn && tableLabel != null) return '$tableLabel · #$orderNo';
  return '${type.label} #$orderNo';
}

/// Builds the pricing input from persisted order state. Used by the cart
/// preview and by checkout so both always agree.
PricingInput pricingInputFor(OrderRow order, List<OrderLineRow> lines) {
  return PricingInput(
    lines: [
      for (final l in lines)
        if (l.quantity > 0)
          PricingLineInput(
            key: l.id,
            unitPrice: l.unitPrice,
            modifiersUnitTotal: l.modifiersUnitTotal,
            quantity: l.quantity,
            lineDiscount: Discount(DiscountType.parse(l.lineDiscountType), l.lineDiscountValue),
            tax: TaxSnapshot.decode(l.taxJson),
          ),
    ],
    billDiscount: Discount(DiscountType.parse(order.billDiscountType), order.billDiscountValue),
    serviceChargeBps: order.serviceChargeBps,
    serviceChargeTax: TaxSnapshot.decode(order.serviceChargeTaxJson),
    deliveryCharge: order.deliveryCharge,
    deliveryChargeTax: TaxSnapshot.decode(order.deliveryChargeTaxJson),
    roundingUnit: order.roundingUnit,
  );
}

class OrderLineView {
  const OrderLineView({required this.row, required this.sentQuantity, required this.modifiers});
  final OrderLineRow row;

  /// Net quantity already submitted to the kitchen.
  final int sentQuantity;
  final List<LineModifier> modifiers;

  int get unsentQuantity => row.quantity - sentQuantity;
  bool get lockedByKitchen => sentQuantity > 0;
}

class OrderDetail {
  const OrderDetail({required this.order, required this.lines, required this.pricing, this.pricingError});

  final OrderRow order;
  final List<OrderLineView> lines;
  final PricingResult? pricing;
  final String? pricingError;

  List<OrderLineView> get activeLines => lines.where((l) => l.row.quantity > 0).toList();
  bool get hasUnsentItems => lines.any((l) => l.unsentQuantity > 0);
  bool get hasKitchenItems => lines.any((l) => l.sentQuantity > 0);
  String get reference =>
      orderReference(orderNo: order.orderNo, orderType: order.orderType, tableLabel: order.tableLabel);
}

class OpenOrderSummary {
  const OpenOrderSummary({
    required this.order,
    required this.itemCount,
    required this.total,
    required this.hasUnsent,
  });

  final OrderRow order;
  final int itemCount;
  final int total;
  final bool hasUnsent;

  String get reference =>
      orderReference(orderNo: order.orderNo, orderType: order.orderType, tableLabel: order.tableLabel);
}
