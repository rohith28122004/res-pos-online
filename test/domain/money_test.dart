import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('divRoundHalfUp', () {
    test('rounds half up for positives', () {
      expect(divRoundHalfUp(5, 2), 3);
      expect(divRoundHalfUp(4, 2), 2);
      expect(divRoundHalfUp(7, 3), 2);
      expect(divRoundHalfUp(8, 3), 3);
      expect(divRoundHalfUp(0, 7), 0);
    });
    test('is symmetric for negatives', () {
      expect(divRoundHalfUp(-5, 2), -3);
      expect(divRoundHalfUp(-7, 3), -2);
    });
    test('rejects non-positive denominators', () {
      expect(() => divRoundHalfUp(1, 0), throwsArgumentError);
    });
  });

  group('allocateLargestRemainder', () {
    test('sums exactly and is deterministic on ties', () {
      expect(allocateLargestRemainder(100, [1, 1, 1]), [34, 33, 33]);
      expect(allocateLargestRemainder(2, [1, 1, 1]), [1, 1, 0]);
      expect(allocateLargestRemainder(4000, [20000, 20000]), [2000, 2000]);
    });
    test('never gives a zero weight anything', () {
      expect(allocateLargestRemainder(10, [0, 3, 0, 7]), [0, 3, 0, 7]);
    });
    test('share never exceeds weight when total <= sum', () {
      for (var total = 0; total <= 50; total++) {
        final shares = allocateLargestRemainder(total, [7, 13, 30]);
        expect(shares.reduce((a, b) => a + b), total);
        expect(shares[0] <= 7 && shares[1] <= 13 && shares[2] <= 30, isTrue);
      }
    });
  });

  group('cumulativeShare', () {
    test('partial refunds sum to the original', () {
      const total = 1001;
      var refunded = 0;
      for (var k = 0; k < 3; k++) {
        refunded += cumulativeShare(total, k + 1, 3) - cumulativeShare(total, k, 3);
      }
      expect(refunded, total);
    });
  });

  group('CurrencyFormat', () {
    const inr = CurrencyFormat.inr;
    test('Indian grouping', () {
      expect(inr.format(12345678), '₹1,23,456.78');
      expect(inr.format(-50), '-₹0.50');
      expect(inr.format(100000), '₹1,000.00');
      expect(inr.plain(36900), '369.00');
      expect(inr.plain(-9450), '-94.50');
    });
    test('parses without floating point', () {
      expect(inr.parse('120'), 12000);
      expect(inr.parse('120.5'), 12050);
      expect(inr.parse(' 1,20,000.05 '), 12000005);
      expect(inr.parse('₹99.99'), 9999);
      expect(inr.parse('0.1'), 10);
    });
    test('rejects bad amounts', () {
      expect(() => inr.parse('1.234'), throwsA(isA<ValidationException>()));
      expect(() => inr.parse('-5'), throwsA(isA<ValidationException>()));
      expect(() => inr.parse('abc'), throwsA(isA<ValidationException>()));
      expect(() => inr.parse('1e5'), throwsA(isA<ValidationException>()));
      expect(inr.parse('-5', allowNegative: true), -500);
    });
  });

  test('percent parsing and formatting', () {
    expect(parsePercentToBps('5'), 500);
    expect(parsePercentToBps('2.5'), 250);
    expect(parsePercentToBps('12.75%'), 1275);
    expect(() => parsePercentToBps('101'), throwsA(isA<ValidationException>()));
    expect(formatBps(250), '2.5%');
    expect(formatBps(1275), '12.75%');
    expect(formatBps(500), '5%');
  });
}
