# Offline Café POS — implementation specification

## 1. Goal and scope

Build a complete offline billing application for cafés and small restaurants. Deliver an Android APK for phones/tablets and a native Windows desktop application from one Flutter codebase. The app must handle orders, kitchen tickets, receipts, payments, refunds, expenses, shift reconciliation, backups, and a useful sales dashboard without an internet connection.

This is a new standalone project. This document does not replace the QR Menu website's architecture or authorize changing its backend, deployments, or data. If working inside the QR Menu repository, create the application under `offline_pos/` with its own README and project-specific instructions. Preserve the existing applications and uncommitted changes. Alternatively, use a new empty repository and copy this specification into it.

### Product decisions

- Initial platforms: Android and Windows. iOS, macOS, Linux, and browser builds are outside the initial release.
- One restaurant and one local database per installation.
- Android and Windows are separate installations. They do **not** automatically share orders or sales. Clearly state this during setup and in the README.
- Do not open a SQLite file concurrently over a network share, OneDrive, or Dropbox.
- Backup transfer between platforms is supported; backup import replaces the destination database after validation and confirmation. It is not a merge or a way to operate two active counters together.
- No cloud login, cloud backend, subscriptions, mandatory internet access, or QR customer ordering in v1.
- Default currency INR, integer paise, English UI, configurable restaurant timezone defaulting to Asia/Kolkata.
- Tax configuration is a business setting. Do not claim statutory compliance or guess a restaurant's tax registration or rates. Default taxes to disabled and label exports as operational reports.
- Use a temporary working name, CaféDesk, and make restaurant branding configurable.

## 2. Technology and architecture

Use Flutter stable and Dart with Material 3, Riverpod for state/dependency management, and Drift over SQLite for local persistence. Use a maintained routing package if needed. Select current compatible package versions from official documentation and pub.dev; commit the lockfile. Do not assume a printing plugin supports both platforms merely because it exists.

Use native platform adapters where plugins cannot provide the required printing capability. Use Dart sockets for ESC/POS over a local network, Kotlin for Android Bluetooth Classic RFCOMM, and Windows native code/platform channels for Windows spooler integration as necessary. Document each dependency's platform support and license.

Keep business logic independent of widgets and printer transport:

```text
offline_pos/
  README.md
  CLAUDE.md                 # instructions scoped to this standalone app
  pubspec.yaml
  pubspec.lock
  analysis_options.yaml
  android/
  windows/
  lib/
    main.dart
    app/                   # startup, theme, navigation, dependencies
    core/
      money/               # integer arithmetic and rounding
      time/                # timezone and business-day calculations
      errors/
      security/            # local PIN authentication and permissions
      database/            # Drift schema, migrations, database lifecycle
      backup/
      printing/
        documents/         # receipt and KOT models
        encoders/          # ESC/POS and raster fallback
        transports/        # Bluetooth, TCP, Windows spooler
        queue/
    features/
      setup/
      auth/
      menu/
      tables/
      orders/
      checkout/
      bills/
      refunds/
      dashboard/
      expenses/
      shifts/
      settings/
      audit/
    shared/widgets/
  test/
    domain/
    database/
    reporting/
    printing/
  integration_test/
  docs/
    ARCHITECTURE.md
    DATA_MODEL.md
    PRINTER_SETUP.md
    BACKUP_RESTORE.md
    BUILD_AND_RELEASE.md
    MANUAL_TEST_CHECKLIST.md
    PROGRESS.md
  scripts/                 # reproducible build and packaging helpers
```

Feature folders may contain presentation, application, domain, and data layers when useful. Avoid empty boilerplate layers. Widgets call application services; services enforce permissions and use database transactions. Reports query persisted records, never demo arrays or transient UI state. Native printing code must not perform billing calculations.

Keep SQLite in the platform's application-data directory, enable foreign keys, and use supported concurrency settings. Use migrations with upgrade tests. Allow one app instance per database on Windows. Treat database integrity and transactional checkout as higher priorities than UI animation.

## 3. Screens and workflows

### First-run setup

Collect restaurant name, address, optional phone/tax registration identifier, currency, timezone, business-day cutoff, receipt footer, and owner PIN. No hardcoded credentials. Then offer menu entry/import and printer setup; printer setup can be skipped without preventing billing. A demo restaurant is an explicit separate demo database and never silently populates production reports.

### Login and roles

- Owner: full access, staff management, refunds, settings, restore, exports, audit trail.
- Cashier: orders, checkout, bill search, receipt reprint, and own shift controls.
- Kitchen: ticket list and preparing/ready status; no financial settings or sales reports.
- Owner approval is required for discounts above a configured limit, voids after KOT, refunds, and reopening closed shifts.

Enforce permissions in application services, not only by hiding buttons. Store salted PIN hashes using a maintained password-hashing implementation, with retry delay and inactivity lock. Document owner recovery explicitly; no universal override PIN. Do not store bank-card details or UPI credentials. Explain that local PINs restrict normal app access but are not protection against an administrator with filesystem access.

### Billing

- Searchable menu with category chips, large item buttons, sold-out indicators, variants and priced modifiers.
- Phone: menu view and persistent cart summary with a full-screen cart/checkout.
- Tablet/desktop: menu and cart side by side, keyboard search, quantity controls, and visible checkout.
- Dine-in and takeaway; delivery may be a manual order type with optional delivery charge and no delivery-service integration.
- Create, persist, resume, and cancel open orders; attach them to a table where applicable.
- Add item notes, quantities, modifiers, and discounts; show a transparent totals breakdown.
- Multiple orders can be open, but one active dine-in order per table in v1.
- Persist edits promptly, with a clear save-error state. After a crash, recover committed open orders.
- An edited menu price must never silently update an existing order line. Capture the item name, variant, unit price, modifiers, and tax settings when the line is created.

### Kitchen tickets

Send only additions or changes since the previous kitchen submission. Store each submission as an immutable ticket with a unique identifier and line revision references. A retry of the same submission must not create a new ticket. Decreases or cancellations after sending produce an explicit correction/cancellation ticket with a reason; do not silently erase kitchen instructions.

Support pending, preparing, and ready ticket states within this installation. Assign kitchen and receipt printer profiles independently. The KOT contains table/order reference, time, quantities, item names, and notes; prices are optional and off by default.

### Checkout

Support cash, UPI, card, and split tender as manual payment records. Display cash received and change. Only allocate the amount applied to the bill to revenue; tendered cash and change are separate fields. Do not represent selecting UPI/card as online payment verification. Require staff confirmation that payment was received.

On finalization, one database transaction must validate totals and permissions, allocate a receipt number, write the immutable bill and line snapshots, record payments, close the order/release the table, and enqueue receipt printing. Use a durable operation identifier and unique constraints so double taps, retries, and restarts cannot finalize twice.

Printing failure must never roll back a successful bill. Show the saved bill and offer an explicit reprint. A completed sale cannot be edited or deleted; corrections use a linked refund or adjustment workflow.

### Bills and refunds

Search by receipt number, date, table, or payment method. View the original bill, reprint marked as a copy, and issue an owner-authorized full or partial refund with reason. Track refund quantity/value against original lines and prevent cumulative over-refunding. Reverse proportional original discounts and taxes, including remainder allocation, rather than repricing from today's menu. Refunds retain links to original bills and payment methods.

### Menu and tables

Categories, items, variants, modifiers, availability, images if locally stored, and tax categories. Archive instead of deleting referenced records. CSV import/export with preview, validation, and actionable row errors. Table names and capacity are optional; show free/occupied state from actual open orders.

### Expenses and shifts

Record expense amount, category, time, note, creator, and whether it was paid from the cash drawer. Expenses are separate from sales and refunds. Support one active cashier shift per installation, opening float, drawer cash in/out with reasons, closing counted cash, expected cash, and variance. Associate sales, refunds, and drawer-paid expenses with a shift. Block normal shift closure while it has open orders, with an explicit owner resolution workflow. Keep closed shift snapshots immutable.

### Settings

Business details, timezone/cutoff, menu, staff roles, discount limits, tax modes/rates, receipt footer, printer profiles, backup destination, export, restore, and lock timeout. Confirm consequential changes and audit them. Changes to tax settings or branding do not rewrite historical bill snapshots.

## 4. Sales dashboard and report definitions

Provide Today, Yesterday, Last 7 days, This month, and custom date ranges. The dashboard must work offline and refresh after a committed bill, refund, or expense. Use the configured business timezone and cutoff; store timestamps in UTC and persist a business-date key at transaction creation. Define ranges as start-inclusive/end-exclusive. Changing the cutoff does not reassign historical records silently.

Show these cards and breakdowns:

- Item gross sales: completed item quantities multiplied by captured pre-discount, tax-exclusive item prices.
- Discounts: completed-sale discount allocations, with refund reversals tracked separately.
- Net item sales: gross item sales minus discounts and net of item refund reversals.
- Service/delivery charges and their refunds, shown separately.
- Taxes collected and reversed, shown separately from revenue.
- Net billed value: finalized bill totals in the range minus refund totals issued in the range.
- Completed bill count and original average bill value: completed bill total / completed bill count; returns shown separately so an old refund does not distort this card.
- Payment breakdown: receipts and refunds by cash/UPI/card, correctly allocating split tenders.
- Expenses and net cash movement. Any sales-minus-expenses card must be labeled an operating surplus estimate, not profit, because ingredient costs are absent.
- Daily sales trend, hourly sales, top items by net quantity and net item sales, category sales, dine-in/takeaway split, refund history, and cancellation count.
- Cash drawer: opening float + applied cash receipts - cash refunds + cash in - cash out - drawer-paid expenses; avoid counting the same expense as cash out twice.

Provide a detailed daily ledger and CSV exports of bills, line items, payments, refunds, expenses, and shift summaries. Escape CSV cells that could be interpreted as spreadsheet formulas. Use decimal currency strings in export, with explicit timezone/date columns and UTF-8 encoding. Empty data shows an honest empty state. Negative net billed value is allowed when older bills are refunded in the selected period.

Write a report-definition document and hand-calculated fixtures before implementing dashboard queries. A refund is attributed to its issue date for period activity, while preserving its link to the original sale. Offer a separate original-sale view only if clearly labeled. Never add a mixed dashboard metric that combines gross sales, tax-inclusive receipts, and profit.

## 5. Money and transaction rules

- All persisted money uses integer minor units. Never use binary floating-point arithmetic for totals.
- Quantities are whole numbers in v1; weighted items are deferred.
- Tax rates use integer basis points. Represent intermediate arithmetic as integer/rational values with explicit half-up rounding to the minor unit.
- Support disabled, inclusive, and exclusive tax modes and an optional named tax-component split. Taxes use captured configuration, not an assumed fixed rate.
- Implement one pricing engine used for order preview, checkout, receipt, and tests. For inclusive prices, derive the tax-exclusive components without changing the advertised payable price.
- Apply line discounts before an optional bill discount. Allocate bill discount proportionally across eligible lines using deterministic largest-remainder allocation; allocated amounts must sum exactly to the requested discount and cannot make a line negative.
- Allocate named tax components and refund reversals deterministically. Document calculation order, including charge taxes and any final payable rounding adjustment.
- Default payable rounding adjustment to zero. If enabled, store it separately and include it consistently in refunds and reconciliation.
- Final paid bill total equals the sum of applied payments. Reject underpayment; cash tender may exceed its applied portion and create change.
- Use UUIDs for internal IDs; use a transactionally allocated, installation-scoped sequence for human receipt numbers, with an installation prefix to prevent confusion across separate devices.
- Persist a receipt snapshot sufficient to reproduce the original content after menu, staff, or restaurant settings change.
- Keep audit events for finalization, refund, cancellation, discounts, overrides, menu price changes, settings, backup/restore, and printer retry/reprint.

## 6. Data model

Implement typed Drift tables, indexes, foreign keys, and schema migrations. The following are logical entities; split snapshot fields into proper columns/tables where queries need them.

| Entity | Required responsibilities |
|---|---|
| restaurant_settings | Business identity, currency, timezone, cutoff, receipt and pricing configuration |
| installation | Stable installation ID, receipt prefix, sequence policy, schema metadata |
| staff | Local identity, role, salted PIN hash, disabled flag |
| categories / items / variants / modifiers | Current menu configuration, prices, availability and archived flags |
| tax_profiles | Modes, rates, named components, versioned settings |
| dining_tables | Table labels and configuration |
| orders / order_lines | Persisted open orders, captured pricing, line revisions, state, creator |
| kitchen_tickets / kitchen_ticket_lines | Immutable submissions, correction relationships, kitchen state |
| bills / bill_lines | Immutable completed financial snapshots, business date, receipt number, operation ID |
| payments | Applied amount, method, shift, tender/change details and timestamp |
| refunds / refund_lines / refund_payments | Original references, reversals, reason, authorization, business date |
| expenses | Category, amount, business date, drawer flag, shift and author |
| shifts / cash_movements | Opening/closing values, counted cash, variance and drawer movements |
| printer_profiles | Role, width, transport, endpoint, encoding/capabilities |
| print_jobs / print_attempts | Durable payload, document ID, state, attempts, outcomes and errors |
| audit_events | Actor, action, reference, time and minimally necessary before/after data |
| completed_operations | Unique operation keys and associated result IDs for idempotency |

Index dashboard dates, bill numbers, open-order states, foreign-key references, and pending print jobs. Keep migrations versioned; never wipe user data to solve a schema mismatch. Do not write PINs, backup contents, or unnecessary personal information to logs.

## 7. Thermal printer support

Initial supported protocol: ESC/POS-compatible receipt printers, with 58 mm and 80 mm paper profiles. Compatibility is model-dependent: do not promise support for every thermal printer.

Required transports:

1. Android: paired Bluetooth Classic SPP/RFCOMM printer, with OS-version-appropriate runtime permissions and clear denial/reconnect flows. BLE-only and proprietary vendor protocols are outside initial support.
2. Windows: installed USB thermal printer through the Windows spooler. Use RAW jobs for ESC/POS printers whose installed queue accepts raw bytes. Provide a driver-rendered receipt path for supported Windows queues where RAW is unsuitable. Do not call a PDF generation library thermal printing support.
3. Android and Windows: local-network ESC/POS using configured IP/hostname and port, commonly TCP 9100. Local Wi-Fi/LAN can work without internet; it still requires a reachable printer.

Configure printer name, purpose (receipt/KOT/both), width, actual printable dot width, characters per line, code page, cutter capability, and optional drawer pulse. Drawer opening is disabled by default and requires an explicitly compatible setup. USB on Android and Bluetooth on Windows are deferred unless supported and verified during development.

Keep receipt layout, encoding, transport, and queue separate. Render wrapped item names, aligned amounts, modifiers, discounts, tax, payment/change, bill reference, time, restaurant details, and configurable footer. Handle the rupee symbol and other unsupported characters through a supported code page, raster rendering, or an explicit `INR` fallback; never silently print corrupt text. Use raster text for non-Latin scripts where appropriate.

Persist print jobs before sending. Process sequentially per printer. Record queued, sending, submitted, failed, and unknown outcomes. A successful transport write or spooler submission means submitted, not physically printed. A connection loss or restart during sending can have an ambiguous result; mark it unknown and ask the operator to inspect before an explicit retry. Do not silently resend uncertain jobs and promise exactly-once physical printing.

Provide printer discovery where feasible, manual endpoint entry, connection test, sample receipt/KOT, pending jobs, actionable errors, and explicit reprints marked COPY/REPRINT. Validate endpoints and enforce connection/read/write timeouts. Slow printers must not block checkout or the UI thread.

Deliver `docs/PRINTER_SETUP.md` with a compatibility matrix: platform, model, connection, paper width, encoding, cutter, test date, and status (physically verified / simulated / unverified). A software fake validates logic only. Without access to real hardware, report printing as implemented but hardware validation pending; never claim physical success.

## 8. Backup and restore

Provide manual export and configurable local scheduled backups while the app is running, plus a catch-up backup on next launch. A second copy on removable storage is recommended in the UI because a backup on the same failed device cannot help.

Use SQLite's supported consistent backup procedure, or quiesce database access and safely checkpoint/close it before copying. Never copy a live database file alone while ignoring its WAL. Backups include database, required local assets, manifest with schema/app version and checksum, and no transient locks or printer sockets.

For restore: validate archive paths against traversal, manifest/checksum, currency/version compatibility, and SQLite integrity; refuse unsupported future versions. Show a summary of restaurant, backup date, and bill count. Require owner confirmation, create a pre-restore backup, stage the restored data, and perform an atomic replacement or recoverable swap. Roll back on failure. Restore must not automatically send historical queued print jobs; require explicit review of pending/unknown jobs. Document which installation identity and receipt sequence are retained during a continuation restore.

PINs provide app access control, not database encryption. Disclose whether backup files are encrypted. If encryption is added, use authenticated encryption through a maintained implementation and a clear recovery policy; no custom cryptography or hardcoded keys.

## 9. Visual and interaction requirements

Use a clean, practical POS design: warm neutral surfaces, one accent color, readable totals, accessible contrast, status text plus color, and touch targets at least 48 logical pixels. Support narrow portrait phones, landscape tablets, and resizable desktop windows. Respect text scaling and keyboard navigation. Avoid hover-only controls.

Provide clear empty/loading/error states, destructive-action confirmation, refund/void reasons, and visible local save/printing status. Search should be easy to reach. Do not require customer details to finish a normal bill. Do not label remote sync as active since v1 has no sync.

## 10. Implementation phases

Complete each phase as working, persisted behavior and maintain `docs/PROGRESS.md` with completed work, checks, assumptions, and remaining limitations.

1. **Foundation:** Flutter project, responsive navigation, database/migrations, setup, local roles, seedable separate demo mode, money/time services.
2. **Ordering:** menu CRUD/import, tables, durable orders/cart, pricing engine, order recovery, KOT submission/corrections.
3. **Checkout:** atomic idempotent finalization, payment/change, immutable bills, receipt preview, history, authorized refunds.
4. **Printing:** receipt/KOT encoders, durable queue, Bluetooth/TCP/Windows adapters, configuration, retries and test output.
5. **Operations:** shifts, drawer movements, expenses, SQL-based dashboards, charts, ledger and CSV exports.
6. **Reliability:** backup/restore, migrations, audit review, performance profiling, integration tests, physical hardware checklist.
7. **Delivery:** Android APK, Windows release bundle/installer, clean-machine installation instructions, build scripts, screenshots and honest validation report.

Do not stop after scaffolding or UI mockups. If toolchains/hardware are unavailable, continue all feasible implementation and tests, then report exactly which build or hardware checks remain blocked. Do not substitute TODOs, simulated success, or in-memory repositories for required production behavior.

## 11. Meaningful tests and acceptance criteria

Automated checks must cover the risks of offline financial storage and platform integrations:

- Pricing fixtures: inclusive/exclusive/disabled taxes, modifiers, line and bill discounts, remainder allocation, split payments, cash change, and refund allocation.
- Double-tap/retry finalization produces one bill, one receipt number, correct payments and one original print job.
- Transaction failure leaves no partial bill, payment, sequence allocation, or closed order.
- Kill/restart recovery preserves committed carts and sales; interrupted print attempts become unknown.
- Menu/settings changes do not alter historical receipt snapshots or silently reprice open lines.
- KOT retries do not duplicate submissions; post-submission cancellations produce correction tickets.
- Cumulative partial refunds cannot exceed original quantities or amounts.
- Dashboard fixtures reconcile bills, old-sale refunds, split payments, tax, charges, expenses and drawer balances; test timezone/cutoff boundaries and empty/negative periods.
- Permissions are enforced below the UI; unauthorized refunds/restores fail.
- Schema migration preserves an older populated database; corrupt and unsupported backups are rejected; successful cross-platform restore preserves financial records.
- Simulated printer failures test timeout, queue persistence, uncertain outcomes, formatting, and explicit retry semantics.
- CSV exports match selected date filters and resist formula injection.

Run formatting, `flutter analyze`, unit/database/widget tests, and supported integration tests. Produce an Android release APK and a Windows release build if the corresponding toolchains exist. Production APK signing needs the owner's private release key; never generate/commit a signing secret and call it production signing. Label local/debug-signed artifacts accurately. Windows delivery must include required DLLs/assets and must be tested as a bundle, not just a lone EXE.

Manual acceptance: airplane-mode billing, app restart during ordering, reboot after sale, Bluetooth permission denial, printer out of paper/disconnected, 58/80 mm long-name receipts, split tender, partial refund, overnight business-day cutoff, backup restoration, and installer/run on a clean Windows machine. Mark each check as passed/failed/not run with evidence.

Performance target: menu search and local order edits should feel immediate for 1,000 items; date-filtered dashboards should remain usable with 50,000 bills. Profile on an identified reference device and document results, rather than claiming unmeasured timing guarantees.

### Completion definition

Deliver working source, migration files, reproducible setup/build commands, test results, artifact paths where built, and documentation. Clearly list unavailable toolchains, unverified hardware, signing needs, and any incomplete feature. A release is ready for a café pilot only after the actual target printer and operating devices pass the manual checklist.

## 12. Later roadmap — not part of v1

Local-network multi-counter operation requires one authoritative host/service, authenticated clients, concurrent-order conflict handling and a defined host-offline policy. Do not implement it by sharing database files. Cloud backup/dashboard, QR ordering, multi-branch reports, stock/ingredient accounting, loyalty and online payment verification are separate later projects.

## 13. Official implementation references

- Flutter platforms: https://docs.flutter.dev/reference/supported-platforms
- Flutter desktop: https://docs.flutter.dev/platform-integration/desktop
- Drift platforms: https://drift.simonbinder.eu/platforms/
- Drift setup: https://drift.simonbinder.eu/setup/
- Android Bluetooth permissions: https://developer.android.com/develop/connectivity/bluetooth/bt-permissions
- Windows RAW printing: https://learn.microsoft.com/windows-hardware/drivers/print/raw-data-type

Check current official documentation when selecting packages or implementing native adapters. These references support platform choices; they do not certify a particular thermal printer.
