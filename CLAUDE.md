# CLAUDE.md — CaféDesk (offline café POS)

Scope: this standalone Flutter app only. It shares no code, backend or deployment with any
other project (RetroClub, QR Menu). Read `OFFLINE_POS_BUILD_SPEC.md` (acceptance contract) and
`docs/PROGRESS.md` (status) before changing anything; update PROGRESS.md with every change.

## Toolchain (this PC)

* `. .\scripts\dev-env.ps1` first in every PowerShell session (Flutter, Android SDK, Java,
  pub/Gradle caches on D:).
* Windows Smart App Control is ON here and blocks unsigned engine tools that lack reputation.
  The pinned SDK in `dev-env.ps1` is one whose `flutter_tester`, `impellerc` and
  `gen_snapshot` run. Do not "upgrade Flutter" without re-checking (see BUILD_AND_RELEASE.md).
* Run tests with `flutter test --no-test-assets` (or `scripts/check.ps1`).
* After editing `lib/core/database/tables.dart`: `dart run build_runner build`.
* Schema change = new version: bump `AppDatabase.latestSchemaVersion`, run
  `dart run drift_dev make-migrations`, add a `fromNToM` step, extend the migration test.
  Never edit a frozen schema or an old step; never wipe data.

## Non-negotiables

* Money: integer paise only, `divRoundHalfUp`, largest remainder. No doubles in totals.
* One pricing engine (`core/pricing`) for cart, checkout, receipts and tests.
* Widgets call services; services enforce `Actor.require` / owner approvals and use one
  transaction per business action. Never rely on hiding a button.
* Bills, bill lines, payments, refunds and KOT lines are append-only. Corrections are refunds
  or correction tickets.
* Checkout/refund/KOT take an operation id; keep idempotency intact.
* Printing never touches money or bills; unknown print outcomes are never auto-retried.
* Reports are SQL over persisted rows by stamped business date (`REPORT_DEFINITIONS.md`).
* Backups only via `VACUUM INTO`; restore keeps all validation, the pre-restore backup and
  rollback.
* No network calls except LAN printers. No cloud, no analytics, no sync.
* Never commit secrets: `android/key.properties`, keystores, certificates, databases, backups.
* Honest reporting: never claim a printer, device or build check passed unless it ran.
