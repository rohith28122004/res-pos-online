# CaféDesk Online — implementation progress

Spec: `CONNECTED_BUILD_SPEC.md`. Baseline: `docs/BASELINE.md`. History of the offline app:
`docs/OFFLINE_PROGRESS.md`. Update this file with every change; if a session runs out of
context, resume from here.

Legend: ✅ done and checked · 🟡 implemented, check pending (see note) · ⛔ blocked by an
external dependency · ⬜ not started

## Phase checklist

### 1. Isolated workspace, identity, baseline
- ✅ New checkout `C:\Users\rohit\projects\res-pos-online`, cloned from GitHub over HTTPS; source
  `origin` removed; history kept; branch `connected-pos`
- ✅ Private repo https://github.com/rohith28122004/res-pos-online created; baseline `main`
  pushed; remote URL checked before every push
- ✅ Separate identity: `com.cafedesk.online`, `cafedesk_online.exe`, product "CafeDesk
  Online" (own `%APPDATA%` folder), `cafedesk_online*.sqlite`, own lock and backup names
- ✅ Baseline checks on the untouched clone: format clean, analyze clean, 168/168 tests
- ✅ `CLAUDE.md`, README, `docs/BASELINE.md`, spec saved as `CONNECTED_BUILD_SPEC.md`; offline
  spec and progress kept as history

### 2. Protocol, waiter role, migrations, command dispatcher, outbox
- ✅ `docs/PROTOCOL.md` v1; `lib/core/protocol/` (canonical JSON, command/result/error types)
- ✅ Canonical JSON cross-check: `protocol/vectors/canonical_hash.json` (17 cases) passes in Dart
  and in the cloud tests
- ✅ Waiter role: takes orders only; any discount needs owner approval; service/delivery
  charges need the new `discount` permission; no payment, refund, staff or reports
- ✅ Schema v4 (`from3To4`): host identity (one row), paired devices, pairing codes, staff
  sessions, command receipts, host event outbox, sync checkpoints, kitchen ticket revision
- ✅ Events written in the same transaction as orders, tickets, bills, refunds, expenses,
  shifts, cash movements, menu and table edits, staff access changes and session revocations
  (`lib/core/sync/host_outbox.dart`); gap-free sequence per epoch
- ✅ Idempotent command dispatcher (`lib/core/host/command_dispatcher.dart`): same id + same
  body → stored result; same id + other body → `COMMAND_ID_REUSED`; stale revision →
  `STALE_REVISION` with current state; atomic table opening; host-side price/availability
  check; one ticket and one KOT print job per command; forward-only kitchen status

### 3. LAN host, pairing, sessions, client persistence
- ✅ Host keys (`lib/core/host/host_keys.dart`): self-signed EC P-256 TLS certificate, Ed25519
  signing key, X25519 seal key; private parts only in OS secure storage (`SecretStore`)
- ✅ LAN server (`lib/core/host/lan_server.dart`): HTTPS + WebSocket, pinned certificate,
  every route but health/pair authenticated (device credential + live, host-signed staff
  session), 256 KiB body cap, 50-line cap, per-address limits on pairing and sign-in,
  sockets re-checked every 60 s
- ✅ Pairing (`lib/features/devices/application/device_service.dart`): single-use codes, 10
  minutes, bound to role, hashed; device credentials stored only as hashes; revocation ends
  sessions at once; `device.paired`/`device.revoked` events for the cloud
- ✅ Staff sessions (`lib/core/host/session_service.dart`): 12-hour Ed25519-signed tokens checked
  against live rows; role must fit the device; sealed (X25519 + AES-GCM) sign-in and owner
  approval so passwords are readable only by the POS
- ✅ Device side: own database (`lib/core/sync/client_database.dart`, schema v1), pinned LAN
  client, sync engine (`lib/core/sync/device_sync.dart`): snapshot + cursor + live events,
  durable command queue (same id on every retry, lookup before resend, backoff with jitter,
  30-minute review rule, per-person isolation), one alarm per kitchen ticket, link status
- ⬜ Windows firewall / Android network notes (with the runbooks, phase 7)

### 4. Waiter → host → kitchen flow
- ⬜ Device modes POS / Waiter / Kitchen
- ⬜ Waiter: tables, menu, drafts, send, states, additions, price/availability conflicts
- ⬜ Kitchen: board, preparing/ready with revision checks, alarm without repeats, mute, keep awake
- ⬜ Host screens: connected devices, pair device, host status

### 5. Cloudflare relay (local)
- ✅ `cloud/`: Worker API (all PROTOCOL §8 routes), `RestaurantHub` Durable Object (hibernating
  sockets, durable mailbox in DO SQLite, 30-minute expiry, quarantine on new epoch, relay
  with 503/504), D1 ledger + report projections (rebuildable), private R2 backups and menu
  images. Local only; nothing deployed
- ✅ Enrollment with single-use operator codes; device registry from host events; ingest with
  gap/duplicate/content-mismatch checks; report cards from `REPORT_DEFINITIONS.md`
- ✅ Cross-restaurant isolation tests; `docs/CLOUDFLARE_SETUP.md` (local dev, runbook for a
  later deployment that needs the owner's instruction)
- ⬜ POS cloud connector (enroll, upload, relay socket) and phone cloud route

### 6. Fallback, recovery, sync status, restore
- ⬜ LAN-first, cloud fallback with the same command id
- ⬜ Restart/outage recovery, replay, sync queue / last sync screens
- ⬜ Restore → new host epoch, quarantine, reconciliation before reconnecting
- ⬜ Opt-in encrypted cloud backup with owner recovery key

### 7. Hardening, builds, runbooks
- ⬜ Security and regression tests from spec §12
- ⬜ Android APK and Windows bundle with the new identity
- ⬜ Setup runbooks, connected test checklist, pilot steps

## Builds and checks (latest run)

| Check | Result |
|---|---|
| `dart format` | clean |
| `flutter analyze` | no issues |
| Flutter tests | 204 passed, 0 failed (20 min on a loaded PC; ~1.5 min normally) |
| Cloud tests | `npm run typecheck` exit 0; `vitest run` 89 passed (9 files) |
| Android / Windows builds | not built yet in this repo |
| Physical devices / printers | not run |

## Run log

(append newest at the bottom)

- 2026-10-11 — Cloned `res-pos` at `f65c4bb` into a new folder, removed the source remote,
  created the private `res-pos-online` repo and pushed `main`. Baseline checks: format 0
  changed, analyze no issues, 168/168 tests. Separate app identity applied; re-checked:
  analyze no issues, 168/168 tests.
- 2026-10-11 — Phase 2: protocol types, waiter role, schema v4, transactional outbox, command
  dispatcher. New tests: `test/connected/` (outbox: same-transaction events, gap-free
  sequence after a rolled-back sale, financial payloads, session revocation; dispatcher:
  duplicate command → one order/ticket/print job, id reuse, table race, stored rejections,
  price/availability, stale revisions, approvals, forward-only tickets, roles/devices/forged
  actor/epoch, version and malformed bodies; canonical JSON) and a populated v3 → v4 upgrade
  test. Two older migration tests now migrate to the latest schema (services need it).
  `flutter analyze` no issues; 192 passed, 1 skipped.
- 2026-10-11 — Phase 3: host keys/TLS, LAN server, pairing, sessions, sealed requests, device
  database and sync engine. `test/connected/lan_test.dart` runs a real TLS server on
  localhost with real phone clients: single-use/expiring pairing, hashed credentials, sealed
  sign-in, wrong password/role/must-change refused, every route authenticated (missing
  credential, no session, forged token, wrong secret, other device's credential, disabled
  staff, revoked device), wrong certificate refused, rate limits, live kitchen board with one
  alarm across reconnects, revision-checked status updates, lost response resolved by lookup,
  30-minute review rule, per-person command isolation. Found and fixed: concurrent
  `deliverNow()` calls returned before the run finished; background work could outlive
  `dispose()`. 204 tests passed.
- 2026-10-11 — Cloud relay built under `cloud/` (by a delegated agent; checked here):
  `npm run typecheck` exit 0 and `npx vitest run` 89 passed, re-run in this session. Local
  Miniflare/workerd only. Deviations recorded in `docs/CLOUDFLARE_SETUP.md`: the renamed test
  package `@cloudflare/vitest-plugin`; event pages carry `through` (matches the LAN host);
  stricter session checks (epoch, role from `staff.access_changed`).

## Assumptions and decisions

- The POS host is a Windows PC (spec §3). Android POS mode stays the offline standalone mode
  and does not serve other devices.
- The Dart package name stays `cafedesk`; only install/data identities changed.

## Remaining limitations / open items

- This PC has Smart App Control on, so the unsigned Windows build cannot be launched here; the
  host is exercised through automated tests until a signed build or another PC is available.
