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
- ⬜ Versioned protocol types (command / result / event), canonical body hash
- ⬜ Waiter role with narrow permissions
- ⬜ Schema v4: host identity, devices, pairing codes, staff sessions, command receipts,
  host event outbox, sync checkpoints, kitchen ticket revision
- ⬜ Events written in the same transaction as orders, tickets, bills, refunds, expenses,
  shifts, cash movements
- ⬜ Idempotent command dispatcher (same id + same body → stored result; same id + other body →
  rejected; stale revision → conflict with current state; atomic table opening)

### 3. LAN host, pairing, sessions, client persistence
- ⬜ Host keys and self-signed TLS certificate; private keys in OS secure storage
- ⬜ HTTPS + WebSocket LAN server, every route authenticated, limits and rate limits
- ⬜ Single-use, short-lived pairing codes / QR bound to role; revocable device credentials
- ⬜ Host-signed staff sessions; sealed (end-to-end encrypted) sign-in and owner approval
- ⬜ Client database (pairing, drafts, command outbox, cache, cursor) and connection status

### 4. Waiter → host → kitchen flow
- ⬜ Device modes POS / Waiter / Kitchen
- ⬜ Waiter: tables, menu, drafts, send, states, additions, price/availability conflicts
- ⬜ Kitchen: board, preparing/ready with revision checks, alarm without repeats, mute, keep awake
- ⬜ Host screens: connected devices, pair device, host status

### 5. Cloudflare relay (local)
- ⬜ Worker API, restaurant Durable Object (hibernating sockets, durable mailbox), D1 ledger and
  projections, private R2
- ⬜ Enrollment, device registry, event ingest with dedupe/gap detection, cloud reports
- ⬜ Cross-restaurant isolation tests

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
| Flutter tests | 168 passed (baseline suite, after identity changes) |
| Cloud tests | not started |
| Android / Windows builds | not built yet in this repo |
| Physical devices / printers | not run |

## Run log

(append newest at the bottom)

- 2026-10-11 — Cloned `res-pos` at `f65c4bb` into a new folder, removed the source remote,
  created the private `res-pos-online` repo and pushed `main`. Baseline checks: format 0
  changed, analyze no issues, 168/168 tests. Separate app identity applied; re-checked:
  analyze no issues, 168/168 tests.

## Assumptions and decisions

- The POS host is a Windows PC (spec §3). Android POS mode stays the offline standalone mode
  and does not serve other devices.
- The Dart package name stays `cafedesk`; only install/data identities changed.

## Remaining limitations / open items

- This PC has Smart App Control on, so the unsigned Windows build cannot be launched here; the
  host is exercised through automated tests until a signed build or another PC is available.
