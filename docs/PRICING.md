# Pricing, tax and refund rules

One engine — `lib/core/pricing/pricing_engine.dart` — prices the cart preview, checkout and
receipts. Refund reversals live in `lib/core/pricing/refund_calculator.dart`. Everything is
integer minor units (paise); rates are basis points (500 = 5 %). Division always rounds
**half up** (half away from zero) via `divRoundHalfUp`.

## Captured inputs

When a line is added to an order it captures: item name, category, variant name, unit price
(variant price if any), modifiers (names + prices), and a **tax snapshot** (mode, rate,
components, profile name). Order-level service-charge %, its tax, delivery charge, its tax and
the rounding unit are captured when the order is created. Later menu, tax or settings edits
never change an existing line, order or bill.

## Calculation order

For each line `i`:

1. `unit_i = unit price + Σ modifier prices`; `gross_i = unit_i × qty_i` (in the snapshot's
   price mode: tax-inclusive for inclusive lines).
2. **Line discount** `ld_i`: an amount (≤ gross) or a % of `gross_i` (half up).
3. **Bill discount** `D`: an amount, or a % of the eligible base `Σ(gross_i − ld_i)`. It is
   split over eligible lines by **largest remainder** with weights `gross_i − ld_i`; ties go
   to the earlier line. Shares sum exactly to `D` and never exceed a line's remaining value.
4. `net_entered_i = gross_i − ld_i − bd_i`.
5. **Tax** per line on `net_entered_i`:
   * exclusive: `tax = round(net × rate / 10000)`, `net_ex = net`, `total = net + tax`
   * inclusive: `net_ex = round(net × 10000 / (10000 + rate))`, `tax = net − net_ex`,
     `total = net` (the advertised price is unchanged)
   * disabled: no tax
   Tax is split into named components (e.g. CGST/SGST) by largest remainder on the
   component rates. A profile without components is one component named after it.
6. Reporting values: `gross_ex` = tax-exclusive value of `gross_i` (same formula as above for
   inclusive lines), `discount_ex = gross_ex − net_ex`. Identity: `gross_ex − discount_ex =
   net_ex` and `net_ex + tax = line total`.

Then for the bill:

7. **Service charge** (dine-in by default): `round(Σ net_ex × service% )`, taxed with its own
   snapshot (as an amount in that snapshot's mode).
8. **Delivery charge**: a fixed amount, taxed with its own snapshot.
9. `subtotal = Σ line totals + Σ charge totals`.
10. **Payable rounding** (off by default): `total = round(subtotal / unit) × unit`; the
    difference is stored as `rounding_adjustment`.

Discount limit: if `Σ entered discounts × 10000 > cashier_limit_bps × Σ gross_entered`, a
cashier needs owner approval (owner password); owners are not limited.

## Payments

`Σ applied == total` exactly. Only cash may have `tendered > applied`; the difference is
change and is never revenue. UPI and card are staff-recorded, not verified.

## Refunds

A refund reverses the *captured* bill amounts. For a bill line with quantity `Q`, refunding
units `(k_before, k_after]` uses cumulative shares:

```
share(x, k) = x               when k == Q
            = round(x × k / Q) otherwise
refund(x)   = share(x, k_after) − share(x, k_before)
```

applied independently to `net_ex`, `discount_ex` and each tax component. Derived:
`gross_ex = net_ex + discount_ex`, `tax = Σ components`, `total = net_ex + tax`. So partial
refunds are never negative, can never exceed the original, and the last unit brings the
totals back to exactly the original line.

Service/delivery charges are refunded whole (once). The bill's rounding adjustment is
returned only by the refund that refunds everything that remains, so cumulative refunds equal
the bill total exactly.

Refund tenders default to the original methods (largest remainder, capped by what each
method paid minus what was already refunded through it). Custom splits are validated against
the same caps. Cash refunds need an open shift (they leave the drawer).

## Worked examples

See `docs/REPORT_DEFINITIONS.md` (bills B1–B4, refund R1) and `test/domain/pricing_engine_test.dart`.
