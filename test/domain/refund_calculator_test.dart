import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/pricing/refund_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

RefundableLine coffeeLine({int already = 0}) => RefundableLine(
  billLineId: 'l1',
  quantity: 2,
  netEx: 18000,
  discountEx: 2000,
  alreadyRefundedQuantity: already,
  components: const [
    RefundableComponent(id: 'c1', name: 'CGST', rateBps: 250, amount: 450),
    RefundableComponent(id: 'c2', name: 'SGST', rateBps: 250, amount: 450),
  ],
);

void main() {
  test('R1 fixture: 1 of 2 coffees reverses captured, discounted amounts', () {
    final r = computeLineRefund(coffeeLine(), 1);
    expect(r.netEx, 9000);
    expect(r.discountEx, 1000);
    expect(r.grossEx, 10000);
    expect(r.tax, 450);
    expect(r.total, 9450);
  });

  test('cumulative partial refunds reproduce the original exactly', () {
    const line = RefundableLine(
      billLineId: 'x',
      quantity: 3,
      netEx: 10001,
      discountEx: 333,
      alreadyRefundedQuantity: 0,
      components: [
        RefundableComponent(id: 'a', name: 'CGST', rateBps: 250, amount: 251),
        RefundableComponent(id: 'b', name: 'SGST', rateBps: 250, amount: 250),
      ],
    );
    var net = 0, disc = 0, tax = 0, done = 0;
    for (final q in [1, 1, 1]) {
      final r = computeLineRefund(
        RefundableLine(
          billLineId: line.billLineId,
          quantity: line.quantity,
          netEx: line.netEx,
          discountEx: line.discountEx,
          alreadyRefundedQuantity: done,
          components: line.components,
        ),
        q,
      );
      expect(r.netEx >= 0 && r.tax >= 0 && r.discountEx >= 0, isTrue);
      net += r.netEx;
      disc += r.discountEx;
      tax += r.tax;
      done += q;
    }
    expect(net, 10001);
    expect(disc, 333);
    expect(tax, 501);
  });

  test('cannot refund more than remains', () {
    expect(() => computeLineRefund(coffeeLine(already: 2), 1), throwsA(isA<ValidationException>()));
    expect(() => computeLineRefund(coffeeLine(already: 1), 2), throwsA(isA<ValidationException>()));
    expect(() => computeLineRefund(coffeeLine(), 0), throwsA(isA<ValidationException>()));
  });

  test('default tender split follows original methods and caps', () {
    expect(defaultRefundTender(9450, {'cash': 36900}), {'cash': 9450});
    final split = defaultRefundTender(5000, {'upi': 5500, 'card': 5000});
    expect(split.values.reduce((a, b) => a + b), 5000);
    expect(split['upi']! <= 5500 && split['card']! <= 5000, isTrue);
    expect(() => defaultRefundTender(20000, {'cash': 100}), throwsA(isA<ValidationException>()));
  });
}
