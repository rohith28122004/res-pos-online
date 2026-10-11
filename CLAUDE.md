# CLAUDE.md — CaféDesk Online (connected café POS)

Scope: this repository only (`res-pos-online`). It was cloned from the offline CaféDesk
(`res-pos`) and extends it with a LAN host, waiter and kitchen devices, and a Cloudflare relay.

Read first, in this order:
1. `CONNECTED_BUILD_SPEC.md` — the acceptance contract for the connected product.
2. `docs/PROGRESS.md` — what is done, what was checked, what is pending.
3. `docs/CONNECTED_ARCHITECTURE.md`, `docs/PROTOCOL.md`, `docs/PAIRING_AND_SECURITY.md`.

`docs/OFFLINE_POS_BUILD_SPEC.md` and `docs/OFFLINE_PROGRESS.md` are the **historical** offline
baseline. Their money, permission, audit, backup and printing guarantees still apply; their
"no network / no cloud / no sync" limits do not apply to this repository.

## Hard boundaries

* Never touch the offline app: not `C:\Users\rohit\projects\cafedesk`, not the `res-pos` repo,
  its releases or its installed data. Never touch `qrmenu`.
* Push only to `https://github.com/rohith28122004/res-pos-online` (check `git remote get-url
  origin` before every push). No force-push.
* Cloudflare: develop and test locally (`wrangler dev`, vitest with local bindings). Deploying
  to Cloudflare needs an explicit instruction from the owner.
* Never commit secrets: signing keys, `.dev.vars`, TLS private keys, device or host
  credentials, databases, backups.
* Owner decision (2026-10-11): **no encrypted cloud backup** — backups stay local. Do not build
  it from the spec.

## Toolchain (this PC)

* `. .\scripts\dev-env.ps1` first in every PowerShell session (Flutter, Android SDK, Java,
  pub/Gradle caches on D:).
* Windows Smart App Control is ON here and blocks unsigned engine tools that lack reputation.
  The pinned SDK in `dev-env.ps1` (3.47.6) was chosen because its tools ran; since 2026-10-11
  its Android *release* `gen_snapshot` is blocked (Windows release and Android profile still
  run) — see BUILD_AND_RELEASE.md. Do not "upgrade Flutter" without re-checking, and never turn
  Smart App Control off. The unsigned Windows build itself cannot be launched on this PC.
* `scripts/check.ps1` = format check, analyze, all Flutter tests. Cloud: `cd cloud; npm test`.
* After editing `lib/core/database/tables.dart`: `dart run build_runner build`.
* Schema change = new version: bump `AppDatabase.latestSchemaVersion`, run
  `dart run drift_dev make-migrations`, add a `fromNToM` step, extend the migration test.
  Never edit a frozen schema or an old step; never wipe data.

## Non-negotiables

* Money: integer paise only, `divRoundHalfUp`, largest remainder. No doubles in totals.
* One pricing engine (`core/pricing`) for cart, checkout, receipts, host commands and tests.
  Waiter phones show cached prices as estimates; the host decides the price.
* Widgets call services; services enforce `Actor.require` / owner approvals and use one
  transaction per business action. Never rely on hiding a button.
* The POS host is the only authority for orders, kitchen tickets, bills, refunds and receipt
  numbers. The cloud relays and projects; it never finalizes anything itself.
* Remote work arrives as protocol commands (`docs/PROTOCOL.md`): validated, authenticated
  (device credential + host-signed staff session), idempotent by command id + body hash, and
  committed in the same transaction as their business changes and outbox events.
* Bills, bill lines, payments, refunds and KOT lines are append-only. Corrections are refunds
  or correction tickets.
* Checkout/refund/KOT take an operation id; keep idempotency intact.
* Printing never touches money or bills; unknown print outcomes are never auto-retried. Only
  the host prints; remote delivery never creates extra print jobs.
* Reports are SQL over persisted rows by stamped business date (`REPORT_DEFINITIONS.md`). Cloud
  reports are projections and always show how fresh they are.
* Backups only via `VACUUM INTO`; restore keeps all validation, the pre-restore backup and
  rollback, and starts a new host epoch.
* LAN traffic is TLS with a certificate pinned at pairing. Never disable certificate checks,
  never send credentials in clear text, never log passwords, tokens or customer details.
* Honest reporting: never claim a printer, device, network path or build check passed unless
  it actually ran. Fakes in tests are not physical-device verification.
