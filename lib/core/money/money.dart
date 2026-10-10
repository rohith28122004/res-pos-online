/// Integer money arithmetic.
///
/// Every persisted amount is an `int` in minor units (paise for INR). Nothing
/// in this file uses floating point. Division always goes through
/// [divRoundHalfUp] so rounding is explicit and identical everywhere.
library;

import '../errors/app_exception.dart';

/// Basis points: 10000 bps == 100 %.
const int bpsDenominator = 10000;

/// Divides [numerator] by [denominator] rounding half away from zero.
///
/// For non-negative inputs this is classic "round half up".
int divRoundHalfUp(int numerator, int denominator) {
  if (denominator <= 0) {
    throw ArgumentError.value(denominator, 'denominator', 'must be > 0');
  }
  if (numerator < 0) return -divRoundHalfUp(-numerator, denominator);
  final q = numerator ~/ denominator;
  final r = numerator - q * denominator;
  return (r * 2 >= denominator) ? q + 1 : q;
}

/// `amount * bps / 10000`, rounded half up.
int applyBps(int amount, int bps) => divRoundHalfUp(amount * bps, bpsDenominator);

/// Splits [total] across [weights] proportionally using the largest-remainder
/// (Hamilton) method.
///
/// The result always sums exactly to [total]. Ties on the remainder are broken
/// by lower index first, so the allocation is deterministic. A zero weight
/// always receives zero. Each share is <= its weight when total <= sum(weights).
List<int> allocateLargestRemainder(int total, List<int> weights) {
  if (total < 0) throw ArgumentError.value(total, 'total', 'must be >= 0');
  if (weights.any((w) => w < 0)) {
    throw ArgumentError.value(weights, 'weights', 'must be >= 0');
  }
  final sum = weights.fold<int>(0, (a, b) => a + b);
  if (total == 0) return List<int>.filled(weights.length, 0);
  if (sum == 0) {
    throw ArgumentError('cannot allocate $total across zero weights');
  }
  final shares = List<int>.filled(weights.length, 0);
  final remainders = <({int index, int remainder})>[];
  var allocated = 0;
  for (var i = 0; i < weights.length; i++) {
    final product = total * weights[i];
    shares[i] = product ~/ sum;
    allocated += shares[i];
    remainders.add((index: i, remainder: product - shares[i] * sum));
  }
  var left = total - allocated;
  remainders.sort((a, b) {
    final byRemainder = b.remainder.compareTo(a.remainder);
    return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
  });
  for (final entry in remainders) {
    if (left == 0) break;
    if (weights[entry.index] == 0) continue;
    shares[entry.index] += 1;
    left -= 1;
  }
  assert(left == 0);
  return shares;
}

/// The cumulative share of [total] that belongs to [doneQuantity] of
/// [totalQuantity] units, rounded half up. `cumulativeShare(t, q, q) == t`.
///
/// Used for partial refunds: the amount for one refund is
/// `cumulativeShare(after) - cumulativeShare(before)`, which never goes
/// negative and sums exactly to [total] once every unit is refunded.
int cumulativeShare(int total, int doneQuantity, int totalQuantity) {
  if (totalQuantity <= 0) {
    throw ArgumentError.value(totalQuantity, 'totalQuantity', 'must be > 0');
  }
  if (doneQuantity < 0 || doneQuantity > totalQuantity) {
    throw ArgumentError.value(doneQuantity, 'doneQuantity', 'out of range');
  }
  if (doneQuantity == totalQuantity) return total;
  return divRoundHalfUp(total * doneQuantity, totalQuantity);
}

/// Currency display/parse configuration. INR by default.
class CurrencyFormat {
  const CurrencyFormat({
    this.code = 'INR',
    this.symbol = '₹',
    this.minorDigits = 2,
    this.indianGrouping = true,
  });

  final String code;
  final String symbol;
  final int minorDigits;
  final bool indianGrouping;

  static const inr = CurrencyFormat();

  static CurrencyFormat forCode(String code) => switch (code) {
    'INR' => inr,
    _ => CurrencyFormat(code: code, symbol: '$code ', indianGrouping: false),
  };

  int get _scale {
    var s = 1;
    for (var i = 0; i < minorDigits; i++) {
      s *= 10;
    }
    return s;
  }

  /// "1234.50" style string with no symbol and no grouping (exports, inputs).
  String plain(int minor) {
    final negative = minor < 0;
    final abs = minor.abs();
    final major = abs ~/ _scale;
    final fraction = abs % _scale;
    final text = minorDigits == 0 ? '$major' : '$major.${fraction.toString().padLeft(minorDigits, '0')}';
    return negative ? '-$text' : text;
  }

  /// "₹1,23,456.50" (Indian grouping) or "USD 123,456.50".
  String format(int minor, {bool withSymbol = true}) {
    final negative = minor < 0;
    final abs = minor.abs();
    final major = (abs ~/ _scale).toString();
    final fraction = abs % _scale;
    final grouped = indianGrouping ? _groupIndian(major) : _groupWestern(major);
    final body = minorDigits == 0 ? grouped : '$grouped.${fraction.toString().padLeft(minorDigits, '0')}';
    final withSign = withSymbol ? '$symbol$body' : body;
    return negative ? '-$withSign' : withSign;
  }

  /// Parses a user/CSV decimal string into minor units without floating point.
  /// Accepts "120", "120.5", "120.50", "1,20,000.00". Rejects more than
  /// [minorDigits] decimals, signs (unless [allowNegative]) and garbage.
  int parse(String input, {bool allowNegative = false}) {
    var s = input.trim().replaceAll(',', '');
    if (s.startsWith(symbol.trim())) s = s.substring(symbol.trim().length).trim();
    if (s.toUpperCase().startsWith(code)) s = s.substring(code.length).trim();
    var negative = false;
    if (s.startsWith('-')) {
      if (!allowNegative) {
        throw const ValidationException('Amount cannot be negative');
      }
      negative = true;
      s = s.substring(1);
    }
    final match = RegExp(r'^(\d+)(?:\.(\d*))?$').firstMatch(s);
    if (match == null) {
      throw ValidationException('"$input" is not a valid amount');
    }
    final majorText = match.group(1)!;
    final fractionText = match.group(2) ?? '';
    if (fractionText.length > minorDigits) {
      throw ValidationException('"$input" has more than $minorDigits decimal places');
    }
    if (majorText.length > 13) {
      throw ValidationException('"$input" is too large');
    }
    final major = int.parse(majorText);
    final fraction = fractionText.isEmpty ? 0 : int.parse(fractionText.padRight(minorDigits, '0'));
    final value = major * _scale + fraction;
    return negative ? -value : value;
  }

  static String _groupWestern(String digits) {
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }

  static String _groupIndian(String digits) {
    if (digits.length <= 3) return digits;
    final last3 = digits.substring(digits.length - 3);
    var rest = digits.substring(0, digits.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }
}

/// Parses a percentage string ("5", "2.5", "12.75") into basis points.
int parsePercentToBps(String input) {
  final s = input.trim().replaceAll('%', '');
  final match = RegExp(r'^(\d{1,3})(?:\.(\d{0,2}))?$').firstMatch(s);
  if (match == null) throw ValidationException('"$input" is not a valid percentage');
  final whole = int.parse(match.group(1)!);
  final frac = (match.group(2) ?? '').padRight(2, '0');
  final bps = whole * 100 + int.parse(frac.isEmpty ? '0' : frac);
  if (bps > bpsDenominator) {
    throw ValidationException('"$input" is more than 100%');
  }
  return bps;
}

/// "5%", "2.5%", "12.75%".
String formatBps(int bps) {
  final whole = bps ~/ 100;
  final frac = bps % 100;
  if (frac == 0) return '$whole%';
  final f = frac.toString().padLeft(2, '0');
  return '$whole.${f.endsWith('0') ? f.substring(0, 1) : f}%';
}
