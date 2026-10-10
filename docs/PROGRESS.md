# CaféDesk — implementation progress

Spec: `OFFLINE_POS_BUILD_SPEC.md` (the acceptance contract). This file tracks what is done,
how it was checked, assumptions, and what is still open. Update it with every change.

Legend: ✅ done and checked · 🟡 implemented, check pending (see note) · ⛔ blocked by an
external dependency · ⬜ not started

## Checklist by phase

### 1. Foundation
- ✅ Flutter project (Android + Windows), Material 3 theme, responsive shell (rail / bottom bar)
- ✅ Drift schema (34 tables), foreign keys, partial unique indexes, WAL + `synchronous=FULL`
- ✅ Versioned migrations: schema v1 frozen (`drift_schemas/`), v2 step adds guest count + index
- ✅ First-run setup (no default credentials), receipt prefix, recovery code
- ✅ Roles owner / cashier / kitchen, permissions enforced in services, owner approvals
- ✅ Salted Argon2id PIN hashes, persistent retry delay, inactivity lock
- ✅ Separate demo database (`cafedesk_demo.sqlite`) with banner; never mixed with production
- ✅ Integer money, half-up rounding, largest remainder; business-day calendar with cutoff
- ✅ Single-instance lock per data directory

### 2. Ordering
- ✅ Menu: categories, items, variants, modifiers, availability (sold out), archive-not-delete
- ✅ CSV import (preview + row errors) / export; formula-injection safe
- ✅ Tables with occupancy from open orders; one open dine-in order per table (unique index)
- ✅ Durable open orders; captured line snapshots (name, variant, price, modifiers, tax)
- ✅ Pricing engine (inclusive / exclusive / disabled tax, components, line + bill discounts,
  service + delivery charges, optional rounding)
- ✅ KOT: additions-only submissions, idempotent operation ids, correction tickets with reason
  and owner approval, kitchen status board

### 3. Checkout
- ✅ Atomic idempotent finalisation (receipt sequence, immutable bill, lines, tax components,
  payments, order close, print job) in one transaction
- ✅ Cash / UPI / card / split tender, cash received and change, staff confirmation
- ✅ Bill history search, receipt preview, COPY reprints
- ✅ Owner-authorised full/partial refunds reversing captured amounts, tender caps per method

### 4. Printing
- ✅ Receipt / KOT / test-page layout for 58 and 80 mm, wrapping, COPY/REPRINT marks
- ✅ ESC/POS text encoder (PC437, WPC1252, ASCII) with explicit INR fallback and refusal to
  print unsupported characters; raster (GS v 0) renderer for ₹ and non-Latin scripts
- ✅ Durable queue: claim-before-send, sequential per printer, submitted / failed / unknown,
  crash recovery → unknown, explicit retry/confirm/cancel, held after restore
- ✅ TCP 9100 transport (tested against a local socket)
- 🟡 Android Bluetooth Classic (Kotlin RFCOMM plugin, runtime permissions) — compiles in the
  APK build; needs a phone + printer to verify
- 🟡 Windows spooler RAW + driver-rendered GDI paths (dart:ffi) — compiled; needs a Windows
  build that can run on this PC and a USB thermal printer to verify
- ⛔ Physical printer validation — no printer hardware available (see PRINTER_SETUP.md)

### 5. Operations
- ✅ Shifts: float, cash in/out, expected cash, counted cash, variance, immutable closure
  snapshots, owner carry-over of open orders, owner reopen
- ✅ Expenses (drawer / non-drawer, owner void)
- ✅ SQL dashboard per REPORT_DEFINITIONS.md with hand-calculated fixture test
- ✅ Daily ledger + CSV exports (bills, lines, payments, refunds, refund lines, expenses,
  shifts, ledger)

### 6. Reliability
- ✅ Backups via `VACUUM INTO` + manifest + SHA-256; scheduled + catch-up; retention
- ✅ Restore: path-traversal, checksum, version, currency and integrity checks; owner PIN;
  pre-restore backup; swap with rollback; sequences never move backwards; print jobs held
- ✅ Audit trail (finalise, refunds, voids, discounts, overrides, prices, settings, backup,
  restore, printing)
- ✅ Migration test on a populated v1 database
- 🟡 Performance profiling on a reference device (1,000 items / 50,000 bills) — not measured yet

### 7. Delivery
- see "Builds and checks" below

## Builds and checks (latest run)

Recorded honestly; "not run" means not run.

| Check | Result |
|---|---|
| `flutter analyze` | see latest entry in the run log below |
| Unit / database / reporting / printing tests | see run log |
| Android release APK | see run log |
| Windows release bundle | see run log |
| Integration test on device | not run |
| Physical printers | not run (no hardware) |

## Run log

(append newest at the bottom)

- 2026-10-09/10 — Toolchains installed on the dev PC (Windows 11 25H2, i7-1185G7, 16 GB):
  Flutter, Android SDK (platform 36, build-tools 36.0.0), Temurin JDK 21, VS Build Tools
  2022 17.14 C++. `flutter doctor`: all green. Windows Developer Mode still off (needed for
  the Windows build; a user setting).
- 2026-10-10 — On Flutter 3.47.7: `flutter analyze` clean (services), 114 tests passed
  (domain 41, database/reporting/printing 73) incl. the hand-calculated dashboard fixture.
- 2026-10-10 — Smart App Control probe of engine tools: 3.47.7 blocks `impellerc` and
  `gen_snapshot`; 3.44.9 blocks `flutter_tester`; 3.47.6 allows all → project pinned to
  3.47.6.
- 2026-10-10 — On Flutter 3.47.6 (Dart 3.13.5): `flutter analyze` → **No issues found**.
  `flutter test` → **153 passed, 0 failed**: domain, database (checkout idempotency and
  rollback, KOT, refunds, auth, menu CSV, backup/restore incl. rollback and restart),
  reporting (hand-calculated fixture, ledger, all CSV exports), printing (encoder, queue
  semantics, loopback TCP), schema migration v1→v2 with a populated database, Windows spooler
  (enumeration, RAW submission, GDI driver-rendered job producing a real PDF via "Microsoft
  Print to PDF"), widget tests (full sale flow through the UI; 14 screens at phone 390×844
  and desktop 1400×900 with no layout errors). The render test found and drove fixes for:
  dropdown overflow on phones, a phone order-card overflow, kitchen card buttons at desktop.
- 2026-10-10 — `dart run tool/perf_benchmark.dart` on the dev PC: menu load 24 ms (1,000
  items); order edit 13–53 ms and checkout 35 ms on a 50,000-bill database; dashboard 30 ms
  (day), 452 ms (month, 12,927 bills), 1,646 ms (120 days, 50,000 bills).

## Assumptions and decisions

- One restaurant, one database per installation; no sync. Android and Windows are separate.
- INR only in v1 (`currency_code` is stored; restore refuses other currencies).
- Taxes are off until an owner creates tax profiles; nothing is assumed about GST rates.
- Tax is computed per line (and per charge) on the discounted amount; components split by
  largest remainder. See `docs/PRICING.md`.
- Service charge applies to dine-in orders by default and is a % of tax-exclusive net item
  sales; staff can remove it per order.
- Rounding of the payable total is off by default; when on, the adjustment is stored
  separately and returned only by the refund that completes the bill.
- Refunds are attributed to their issue date; partial refunds use cumulative shares so they
  can never exceed the original.
- A drawer-paid expense is only an expense, never also a cash-out.
- Lines already sent to the kitchen can only change quantity; decreasing needs a reason and
  owner approval and creates a correction ticket immediately.
- Failed print jobs (nothing sent) are not auto-retried; staff retry with one tap. Unknown
  jobs are never resent without an explicit "did not print" confirmation (marked REPRINT).
- Backups are not encrypted (disclosed in the UI and docs).
- Item images are not supported in v1 (backups therefore contain only the database).
- Flutter 3.44.9 is used instead of the newest stable because Windows Smart App Control on
  the development PC blocks the newest release's unsigned engine tools.

## Remaining limitations / open items

- Hardware validation of every printer path (Bluetooth, USB spooler RAW/driver, LAN).
- Release signing: needs the owner's Android upload key and a Windows code-signing
  certificate (Smart App Control and SmartScreen block unsigned apps).
- Performance profiling on reference devices.
- Bluetooth on Windows and USB on Android are not supported in v1.
