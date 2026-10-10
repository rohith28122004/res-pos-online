# Architecture

```
Flutter UI (lib/features/*/presentation, lib/app)
   │  Riverpod: app state, session, Services bundle
   ▼
Application services (lib/features/*/application)   ← permissions + transactions here
   │  ServiceContext (db, clock, ids, audit, approvals)
   ▼
Domain (lib/core/money, pricing, time, security)     ← pure Dart, no I/O
   │
Drift / SQLite (lib/core/database)                    ← background isolate, WAL, FK on
   │
Printing (lib/core/printing): documents → layout → encoders → queue → transports
   │                                                          ├ TCP (dart:io)
   │                                                          ├ Bluetooth (Kotlin plugin)
   │                                                          └ Windows spooler (dart:ffi)
Backup (lib/core/backup): VACUUM INTO + manifest + checksum; validated restore
```

## Principles

* **Widgets never write to the database.** They call services. Services check the actor's
  role (`Actor.require`) and owner approvals (`ServiceContext.verifyApproval`) themselves, so
  hiding a button is never the only protection.
* **One transaction per business action.** Checkout, refunds, KOT submissions, shift close,
  restore preparation and CSV import each commit or roll back as a whole.
* **Idempotency.** Checkout, refunds and KOT submissions take an operation id generated when
  the screen opens. `completed_operations` plus unique constraints (`bills.operation_id`,
  `bills.order_id`, `refunds.operation_id`, `kitchen_tickets.operation_id`) make retries,
  double taps and restarts safe.
* **Append-only financial records.** Bills, bill lines, tax components, payments, refunds and
  kitchen ticket lines are inserted and never updated or deleted (ticket *status* is the only
  mutable kitchen field). Corrections are refunds or correction tickets.
* **Snapshots.** Order lines capture menu data; bills capture restaurant identity, time zone
  and currency; print jobs persist a document (not a reference), so old receipts reproduce.
* **Reports are SQL over persisted rows**, filtered by the business date stamped at creation.
* **Printing is outside the money path.** A print job row is written inside the checkout
  transaction; sending happens later on the queue. Transport errors change only the job.
* **No network services.** The only sockets are LAN printers; nothing calls the internet.

## Startup (lib/app/providers.dart, runtime.dart)

1. Resolve the app-data directory, take the single-instance lock (`cafedesk.lock`).
2. Read `mode.json` (production / demo). First run shows the welcome screen.
3. Open the mode's database on a background isolate (migrations run here).
4. If not set up → setup wizard; else start the print queue (recovering interrupted jobs to
   `unknown`) and the backup scheduler (15-minute check + catch-up shortly after launch).
5. Lock screen → role-based shell. Inactivity locks back to the lock screen.

Restore and mode switches close the runtime's database and rebuild every screen on the new
connection (`AppReady.generation`).

## Folder map

| Path | Responsibility |
|---|---|
| `lib/app/` | startup, runtime (DB host, queue, backups), providers, theme, shell |
| `lib/core/money/` | integer money, rounding, allocation, INR formatting/parsing |
| `lib/core/pricing/` | tax snapshots, pricing engine, refund maths |
| `lib/core/time/` | clocks, business dates, ranges, time zones (bundled tz data) |
| `lib/core/security/` | roles, permissions, approvals, Argon2id PIN hashing |
| `lib/core/database/` | Drift tables, database, migrations (`app_database.steps.dart`) |
| `lib/core/printing/` | documents, layout, ESC/POS + raster encoders, queue, transports |
| `lib/core/backup/` | backup/restore |
| `lib/core/csv/` | RFC 4180 writer/parser with formula guard |
| `lib/features/<x>/application` | services per feature |
| `lib/features/<x>/presentation` | screens per feature |
| `android/app/src/main/kotlin/…/BluetoothPrinterPlugin.kt` | Bluetooth Classic transport |
| `drift_schemas/` | frozen schema versions for migration tests |
| `test/` | domain, database, reporting, printing, migration tests |
