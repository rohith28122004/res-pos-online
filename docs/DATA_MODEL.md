# Data model

Source of truth: `lib/core/database/tables.dart` (Drift). Frozen versions: `drift_schemas/cafedesk/`.

Conventions: UUID v7 text ids · money INTEGER paise · rates INTEGER basis points · timestamps
INTEGER UTC epoch ms · financial rows carry `business_date` (YYYY-MM-DD, computed when the row
is created) · booleans INTEGER 0/1 · `PRAGMA foreign_keys = ON` on every connection.

| Table | Purpose | Mutability |
|---|---|---|
| `installation` | single row: installation id, receipt prefix, demo flag, created-by version | prefix changes only via restore option |
| `sequences` | `receipt`, `refund`, `order`, `kot` counters, allocated inside the using transaction | increment only |
| `restaurant_settings` | single row: identity, currency, time zone, cutoff, receipt text, limits, charges, rounding, lock timeout, print and backup options, `version` | audited updates |
| `staff` | name, role, sign-in `email` (lower-case, unique), Argon2id `password_hash`, `must_change_password`, disabled flag, failed attempts, `locked_until`; legacy `pin_hash` (schema 1–2, unused since v3, cleared when a password is set) | audited updates |
| `owner_recovery` | hashed one-time recovery codes | `used_at` set once |
| `tax_profiles` | mode, rate, component split, archived, `version` | audited updates; lines keep snapshots |
| `categories`, `menu_items`, `item_variants`, `item_modifiers` | current menu; archived instead of deleted | audited updates |
| `dining_tables` | label, capacity, archived | updates |
| `orders` | open/finalized/cancelled orders, captured charge/rounding settings, discounts, approval, `guest_count` (v2), cancellation reason/date | updated while open; frozen once billed or cancelled |
| `order_lines` | captured item/variant/price/modifiers/tax snapshot, quantity, note, line discount, `revision` | quantity edits while open; locked fields once sent to kitchen |
| `kitchen_tickets` / `kitchen_ticket_lines` | immutable KOT submissions and corrections (negative deltas), operation id, line revision references | only ticket `status` changes |
| `shifts` / `shift_closures` | one open shift (partial unique index); every close is an immutable closure snapshot | status toggles; closures append-only |
| `cash_movements` | drawer cash in/out with reason | append-only |
| `bills` | immutable financial snapshot: receipt no (unique), operation id (unique), order id (unique), totals, business date, local hour, staff, shift, currency, time zone, restaurant JSON, `guest_count` (v2) | append-only |
| `bill_lines` | per line entered and tax-exclusive amounts, tax mode/rate/amount | append-only |
| `bill_charges` | service/delivery charges with tax | append-only |
| `bill_tax_components` | tax per line/charge per named component | append-only |
| `payments` | applied amount, tendered, change, method, shift, confirmer | append-only |
| `refunds`, `refund_lines`, `refund_charges`, `refund_tax_components`, `refund_payments` | reversals linked to bill, bill lines, charges, components; reason, authoriser, business date | append-only |
| `expenses` | category, amount, drawer flag, shift, author; void fields | void only (owner, with reason) |
| `printer_profiles` | role, width, dots, characters per line, code page, render mode, cutter, drawer pulse, transport, endpoint, timeouts | updates; archived instead of deleted |
| `print_jobs` / `print_attempts` | durable document payload, state, attempts with outcome/error/bytes | state transitions only |
| `audit_events` | actor, action, entity, minimal details JSON, approving owner | append-only |
| `completed_operations` | idempotency keys → result id | append-only |

## Key constraints and indexes

* `orders_one_open_per_table` — UNIQUE(table_id) WHERE status='open' AND table_id IS NOT NULL
* `shifts_one_open` — UNIQUE(status) WHERE status='open'
* UNIQUE `bills.receipt_no`, `bills.operation_id`, `bills.order_id`, `refunds.refund_no`,
  `refunds.operation_id`, `kitchen_tickets.operation_id`
* CHECKs: positive quantities on bill/refund lines, positive payment/refund/expense amounts,
  non-negative totals and prices, tax rate 0–10000 bps, non-zero KOT deltas
* Report indexes: `bills(business_date)`, `bills(order_type, business_date)` (v2),
  `payments(business_date, method)`, `refunds(business_date)`,
  `refund_payments(business_date, method)`, `expenses(business_date)`,
  `cash_movements(business_date)`, plus FK lookup indexes and `print_jobs(state, printer)`.

## Migrations

* v1 — initial schema.
* v2 — `orders.guest_count`, `bills.guest_count` (nullable), index `bills_type_date`.

Steps live in `AppDatabase.migration` via the generated `stepByStep` helper. Rules: additive
only, never edit an old step, never wipe data to resolve a mismatch, and a database from a
newer app version is refused instead of downgraded. To add v3: change tables, bump
`latestSchemaVersion`, run `dart run drift_dev make-migrations`, write `from2To3`, extend
`test/database/generated_migrations/cafedesk/migration_test.dart`.

## What is never stored

Card numbers, UPI ids/credentials, plaintext passwords or recovery codes, customer phone numbers
(no field exists). Logs and audit details never include passwords or backup contents.
