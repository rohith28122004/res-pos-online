/// The single pricing engine used for the cart preview, checkout, receipts,
/// refunds and tests. Pure Dart, integer minor units only.
///
/// Calculation order (see docs/PRICING.md):
///  1. line gross (entered) = (unit price + modifiers) × quantity
///  2. line discount (amount, or % of line gross, half-up)
///  3. bill discount (amount, or % of eligible base, half-up) allocated over
///     eligible lines by largest remainder, weights = line gross − line discount
///  4. tax per line on the discounted entered amount, by the line's captured
///     tax snapshot (inclusive / exclusive / disabled), components by largest
///     remainder
///  5. service charge = % of Σ line net (tax-exclusive), then its own tax
///  6. delivery charge (fixed entered amount), then its own tax
///  7. optional payable rounding to a unit (default none), stored separately
library;

import '../errors/app_exception.dart';
import '../money/money.dart';
import 'tax.dart';

enum DiscountType {
  none,
  amount,
  percent;

  static DiscountType parse(String value) =>
      DiscountType.values.firstWhere((d) => d.name == value, orElse: () => DiscountType.none);
}

/// Amount discounts are in minor units; percent discounts are in basis points.
class Discount {
  const Discount(this.type, this.value);
  const Discount.amount(int minor) : this(DiscountType.amount, minor);
  const Discount.percent(int bps) : this(DiscountType.percent, bps);

  static const none = Discount(DiscountType.none, 0);

  final DiscountType type;
  final int value;

  bool get isNone => type == DiscountType.none || value == 0;

  int resolve(int base) {
    switch (type) {
      case DiscountType.none:
        return 0;
      case DiscountType.amount:
        if (value < 0) throw const ValidationException('Discount cannot be negative');
        if (value > base) {
          throw const ValidationException('Discount is larger than the amount it applies to');
        }
        return value;
      case DiscountType.percent:
        if (value < 0 || value > bpsDenominator) {
          throw const ValidationException('Discount percentage must be between 0% and 100%');
        }
        return applyBps(base, value);
    }
  }
}

class PricingLineInput {
  const PricingLineInput({
    required this.key,
    required this.unitPrice,
    required this.quantity,
    this.modifiersUnitTotal = 0,
    this.lineDiscount = Discount.none,
    this.billDiscountEligible = true,
    this.tax = TaxSnapshot.none,
  });

  final String key;

  /// Base or variant price, in the tax snapshot's mode.
  final int unitPrice;
  final int modifiersUnitTotal;
  final int quantity;
  final Discount lineDiscount;
  final bool billDiscountEligible;
  final TaxSnapshot tax;
}

class PricingInput {
  const PricingInput({
    required this.lines,
    this.billDiscount = Discount.none,
    this.serviceChargeBps = 0,
    this.serviceChargeTax = TaxSnapshot.none,
    this.deliveryCharge = 0,
    this.deliveryChargeTax = TaxSnapshot.none,
    this.roundingUnit = 0,
  });

  final List<PricingLineInput> lines;
  final Discount billDiscount;
  final int serviceChargeBps;
  final TaxSnapshot serviceChargeTax;
  final int deliveryCharge;
  final TaxSnapshot deliveryChargeTax;

  /// 0 = no payable rounding. 100 = round the payable to the nearest ₹1.
  final int roundingUnit;
}

class PricedLine {
  const PricedLine({
    required this.key,
    required this.quantity,
    required this.unitPriceEntered,
    required this.grossEntered,
    required this.lineDiscountEntered,
    required this.billDiscountEntered,
    required this.grossEx,
    required this.discountEx,
    required this.netEx,
    required this.tax,
    required this.components,
    required this.taxSnapshot,
  });

  final String key;
  final int quantity;

  /// unit price + modifiers, as entered (tax-inclusive for inclusive lines).
  final int unitPriceEntered;
  final int grossEntered;
  final int lineDiscountEntered;
  final int billDiscountEntered;

  /// Pre-discount, tax-exclusive value. grossEx − discountEx == netEx.
  final int grossEx;
  final int discountEx;
  final int netEx;
  final int tax;
  final List<TaxComponentAmount> components;
  final TaxSnapshot taxSnapshot;

  int get netEntered => grossEntered - lineDiscountEntered - billDiscountEntered;
  int get discountEntered => lineDiscountEntered + billDiscountEntered;

  /// What the customer pays for this line.
  int get total => netEx + tax;
}

enum ChargeKind {
  service,
  delivery;

  static ChargeKind parse(String v) => ChargeKind.values.firstWhere((k) => k.name == v);
}

class PricedCharge {
  const PricedCharge({
    required this.kind,
    required this.label,
    required this.amountEntered,
    required this.netEx,
    required this.tax,
    required this.components,
    required this.taxSnapshot,
  });

  final ChargeKind kind;
  final String label;
  final int amountEntered;
  final int netEx;
  final int tax;
  final List<TaxComponentAmount> components;
  final TaxSnapshot taxSnapshot;

  int get total => netEx + tax;
}

class TaxBreakdownRow {
  const TaxBreakdownRow({required this.name, required this.rateBps, required this.amount});
  final String name;
  final int rateBps;
  final int amount;
}

class PricingResult {
  const PricingResult({
    required this.lines,
    required this.charges,
    required this.billDiscountEntered,
    required this.subtotalBeforeRounding,
    required this.roundingAdjustment,
  });

  final List<PricedLine> lines;
  final List<PricedCharge> charges;
  final int billDiscountEntered;
  final int subtotalBeforeRounding;
  final int roundingAdjustment;

  int get total => subtotalBeforeRounding + roundingAdjustment;

  int get itemsGrossEntered => _sum(lines.map((l) => l.grossEntered));
  int get lineDiscountsEntered => _sum(lines.map((l) => l.lineDiscountEntered));
  int get discountEnteredTotal => lineDiscountsEntered + billDiscountEntered;
  int get itemsGrossEx => _sum(lines.map((l) => l.grossEx));
  int get itemsDiscountEx => _sum(lines.map((l) => l.discountEx));
  int get itemsNetEx => _sum(lines.map((l) => l.netEx));
  int get itemsTax => _sum(lines.map((l) => l.tax));
  int get chargesNetEx => _sum(charges.map((c) => c.netEx));
  int get chargesTax => _sum(charges.map((c) => c.tax));
  int get taxTotal => itemsTax + chargesTax;
  int get itemCount => _sum(lines.map((l) => l.quantity));

  /// Tax aggregated by component name + rate, for receipts.
  List<TaxBreakdownRow> get taxBreakdown {
    final map = <(String, int), int>{};
    for (final c in [
      for (final l in lines) ...l.components,
      for (final ch in charges) ...ch.components,
    ]) {
      map.update((c.name, c.rateBps), (v) => v + c.amount, ifAbsent: () => c.amount);
    }
    final rows =
        [
          for (final e in map.entries) TaxBreakdownRow(name: e.key.$1, rateBps: e.key.$2, amount: e.value),
        ]..sort((a, b) {
          final byRate = a.rateBps.compareTo(b.rateBps);
          return byRate != 0 ? byRate : a.name.compareTo(b.name);
        });
    return rows;
  }

  /// True when the total entered discount exceeds [limitBps] of the gross.
  bool discountExceeds(int limitBps) => discountEnteredTotal * bpsDenominator > limitBps * itemsGrossEntered;

  static int _sum(Iterable<int> values) => values.fold(0, (a, b) => a + b);
}

class PricingEngine {
  const PricingEngine();

  PricingResult price(PricingInput input) {
    for (final line in input.lines) {
      if (line.quantity <= 0) {
        throw const ValidationException('Quantity must be at least 1');
      }
      if (line.unitPrice < 0 || line.modifiersUnitTotal < 0) {
        throw const ValidationException('Prices cannot be negative');
      }
      line.tax.validate();
    }
    input.serviceChargeTax.validate();
    input.deliveryChargeTax.validate();
    if (input.serviceChargeBps < 0 || input.serviceChargeBps > bpsDenominator) {
      throw const ValidationException('Service charge must be between 0% and 100%');
    }
    if (input.deliveryCharge < 0) {
      throw const ValidationException('Delivery charge cannot be negative');
    }
    if (input.roundingUnit < 0) {
      throw const ValidationException('Rounding unit cannot be negative');
    }

    // 1-2. Gross and line discounts.
    final gross = <int>[];
    final lineDiscounts = <int>[];
    for (final line in input.lines) {
      final unit = line.unitPrice + line.modifiersUnitTotal;
      final g = unit * line.quantity;
      gross.add(g);
      lineDiscounts.add(line.lineDiscount.resolve(g));
    }

    // 3. Bill discount allocation.
    final weights = <int>[
      for (var i = 0; i < input.lines.length; i++)
        input.lines[i].billDiscountEligible ? gross[i] - lineDiscounts[i] : 0,
    ];
    final eligibleBase = weights.fold<int>(0, (a, b) => a + b);
    final billDiscount = input.billDiscount.resolve(eligibleBase);
    final billShares = billDiscount == 0
        ? List<int>.filled(input.lines.length, 0)
        : allocateLargestRemainder(billDiscount, weights);

    // 4. Tax per line.
    final priced = <PricedLine>[];
    for (var i = 0; i < input.lines.length; i++) {
      final line = input.lines[i];
      final netEntered = gross[i] - lineDiscounts[i] - billShares[i];
      assert(netEntered >= 0);
      final split = splitTax(netEntered, line.tax);
      final grossEx = exclusiveValue(gross[i], line.tax);
      priced.add(
        PricedLine(
          key: line.key,
          quantity: line.quantity,
          unitPriceEntered: line.unitPrice + line.modifiersUnitTotal,
          grossEntered: gross[i],
          lineDiscountEntered: lineDiscounts[i],
          billDiscountEntered: billShares[i],
          grossEx: grossEx,
          discountEx: grossEx - split.netEx,
          netEx: split.netEx,
          tax: split.tax,
          components: split.components,
          taxSnapshot: line.tax,
        ),
      );
    }

    // 5-6. Charges.
    final charges = <PricedCharge>[];
    if (input.serviceChargeBps > 0 && priced.isNotEmpty) {
      final base = priced.fold<int>(0, (a, l) => a + l.netEx);
      final amount = applyBps(base, input.serviceChargeBps);
      if (amount > 0) {
        final split = splitTax(amount, input.serviceChargeTax);
        charges.add(
          PricedCharge(
            kind: ChargeKind.service,
            label: 'Service charge ${formatBps(input.serviceChargeBps)}',
            amountEntered: amount,
            netEx: split.netEx,
            tax: split.tax,
            components: split.components,
            taxSnapshot: input.serviceChargeTax,
          ),
        );
      }
    }
    if (input.deliveryCharge > 0) {
      final split = splitTax(input.deliveryCharge, input.deliveryChargeTax);
      charges.add(
        PricedCharge(
          kind: ChargeKind.delivery,
          label: 'Delivery charge',
          amountEntered: input.deliveryCharge,
          netEx: split.netEx,
          tax: split.tax,
          components: split.components,
          taxSnapshot: input.deliveryChargeTax,
        ),
      );
    }

    // 7. Rounding.
    final subtotal = priced.fold<int>(0, (a, l) => a + l.total) + charges.fold<int>(0, (a, c) => a + c.total);
    final rounded = input.roundingUnit > 1
        ? divRoundHalfUp(subtotal, input.roundingUnit) * input.roundingUnit
        : subtotal;

    return PricingResult(
      lines: priced,
      charges: charges,
      billDiscountEntered: billDiscount,
      subtotalBeforeRounding: subtotal,
      roundingAdjustment: rounded - subtotal,
    );
  }
}
