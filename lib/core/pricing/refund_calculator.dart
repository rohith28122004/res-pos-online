/// Refund reversal maths. Reverses the *captured* amounts of the original
/// bill (never today's menu prices), proportionally per refunded unit.
///
/// Each amount uses the cumulative-share method: the refund for quantities
/// (before, after] is share(after) − share(before), where
/// share(k) = round_half_up(original × k / quantity). Consequences:
///  * amounts are never negative,
///  * cumulative partial refunds can never exceed the original,
///  * once every unit is refunded the totals match the original exactly.
library;

import '../errors/app_exception.dart';
import '../money/money.dart';

class RefundableComponent {
  const RefundableComponent({
    required this.id,
    required this.name,
    required this.rateBps,
    required this.amount,
  });

  /// bill_tax_components.id of the original component.
  final String id;
  final String name;
  final int rateBps;
  final int amount;
}

class RefundableLine {
  const RefundableLine({
    required this.billLineId,
    required this.quantity,
    required this.netEx,
    required this.discountEx,
    required this.components,
    required this.alreadyRefundedQuantity,
  });

  final String billLineId;
  final int quantity;
  final int netEx;
  final int discountEx;
  final List<RefundableComponent> components;
  final int alreadyRefundedQuantity;

  int get remainingQuantity => quantity - alreadyRefundedQuantity;
}

class ComponentRefund {
  const ComponentRefund({required this.component, required this.amount});
  final RefundableComponent component;
  final int amount;
}

class LineRefundAmounts {
  const LineRefundAmounts({
    required this.billLineId,
    required this.quantity,
    required this.netEx,
    required this.discountEx,
    required this.components,
  });

  final String billLineId;
  final int quantity;
  final int netEx;
  final int discountEx;
  final List<ComponentRefund> components;

  int get grossEx => netEx + discountEx;
  int get tax => components.fold(0, (a, c) => a + c.amount);
  int get total => netEx + tax;
}

LineRefundAmounts computeLineRefund(RefundableLine line, int refundQuantity) {
  if (refundQuantity <= 0) {
    throw const ValidationException('Refund quantity must be at least 1');
  }
  if (refundQuantity > line.remainingQuantity) {
    throw ValidationException('Only ${line.remainingQuantity} of ${line.quantity} can still be refunded on this line');
  }
  final before = line.alreadyRefundedQuantity;
  final after = before + refundQuantity;
  int share(int total) => cumulativeShare(total, after, line.quantity) - cumulativeShare(total, before, line.quantity);
  return LineRefundAmounts(
    billLineId: line.billLineId,
    quantity: refundQuantity,
    netEx: share(line.netEx),
    discountEx: share(line.discountEx),
    components: [
      for (final c in line.components) ComponentRefund(component: c, amount: share(c.amount)),
    ],
  );
}

/// Splits [total] over the original payment methods as a default refund
/// tender, capped by what is still refundable per method. Largest remainder,
/// in the order given.
Map<String, int> defaultRefundTender(int total, Map<String, int> refundableByMethod) {
  final methods = refundableByMethod.keys.toList();
  final caps = [for (final m in methods) refundableByMethod[m]!];
  final available = caps.fold<int>(0, (a, b) => a + b);
  if (total > available) {
    throw const ValidationException('Refund is larger than the payments left on this bill');
  }
  if (total == 0) return {for (final m in methods) m: 0};
  final shares = allocateLargestRemainder(total, caps);
  return {for (var i = 0; i < methods.length; i++) methods[i]: shares[i]};
}
