import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/pricing/pricing_engine.dart';
import 'package:cafedesk/core/pricing/tax.dart';
import 'package:flutter_test/flutter_test.dart';

const gst5Excl = TaxSnapshot(
  mode: TaxMode.exclusive,
  rateBps: 500,
  components: [
    TaxComponentRate(name: 'CGST', rateBps: 250),
    TaxComponentRate(name: 'SGST', rateBps: 250),
  ],
  profileName: 'GST 5%',
);
const gst5Incl = TaxSnapshot(
  mode: TaxMode.inclusive,
  rateBps: 500,
  components: [
    TaxComponentRate(name: 'CGST', rateBps: 250),
    TaxComponentRate(name: 'SGST', rateBps: 250),
  ],
  profileName: 'GST 5% incl',
);

void main() {
  const engine = PricingEngine();

  test('disabled tax: totals are plain sums', () {
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'a', unitPrice: 12000, quantity: 2),
          PricingLineInput(key: 'b', unitPrice: 5000, quantity: 1, modifiersUnitTotal: 2000),
        ],
      ),
    );
    expect(r.itemsGrossEx, 31000);
    expect(r.taxTotal, 0);
    expect(r.total, 31000);
    expect(r.lines[1].unitPriceEntered, 7000);
  });

  test('exclusive tax with components (B1 fixture)', () {
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'coffee', unitPrice: 10000, quantity: 2, tax: gst5Excl),
          PricingLineInput(key: 'sandwich', unitPrice: 20000, quantity: 1),
        ],
        billDiscount: Discount.percent(1000),
      ),
    );
    expect(r.billDiscountEntered, 4000);
    expect(r.lines[0].billDiscountEntered, 2000);
    expect(r.lines[1].billDiscountEntered, 2000);
    expect(r.lines[0].netEx, 18000);
    expect(r.lines[0].tax, 900);
    expect(r.lines[0].components.map((c) => c.amount), [450, 450]);
    expect(r.lines[1].total, 18000);
    expect(r.itemsGrossEx, 40000);
    expect(r.itemsDiscountEx, 4000);
    expect(r.itemsNetEx, 36000);
    expect(r.total, 36900);
  });

  test('inclusive tax keeps the advertised price (B2 fixture)', () {
    final r = engine.price(
      const PricingInput(
        lines: [PricingLineInput(key: 'cake', unitPrice: 10500, quantity: 1, tax: gst5Incl)],
      ),
    );
    expect(r.total, 10500);
    expect(r.lines.single.netEx, 10000);
    expect(r.lines.single.tax, 500);
    expect(r.lines.single.grossEx, 10000);
    expect(r.lines.single.discountEx, 0);
    expect(r.lines.single.components.map((c) => c.amount), [250, 250]);
  });

  test('inclusive odd amount: net + tax == price exactly', () {
    for (var price = 1; price < 3000; price += 7) {
      final r = engine.price(
        PricingInput(
          lines: [PricingLineInput(key: 'x', unitPrice: price, quantity: 3, tax: gst5Incl)],
        ),
      );
      expect(r.total, price * 3);
      expect(r.lines.single.netEx + r.lines.single.tax, price * 3);
      expect(r.lines.single.components.fold<int>(0, (a, c) => a + c.amount), r.lines.single.tax);
    }
  });

  test('line discount before bill discount; allocation sums exactly', () {
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'a', unitPrice: 333, quantity: 1, lineDiscount: Discount.amount(33)),
          PricingLineInput(key: 'b', unitPrice: 333, quantity: 1),
          PricingLineInput(key: 'c', unitPrice: 334, quantity: 1),
        ],
        billDiscount: Discount.amount(100),
      ),
    );
    expect(r.lines.map((l) => l.lineDiscountEntered), [33, 0, 0]);
    expect(r.lines.fold<int>(0, (a, l) => a + l.billDiscountEntered), 100);
    // weights 300 / 333 / 334 of 967 → 31.02 / 34.43 / 34.54 → 31 + 34 + 35 (largest remainders)
    expect(r.lines.map((l) => l.billDiscountEntered), [31, 34, 35]);
    expect(r.total, 1000 - 33 - 100);
  });

  test('bill discount cannot exceed eligible amount and never makes a line negative', () {
    expect(
      () => engine.price(
        const PricingInput(
          lines: [PricingLineInput(key: 'a', unitPrice: 100, quantity: 1)],
          billDiscount: Discount.amount(101),
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'a', unitPrice: 100, quantity: 1),
          PricingLineInput(key: 'b', unitPrice: 1, quantity: 1),
        ],
        billDiscount: Discount.percent(10000),
      ),
    );
    expect(r.total, 0);
    expect(r.lines.every((l) => l.netEntered >= 0), isTrue);
  });

  test('ineligible lines receive no bill discount', () {
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'a', unitPrice: 1000, quantity: 1),
          PricingLineInput(key: 'b', unitPrice: 1000, quantity: 1, billDiscountEligible: false),
        ],
        billDiscount: Discount.percent(1000),
      ),
    );
    expect(r.lines[0].billDiscountEntered, 100);
    expect(r.lines[1].billDiscountEntered, 0);
  });

  test('service charge on tax-exclusive net, taxed by its own snapshot', () {
    final r = engine.price(
      const PricingInput(
        lines: [PricingLineInput(key: 'a', unitPrice: 10500, quantity: 2, tax: gst5Incl)],
        serviceChargeBps: 500,
        serviceChargeTax: gst5Excl,
      ),
    );
    // Items: net ex 20000, tax 1000. Service 5% of 20000 = 1000, tax 50.
    final service = r.charges.single;
    expect(service.kind, ChargeKind.service);
    expect(service.netEx, 1000);
    expect(service.tax, 50);
    expect(r.total, 21000 + 1050);
    expect(r.chargesNetEx, 1000);
  });

  test('delivery charge and payable rounding are stored separately', () {
    final r = engine.price(
      const PricingInput(
        lines: [PricingLineInput(key: 'a', unitPrice: 10000, quantity: 3, tax: gst5Excl)],
        deliveryCharge: 4000,
        roundingUnit: 100,
      ),
    );
    expect(r.subtotalBeforeRounding, 35500);
    expect(r.roundingAdjustment, 0);
    final odd = engine.price(
      const PricingInput(
        lines: [PricingLineInput(key: 'a', unitPrice: 9990, quantity: 1, tax: gst5Excl)],
        roundingUnit: 100,
      ),
    );
    // 9990 + 500 (499.5 → 500) = 10490 → rounds to 10500
    expect(odd.subtotalBeforeRounding, 10490);
    expect(odd.roundingAdjustment, 10);
    expect(odd.total, 10500);
  });

  test('tax breakdown aggregates by component and rate', () {
    final r = engine.price(
      const PricingInput(
        lines: [
          PricingLineInput(key: 'a', unitPrice: 10000, quantity: 1, tax: gst5Excl),
          PricingLineInput(key: 'b', unitPrice: 10500, quantity: 1, tax: gst5Incl),
        ],
      ),
    );
    final rows = r.taxBreakdown;
    expect(rows.length, 2);
    expect(rows.firstWhere((x) => x.name == 'CGST').amount, 500);
  });

  test('discount limit check', () {
    final r = engine.price(
      const PricingInput(
        lines: [PricingLineInput(key: 'a', unitPrice: 10000, quantity: 1)],
        billDiscount: Discount.percent(1500),
      ),
    );
    expect(r.discountExceeds(1000), isTrue);
    expect(r.discountExceeds(1500), isFalse);
  });

  test('component rates must add up to the profile rate', () {
    const bad = TaxSnapshot(
      mode: TaxMode.exclusive,
      rateBps: 500,
      components: [TaxComponentRate(name: 'X', rateBps: 200)],
    );
    expect(
      () => engine.price(
        const PricingInput(
          lines: [PricingLineInput(key: 'a', unitPrice: 1, quantity: 1, tax: bad)],
        ),
      ),
      throwsA(isA<ValidationException>()),
    );
  });

  test('tax snapshot JSON round trip', () {
    final back = TaxSnapshot.decode(gst5Excl.encode());
    expect(back.mode, TaxMode.exclusive);
    expect(back.rateBps, 500);
    expect(back.components, gst5Excl.components);
  });
}
