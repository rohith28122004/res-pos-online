# Report definitions

Every dashboard card, ledger column and CSV export is defined here. The
automated test `test/reporting/dashboard_fixture_test.dart` builds the fixture
below through the real services (checkout, refunds, expenses, shifts) and checks
each number. If a definition changes, update this file, the fixture and the
test together.

These are **operational reports**. They are not statutory tax reports and make
no compliance claim.

## Conventions

* Money is stored as integer paise. Exports print decimal strings (`369.00`).
* Timestamps are stored in UTC. Each bill, payment, refund, expense and drawer
  movement also stores a **business date** (`YYYY-MM-DD`), calculated once when
  the row is created, in the restaurant time zone, using the business-day
  cutoff in force at that moment. Changing the cutoff later never moves old
  rows to a different day.
* A date range is **start-inclusive, end-exclusive** over business dates:
  `[start, end)`. "Today" is `[today, today+1)`. "Last 7 days" is
  `[today−6, today+1)`. "This month" is `[1st of month, 1st of next month)`.
* A **refund belongs to the day it was issued**, not the day of the original
  sale. It keeps a link to the original bill. A period can therefore show a
  negative net billed value.
* "ex" means tax-exclusive. For tax-inclusive menu prices the tax-exclusive
  value is derived as `round_half_up(price × 10000 / (10000 + rate_bps))`.

## Cards

| Card | Definition |
|---|---|
| Item gross sales | Σ `bill_lines.gross_ex` of bills in range. Captured pre-discount, tax-exclusive item value × quantity. |
| Discounts | Σ `bill_lines.discount_ex` of bills in range (line + bill discounts, tax-exclusive). |
| Discount reversals | Σ `refund_lines.discount_ex` of refunds in range. Shown separately. |
| Net item sales | Σ `bill_lines.net_ex` (bills in range) − Σ `refund_lines.net_ex` (refunds in range). |
| Service/delivery charges | Σ `bill_charges.net_ex` (bills in range). Charge refunds: Σ `refund_charges.net_ex` (refunds in range), shown separately. |
| Taxes collected / reversed | Σ `bills.tax_total` (bills in range) and Σ `refunds.tax_total` (refunds in range). Never added to revenue. |
| Net billed value | Σ `bills.total` (bills in range) − Σ `refunds.total` (refunds in range). Tax-inclusive. May be negative. |
| Completed bills / average bill | Count of bills in range; average = Σ `bills.total` / count, half-up to the paisa. Refunds do **not** change this card. |
| Payments | Receipts: Σ `payments.applied` by method for bills in range (split tenders are separate rows). Refunds: Σ `refund_payments.amount` by method for refunds in range. Cash tendered and change are not revenue. |
| Expenses | Σ `expenses.amount` in range, excluding voided. Drawer-paid shown separately. |
| Operating surplus estimate | Net item sales + (charges − charge refunds) − expenses. **Not profit**: ingredient and other costs are not recorded. |
| Net cash movement | Cash receipts − cash refunds + drawer cash in − drawer cash out − drawer-paid expenses, all in range. |
| Cancellations | Orders cancelled (by cancellation business date) in range. |

Charts and lists: daily trend (per business date: bills total, refunds total,
net billed value), hourly sales (Σ `bills.total` by local hour stamped at
checkout), top items (net quantity = sold − refunded, net item sales), category
sales (net item sales by captured category name), order-type split (bills count
and total by dine-in/takeaway/delivery), refund history (refunds in range with
original receipt numbers).

There is no metric mixing gross sales, tax-inclusive receipts and profit.

## Cash drawer (per shift)

```
expected cash = opening float
              + Σ cash payments.applied in the shift
              − Σ cash refund_payments in the shift
              + Σ drawer cash in − Σ drawer cash out
              − Σ drawer-paid expenses in the shift (not voided)
variance      = counted cash − expected cash
```

A drawer-paid expense is recorded only as an expense, never also as a cash out,
so it is subtracted once.

## Hand-calculated fixture

Restaurant time zone Asia/Kolkata (UTC+05:30), cutoff 04:00. Taxes are
configured only for the fixture:

* **Coffee** ₹100.00, *added to price* 5 % (CGST 2.5 % + SGST 2.5 %)
* **Sandwich** ₹200.00, no tax
* **Cake** ₹105.00, *included in price* 5 % (CGST 2.5 % + SGST 2.5 %)

Shift S1 opens 2026-10-05 09:00 IST with float ₹1,000.00.

| # | Local time (IST) | Business date | Order | Detail | Total | Paid |
|---|---|---|---|---|---|---|
| B1 | 10-05 10:00 | 2026-10-05 | Dine-in | 2× Coffee, 1× Sandwich, 10 % bill discount | ₹369.00 | Cash 369.00 (received 500.00, change 131.00) |
| B2 | 10-05 23:30 | 2026-10-05 | Takeaway | 1× Cake | ₹105.00 | UPI 55.00 + Card 50.00 |
| B3 | 10-06 02:30 | **2026-10-05** (before cutoff) | Takeaway | 1× Sandwich | ₹200.00 | Cash 200.00 |
| B4 | 10-06 11:00 | 2026-10-06 | Delivery | 3× Coffee + ₹40.00 delivery charge (no tax) | ₹355.00 | Card 355.00 |

B1 workings: eligible base 400.00; 10 % = 40.00; largest-remainder split by
weights 200/200 → 20.00 + 20.00. Coffee net 180.00, tax 9.00 (4.50 + 4.50),
total 189.00. Sandwich net 180.00, total 180.00. Bill 369.00.

B2 workings: net ex = round(10500 × 10000 / 10500) = 10000 → ₹100.00, tax ₹5.00
(2.50 + 2.50). Payable stays ₹105.00.

B4 workings: 3 × 100.00 = 300.00, tax 15.00, + 40.00 delivery = 355.00.

Other activity:

* R1, 2026-10-06 12:00: refund **1 of the 2 coffees on B1** (an older sale),
  reason "Spilled". Cumulative share for 1 of 2: net ex 90.00, discount ex
  10.00, tax 2.25 + 2.25 = 4.50, total **94.50**, refunded in cash (B1's only
  method). Shift S1 is still open.
* Expenses: E1 2026-10-05 ₹150.00 "Milk & dairy" from the drawer; E2 2026-10-06
  ₹500.00 "Rent", not from the drawer; E3 2026-10-06 ₹80.00, voided.
* Drawer: 2026-10-05 cash out ₹100.00; 2026-10-06 cash in ₹50.00.
* One order cancelled on 2026-10-05 before anything was sent to the kitchen.

### Expected: 2026-10-05 (`[2026-10-05, 2026-10-06)`)

| Card | Value |
|---|---|
| Completed bills | 3 |
| Bills total | 674.00 |
| Average bill | 224.67 (67400 / 3 = 22466.67 → 22467) |
| Item gross sales | 700.00 |
| Discounts | 40.00 |
| Net item sales | 660.00 |
| Charges | 0.00 |
| Taxes collected / reversed | 14.00 / 0.00 |
| Net billed value | 674.00 |
| Receipts by method | Cash 569.00, UPI 55.00, Card 50.00 |
| Refunds by method | none |
| Expenses | 150.00 (drawer 150.00) |
| Operating surplus estimate | 510.00 |
| Net cash movement | 569.00 − 0 + 0 − 100.00 − 150.00 = 319.00 |
| Cancellations | 1 |
| Order types | Dine-in 1 / 369.00; Takeaway 2 / 305.00 |
| Hourly | 02 h 200.00; 10 h 369.00; 23 h 105.00 |
| Top items (net qty, net sales) | Sandwich 2 / 380.00; Coffee 2 / 180.00; Cake 1 / 100.00 |

### Expected: 2026-10-06 (`[2026-10-06, 2026-10-07)`)

| Card | Value |
|---|---|
| Completed bills | 1, total 355.00, average 355.00 |
| Item gross sales | 300.00 |
| Discounts / discount reversals | 0.00 / 10.00 |
| Net item sales | 300.00 − 90.00 = 210.00 |
| Charges / charge refunds | 40.00 / 0.00 |
| Taxes collected / reversed | 15.00 / 4.50 |
| Refunds | 1, total 94.50 |
| Net billed value | 355.00 − 94.50 = 260.50 |
| Receipts by method | Card 355.00 |
| Refunds by method | Cash 94.50 |
| Expenses | 500.00 (drawer 0.00; the voided 80.00 is excluded) |
| Operating surplus estimate | 210.00 + 40.00 − 500.00 = −250.00 |
| Net cash movement | 0 − 94.50 + 50.00 − 0 − 0 = −44.50 |
| Top items | Coffee net qty 3 − 1 = 2, net sales 300.00 − 90.00 = 210.00 |

### Expected: both days (`[2026-10-05, 2026-10-07)`)

Bills 4, total 1029.00, average 257.25; net item sales 870.00; net billed value
934.50; operating surplus estimate 260.00.

### Expected: shift S1 drawer (still open)

1000.00 + 569.00 − 94.50 + 50.00 − 100.00 − 150.00 = **1274.50**.

### Negative period

If B4 is then fully refunded on 2026-10-07, the range `[2026-10-07,
2026-10-08)` has 0 bills and a net billed value of −355.00. This is shown as is.
