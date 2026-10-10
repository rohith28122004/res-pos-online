# CaféDesk — implementation progress

Spec: `OFFLINE_POS_BUILD_SPEC.md` (the acceptance contract). This file tracks what is done,
how it was checked, assumptions, and what is still open. Update it with every change.

Legend: ✅ done and checked · 🟡 implemented, check pending (see note) · ⛔ blocked by an
external dependency · ⬜ not started

## Checklist by phase

### 1. Foundation
- ✅ Flutter project (Android + Windows), Material 3 theme, responsive shell (rail / bottom bar)
- ✅ Drift schema (34 tables), foreign keys, partial unique indexes, WAL + `synchronous=FULL`
- ✅ Versioned migrations: schemas v1–v3 frozen (`drift_schemas/`); v2 adds guest count + index, v3 adds staff email/password columns + unique email index
- ✅ First-run setup (no default credentials), receipt prefix, recovery code
- ✅ Roles owner / cashier / kitchen, permissions enforced in services, owner approvals
- ✅ Email + password sign-in (replaced PINs on 2026-10-10): owner-created accounts, forced own-password at first sign-in, salted Argon2id hashes, persistent retry delay, inactivity lock
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
- ✅ Restore: path-traversal, checksum, version, currency and integrity checks; owner password;
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
| `dart format` | clean (page width 120) |
| `flutter analyze` | no issues |
| Automated tests (domain, database, reporting, printing, migration, Windows spooler, widget) | 168 passed, 0 failed |
| Android release APK | built — `dist/CafeDesk-1.0.0+1-android-debug-signed.apk` (debug-signed) |
| Windows release bundle | built — `dist/CafeDesk-1.0.0+1-windows-x64-unsigned.zip` (unsigned) |
| Windows bundle launch on dev PC | blocked by Smart App Control (unsigned `flutter_windows.dll`) |
| Release APK on Android emulator | installed and launched; welcome, setup owner form, demo seeding, email + password sign-in (name tap fills the email), shell and Bills checked by hand |
| Scripted integration test on a device | **passed** on the Android emulator (`integration_test/demo_sale_test.dart`: email + password sign-in, shift, sale, payment, saved bill) |
| Physical printers | not run (no hardware) |
| Manual acceptance checklist | not run (needs café devices and printers) |

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
- 2026-10-10 — **Android release APK built** (`scripts/build_android.ps1`): fat APK with
  arm64-v8a, armeabi-v7a and x86_64, minSdk 24, targetSdk 36, bundled `libsqlite3.so`,
  label "CaféDesk". **Debug-signed** (no owner key in the repo). Needed
  `kotlin.incremental=false` (pub cache on D:, project on C:).
- 2026-10-10 — **Windows release bundle built** (`scripts/build_windows.ps1`, VS Build Tools
  2022, Developer Mode on): `cafedesk.exe`, `flutter_windows.dll`, `sqlite3.dll`,
  `dartjni.dll`, `data\`. Zipped **unsigned**. Launching the unzipped bundle on the dev PC:
  the process starts but **Smart App Control blocks `flutter_windows.dll`** (Code Integrity
  events 3033/3077/3118). The Windows app therefore cannot run on this PC until the bundle is
  code-signed with a trusted certificate (or on a PC without Smart App Control). Not a code
  defect; café PCs with Smart App Control on need a signed build.
- 2026-10-10 — `dart format` (page width 120) applied; `dart fix` for brace lints; re-run:
  format 0 changes, analyze no issues, 153 tests passed. Initial local git commit created.
- 2026-10-10 — **Android emulator** (AVD `cafedesk_phone`, x86_64, headless, WHPX): release
  APK installed and launched. Checked by hand: welcome screen, demo seeding, lock screen, owner
  sign-in, shell. **Bug found:** the demo banner sat outside any `Material`, so its text used
  Flutter's red/underlined fallback style. Fixed (`DemoBanner` is now a `Material` and takes the
  status-bar inset); `screens_render_test.dart` now fails on any fallback-style text and renders
  the demo-mode shell at phone and desktop sizes. Gradle raised to `-Xmx4G` after an
  out-of-memory "Could not start thread" during the APK build.
- 2026-10-10 — `integration_test/demo_sale_test.dart` on the emulator: got through cashier
  sign-in, opening a shift, a new takeaway, adding an item, the cart and checkout, then failed
  because "Complete sale" was below the fold on a phone. Fixed with `scrollUntilVisible`, but the
  re-run was interrupted before it finished, so **its result is unknown**. The APK in `dist/` was
  built before the banner fix; rebuild it before handing it out.
- 2026-10-10 — Final local check: format clean, analyze no issues, **155 tests passed**.
- 2026-10-10 — **Artifacts rebuilt** from commit `9924635` (includes the banner fix):
  `dist/CafeDesk-1.0.0+1-android-debug-signed.apk` (65.9 MB, SHA-256
  `ad7d8f7cf466e7d8ed7daf8991b7ad349fb2b69f0b6271fa11785cc96cd551de`; `apksigner` confirms the
  signer is "CN=Android Debug", so it is for testing only) and
  `dist/CafeDesk-1.0.0+1-windows-x64-unsigned.zip` (13.8 MB, SHA-256
  `7a213a93a23c1d8c6822205ea28009a89e0dcf05b03e737030f04bf9b3edde6d`; unsigned). The rebuilt
  APK has not been reinstalled on the emulator.
- 2026-10-10 — **Email + password sign-in replaces PINs** (owner's decision). Schema v3
  (`staff.email` unique, `password_hash`, `must_change_password`; old `pin_hash` kept unused).
  Owner creates accounts in Staff; a new person must choose their own password at first
  sign-in; owner approvals, recovery and restore use passwords. Tests added: sign-in and
  throttling, same message for unknown email and wrong password, unique emails, owner reset,
  forced own-password (and refused once disabled), recovery that also sets an email,
  v2 → v3 migration with PIN-era staff, old demo databases getting their demo sign-ins, the
  sign-in and change-password screens. `flutter analyze` no issues; **168 tests passed**.
- 2026-10-10 — **Android emulator, end to end:** `flutter test integration_test/demo_sale_test.dart
  -d emulator-5554` **passed** (2 min): it started on a schema-2 demo database, which upgraded
  and got its demo sign-ins; signed in as Demo Cashier by email + password; opened a shift; sold
  and paid; the bill was saved. First complete on-device run of this test.
- 2026-10-10 — **Bug found on the emulator: chip labels were near-white** (sign-in names,
  Bills/Dashboard ranges, POS categories, filters): the theme set a chip font size but no
  colour. Fixed in `lib/app/theme.dart`; `screens_render_test.dart` now fails on light chip
  labels and renders the sign-in screen — proven: with the old theme 10 render tests failed,
  with the fix all 32 pass. Rebuilt APK checked on the emulator: names readable.
- 2026-10-10 — **Artifacts rebuilt** with sign-in and the chip fix:
  `dist/CafeDesk-1.0.0+1-android-debug-signed.apk` (66.1 MB, SHA-256
  `f3c58a7554f8112ea90ee65828572a604b8fd4d0139b093a8c26d6fd29e61a4c`, debug-signed) and
  `dist/CafeDesk-1.0.0+1-windows-x64-unsigned.zip` (SHA-256
  `4b80e7bd9b670c41d78897973275b1c4aa2446c3643eff1eecf7f21b4bf99268`, unsigned).

## Assumptions and decisions

- **Sign-in is email + password (owner's decision, 2026-10-10), replacing the spec's PINs.**
  Only an owner creates accounts (Staff → Create account: name, email, role, starting
  password); the person must choose their own password at the first sign-in. Owners reset
  passwords the same way; owner approvals use the owner's password. The email is only a
  sign-in name on the device: no email is ever sent (no internet), so a forgotten owner
  password is reset with the recovery code. Accounts from schema 2 keep their old PIN hash
  (unused) and have no password until set: the owner signs in once through "Forgot the owner
  password?" with the recovery code (which also sets their email), then gives staff emails and
  passwords. Old demo databases get their demo sign-ins automatically.
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
