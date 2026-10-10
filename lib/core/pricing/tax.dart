import 'dart:convert';

import '../errors/app_exception.dart';
import '../money/money.dart';

enum TaxMode {
  /// No tax is calculated.
  disabled,

  /// Menu price already includes tax; tax is carved out of the price.
  inclusive,

  /// Tax is added on top of the menu price.
  exclusive;

  static TaxMode parse(String value) => TaxMode.values.firstWhere(
    (m) => m.name == value,
    orElse: () => throw ValidationException('Unknown tax mode "$value"'),
  );

  String get label => switch (this) {
    TaxMode.disabled => 'No tax',
    TaxMode.inclusive => 'Included in price',
    TaxMode.exclusive => 'Added to price',
  };
}

/// A named slice of a tax rate, e.g. CGST 2.5% + SGST 2.5% of a 5% profile.
class TaxComponentRate {
  const TaxComponentRate({required this.name, required this.rateBps});

  final String name;
  final int rateBps;

  Map<String, Object?> toJson() => {'name': name, 'rateBps': rateBps};

  static TaxComponentRate fromJson(Map<String, Object?> json) =>
      TaxComponentRate(name: json['name']! as String, rateBps: json['rateBps']! as int);

  @override
  bool operator ==(Object other) => other is TaxComponentRate && other.name == name && other.rateBps == rateBps;

  @override
  int get hashCode => Object.hash(name, rateBps);
}

/// Tax configuration captured onto an order line / charge when it is created,
/// so later edits to the tax profile never reprice open or historical lines.
class TaxSnapshot {
  const TaxSnapshot({
    required this.mode,
    required this.rateBps,
    this.components = const [],
    this.profileId,
    this.profileName,
  });

  static const none = TaxSnapshot(mode: TaxMode.disabled, rateBps: 0);

  final TaxMode mode;
  final int rateBps;
  final List<TaxComponentRate> components;
  final String? profileId;
  final String? profileName;

  int get effectiveRateBps => mode == TaxMode.disabled ? 0 : rateBps;

  /// Components used for allocation. A profile without an explicit split is
  /// one component carrying the whole rate.
  List<TaxComponentRate> get effectiveComponents {
    if (mode == TaxMode.disabled || rateBps == 0) return const [];
    if (components.isNotEmpty) return components;
    return [TaxComponentRate(name: profileName ?? 'Tax', rateBps: rateBps)];
  }

  void validate() {
    if (rateBps < 0 || rateBps > bpsDenominator) {
      throw const ValidationException('Tax rate must be between 0% and 100%');
    }
    if (components.isNotEmpty) {
      final sum = components.fold<int>(0, (a, c) => a + c.rateBps);
      if (sum != rateBps) {
        throw ValidationException('Tax components add up to ${formatBps(sum)} but the rate is ${formatBps(rateBps)}');
      }
      if (components.any((c) => c.rateBps < 0 || c.name.trim().isEmpty)) {
        throw const ValidationException('Every tax component needs a name and a rate');
      }
    }
  }

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'rateBps': rateBps,
    'components': [for (final c in components) c.toJson()],
    'profileId': profileId,
    'profileName': profileName,
  };

  String encode() => jsonEncode(toJson());

  static TaxSnapshot fromJson(Map<String, Object?> json) => TaxSnapshot(
    mode: TaxMode.parse(json['mode']! as String),
    rateBps: json['rateBps']! as int,
    components: [
      for (final c in (json['components'] as List<Object?>? ?? const []))
        TaxComponentRate.fromJson((c! as Map).cast<String, Object?>()),
    ],
    profileId: json['profileId'] as String?,
    profileName: json['profileName'] as String?,
  );

  static TaxSnapshot decode(String? text) {
    if (text == null || text.isEmpty) return none;
    return fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  }

  static List<TaxComponentRate> decodeComponents(String? text) {
    if (text == null || text.isEmpty) return const [];
    return [
      for (final c in jsonDecode(text) as List<Object?>) TaxComponentRate.fromJson((c! as Map).cast<String, Object?>()),
    ];
  }

  static String encodeComponents(List<TaxComponentRate> components) =>
      jsonEncode([for (final c in components) c.toJson()]);
}

/// Amount of one tax component on one line or charge.
class TaxComponentAmount {
  const TaxComponentAmount({required this.name, required this.rateBps, required this.amount});

  final String name;
  final int rateBps;
  final int amount;

  @override
  String toString() => '$name ${formatBps(rateBps)}: $amount';
}

/// Result of applying a [TaxSnapshot] to a discounted amount.
class TaxSplit {
  const TaxSplit({required this.netEx, required this.tax, required this.components});

  /// Tax-exclusive value of the amount.
  final int netEx;
  final int tax;
  final List<TaxComponentAmount> components;

  int get total => netEx + tax;
}

/// Applies [snapshot] to [amountEntered] (a price in the snapshot's own mode).
///
/// * exclusive: tax = round(amount × rate), total = amount + tax
/// * inclusive: netEx = round(amount × 10000 / (10000 + rate)), tax = amount − netEx
/// * disabled: no tax
TaxSplit splitTax(int amountEntered, TaxSnapshot snapshot) {
  if (amountEntered < 0) throw ArgumentError.value(amountEntered, 'amountEntered');
  final rate = snapshot.effectiveRateBps;
  final int netEx;
  final int tax;
  switch (snapshot.mode) {
    case TaxMode.disabled:
      netEx = amountEntered;
      tax = 0;
    case TaxMode.exclusive:
      netEx = amountEntered;
      tax = applyBps(amountEntered, rate);
    case TaxMode.inclusive:
      netEx = divRoundHalfUp(amountEntered * bpsDenominator, bpsDenominator + rate);
      tax = amountEntered - netEx;
  }
  return TaxSplit(netEx: netEx, tax: tax, components: allocateTaxComponents(tax, snapshot));
}

/// Tax-exclusive value of a price in the snapshot's mode (no rounding of tax).
int exclusiveValue(int amountEntered, TaxSnapshot snapshot) => snapshot.mode == TaxMode.inclusive
    ? divRoundHalfUp(amountEntered * bpsDenominator, bpsDenominator + snapshot.effectiveRateBps)
    : amountEntered;

/// Splits [tax] over the snapshot's components in proportion to their rates
/// (largest remainder, deterministic, exact sum).
List<TaxComponentAmount> allocateTaxComponents(int tax, TaxSnapshot snapshot) {
  final comps = snapshot.effectiveComponents;
  if (comps.isEmpty) return const [];
  final weights = [for (final c in comps) c.rateBps];
  final shares = weights.every((w) => w == 0)
      ? List<int>.filled(comps.length, 0)
      : allocateLargestRemainder(tax, weights);
  return [
    for (var i = 0; i < comps.length; i++)
      TaxComponentAmount(name: comps[i].name, rateBps: comps[i].rateBps, amount: shares[i]),
  ];
}
