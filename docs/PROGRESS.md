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
- ✅ Windows firewall / Android network notes (`docs/PAIRING_AND_SECURITY.md` §7–8)

### 4. Waiter → host → kitchen flow
- ✅ Device modes POS / Waiter / Kitchen (welcome screen; a phone in device mode never opens
  the POS database; hosting only on Windows)
- ✅ Waiter (`lib/features/waiter/`): tables with occupancy, menu search/categories/variants/
  modifiers/notes, drafts per table, send to kitchen through host acceptance, explicit states
  (saved on phone / waiting in cloud / accepted / not accepted / check before sending again),
  additions to accepted orders, owner-approved corrections, price/sold-out conflicts shown for
  confirmation, "add to existing order" when a table is taken
- ✅ Kitchen (`lib/features/kitchen/`): columns on tablets, tabs on phones, preparing/ready with
  revision checks, one alarm per new ticket (not on replay), mute, keep-awake, honest pending
  state
- ✅ Host screens: Connected devices (phone connections on/off, pair with QR + expiry, device
  list and removal, cloud connection, reset), live status chip in the top bar
- 🟡 Render tests at phone and tablet sizes pass; not yet tried on a physical phone, camera QR
  scanner or kitchen speaker (no device here)

### 5. Cloudflare relay (local)
- ✅ `cloud/`: Worker API (all PROTOCOL §8 routes), `RestaurantHub` Durable Object (hibernating
  sockets, durable mailbox in DO SQLite, 30-minute expiry, quarantine on new epoch, relay
  with 503/504), D1 ledger + report projections (rebuildable), private R2 storage
- ✅ **Deployed 2026-10-11 on the owner's instruction**: `https://cafedesk-online.growlineecommerce.workers.dev`
  (D1/R2 `cafedesk-online`, APAC; `CLOUDFLARE_SETUP.md` §8). Smoke checks passed; full
  end-to-end against it passed (owner's OK; left two labelled test restaurants)
- ✅ Enrollment with single-use operator codes; device registry from host events; ingest with
  gap/duplicate/content-mismatch checks; report cards from `REPORT_DEFINITIONS.md` with
  freshness (acknowledged cursor, last ingest time)
- ✅ Cross-restaurant isolation tests; `docs/CLOUDFLARE_SETUP.md` (local dev, deployment,
  enrollment codes, rollback)
- ✅ POS cloud connector (`lib/core/host/cloud_connector.dart`: enroll + history backfill,
  ordered upload with acknowledgements, relay socket) and phone cloud route
  (`lib/core/sync/cloud_route.dart`)

### 6. Fallback, recovery, sync status, restore
- ✅ LAN first, cloud fallback with the same command id and body; end-to-end against
  `wrangler dev`: LAN down → one order / one ticket / one print job; the same command over the
  LAN afterwards changes nothing; POS offline → nothing accepted, delivered once on return
- ✅ Recovery: a phone app closed with an unsent order sends it once after restart; lost
  response resolved by lookup; replay ignores duplicate/old events and applies a page in
  sequence order; a change between snapshot and live connection is not lost; kitchen
  reconnect does not repeat alarms
- ✅ Sync status: phone banner (Wi-Fi / cloud / not connected, data age, POS offline from the
  cloud, restored POS), Sent tab (sync queue with states), Connection details; POS top-bar
  chip (phones live, cloud state), cloud card (copied up to #, last copy, waiting changes,
  last error, Copy now)
- ✅ Restore (`PROTOCOL.md` §5.4): new host epoch, this PC's pairings kept (removed phones stay
  removed), all sessions ended, phones and cloud off until the owner chooses Reconnect
  devices; reconnecting re-sends the restored history then `host.restored`, and the cloud
  drops report rows the restored POS no longer has. Phones hold old-epoch commands for review.
  End-to-end against `wrangler dev`: 2 bills → restore a backup with 1 → cloud shows 1
- ✅ Outbox pruning: 7 days; with a cloud, current-epoch events stay until acknowledged
- ➖ Encrypted cloud backup: **not built — owner decision, 2026-10-11** ("no need of encrypted
  backup"). Local backups on the PC work as before. The cloud's private backup routes exist
  but nothing on the POS uploads backups.

### 7. Hardening, builds, runbooks
- ✅ Spec §12 checks mapped to automated tests (see the run log); added identity separation,
  replay order, phone restart and snapshot/live race tests
- 🟡 Builds with the new identity: Windows bundle ✅ (unsigned, not launched here); Android
  arm64 TEST APK ✅ (profile mode); Android **release** APK ⛔ blocked by Smart App Control on
  this PC — build it on another machine (run log)
- ✅ Docs: `CONNECTED_ARCHITECTURE.md`, `PAIRING_AND_SECURITY.md` (keys, pairing, sign-in,
  cloud trust, Windows firewall/sleep/fixed IP, Android Wi-Fi notes),
  `CONNECTED_TEST_CHECKLIST.md` (physical checks A–E and pilot steps), README index
- ⬜ Physical-device run of `CONNECTED_TEST_CHECKLIST.md` (needs the café's PC, phones, Wi-Fi)

### 8. Clearer screens per role, no demo, kitchen on/off (owner request, 2026-10-11)
- ✅ Owner said admin and waiter screens looked alike and confusing. Chosen with the owner:
  * **No demo café / built-in accounts.** First launch: "What is this device for?" → Main till
    (setup wizard creates the restaurant and *your* Admin account) or Waiter phone / kitchen
    screen. The old demo database is deleted on start; a `demo` mode file is cleared.
  * **Sign-in:** tap your name, then your password ("Use email instead" still there).
  * **Admin home** (`lib/features/home/presentation/admin_home.dart`): big buttons — New order,
    Open orders, Tables, Kitchen, Bills, Shift & cash, Expenses; Manage: Reports, Menu, Staff,
    Phones & cloud, Settings; a Today card (sales, bills). Cashiers get the same home without
    the admin-only buttons. User-facing "owner" → "Admin".
  * **Waiter** (POS sign-in: `waiter_till_home.dart`; phone: `waiter_home.dart`): Tables,
    Orders, Takeaway; no payments, discounts, reports or settings; "Payment is taken at the
    till".
  * **Kitchen** (`kitchen_ui.dart`, shared by the POS and the kitchen phone): dark board,
    New → Cooking → Ready, wait-time colours, one big button per step.
  * **Kitchen on/off** (Settings → Kitchen; schema v5 `kitchen_enabled`, default on). Off: no
    Kitchen tile, kitchen displays say "switched off", kitchen invites refused, waiters get
    **To prepare** (POS and phone) and mark orders ready; the POS enforces it
    (`OrderService.canUpdateTickets`, dispatcher check for waiter phones).
- 🟡 Cloud: waiter `ticket.set_status` + `settings.changed` relay — tested locally (93 passed);
  **not deployed yet** (waits for the owner, see run log)

## Builds and checks (latest run)

| Check | Result |
|---|---|
| `dart format` | clean |
| `flutter analyze` | no issues |
| Flutter tests | see the latest run-log entry |
| Cloud tests | see the latest run-log entry |
| Cloud end-to-end (`--dart-define=CAFEDESK_CLOUD_E2E=true test/e2e`, local `wrangler dev`) | 2 passed |
| Deployed cloud | live at `https://cafedesk-online.growlineecommerce.workers.dev`; smoke checks passed; end-to-end against it: 2 passed |
| Android / Windows builds | Windows zip built (unsigned); Android arm64 TEST APK (profile) built; Android release APK blocked here |
| Physical devices / printers | not run (none available here) |

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
- 2026-10-11 — Phase 4 + connector (commit 919c29b): device modes, waiter and kitchen apps,
  Connected devices screen, cloud connector and phone cloud route. Fixed on the way: the host
  now requires `sendToKitchen` (the cloud already did). Cloud end-to-end against local
  `wrangler dev` passed (relay exactly once, no false acceptance while the POS is offline,
  sign-in through the relay, cloud report cards equal the POS dashboard).
- 2026-10-11 — Render tests for every phone/kitchen/device screen at 390 px and 1280 px
  (no exceptions, overflow or unstyled text). POS UI pass: live phone/cloud chip (replaces the
  outdated "this device only" chip), in-cart counts on menu buttons, F2/F8/F9 keys, order
  cards with type/taker/time open, tables with counts and time open. 226 passed, 1 skipped.
- 2026-10-11 — Phase 6 restore + pruning (commit 89a6dc9). Flutter 231 passed, 2 skipped (the
  opt-in end-to-end tests, run separately: 2 passed against `wrangler dev`); cloud typecheck
  exit 0, vitest 91 passed.
- 2026-10-11 — Owner decided not to build the encrypted cloud backup. Added §12 tests
  (identity separation, replay order, phone restart with a queued order, snapshot/live race)
  and the phone's Connection details. Phone replay now sorts a page by sequence before
  applying it (an out-of-order page could have skipped an update). Flutter 241 passed, 2
  skipped (opt-in end-to-end).
- 2026-10-11 — Docs: connected architecture, pairing and security, test checklist + pilot
  steps. Builds on this PC:
  * Android **release** APK: **not built** — Smart App Control now blocks 3.47.6's Android
    release `gen_snapshot.exe` (it built the offline APK the day before). Not worked around by
    changing security settings.
  * Android **test** APK built instead: `flutter build apk --profile --target-platform
    android-arm64` → `dist\CafeDeskOnline-1.0.0+1-android-arm64-TEST-profile-debug-signed.apk`
    (57,553,782 bytes, SHA-256 `5b0ae2a0…7aab13d`, full hash in the `.sha256` file).
    `aapt2 dump badging`: package `com.cafedesk.online`, label "CaféDesk Online", minSdk 24,
    INTERNET + CAMERA (camera not required). arm64 phones only; debug-signed; for testing.
  * Windows bundle: first attempt failed — `flutter_secure_storage_windows` needs the Visual
    Studio "C++ ATL" component (`atlstr.h`). With the owner's approval (administrator prompt)
    `Microsoft.VisualStudio.Component.VC.ATL` was added to Build Tools 2022, then
    `scripts\build_windows.ps1` built
    `dist\CafeDeskOnline-1.0.0+1-windows-x64-unsigned.zip` (15,671,800 bytes, SHA-256
    `7d42c1f6…1964b1c95`). `cafedesk_online.exe` version info: product "CafeDesk Online",
    company "CafeDesk", file `cafedesk_online.exe`, 1.0.0+1; **not signed**, so it cannot be
    launched on this PC (Smart App Control) — not run here.
  * Offline repo check (read-only): `C:\Users\rohit\projects\cafedesk` clean at `f65c4bb`,
    origin `res-pos` — untouched.
- 2026-10-11 — Waiter/kitchen screenshots for the owner (`test/screenshots`, opt-in, real fonts).
  Theme: filled-button and chip label styles now come from the text theme (they had no font
  family, which only showed in test renders).
- 2026-10-11 — **Cloud deployed on the owner's instruction** ("ok deploy the cloudflare") to the
  account already logged in on this PC (growlineecommerce): D1 `cafedesk-online` (APAC, schema
  applied), R2 `cafedesk-online` (APAC, private), Worker `cafedesk-online` via
  `wrangler deploy --env production`. Smoke checks on the live URL: health 200 (`no-store`,
  `nosniff`), unauthenticated/bogus credential 401, malformed enroll 400, wrong code 401,
  unknown route 404. Found plain `http://` answered → the Worker now refuses it (403) except on
  localhost; test added; redeployed (version `91be11a3…`) and re-checked (http 403, https 200).
  `issue-enrollment-code` gained `--env production`. Cloud vitest 92 passed, typecheck clean;
  Flutter 241 passed, 6 skipped (opt-in end-to-end + screenshots). The full end-to-end run
  against the deployed relay was first stopped by the session's safety check (it writes test
  restaurants into the production database); after the owner's OK it ran: **2 passed in 29 s**
  against `https://cafedesk-online.growlineecommerce.workers.dev`. Test restaurants left in the
  production D1 (label "E2E remote check"): `01a1291d-e9ea-7f54-98a2-70c61b46aeeb`,
  `01a1291e-35d4-71e6-b192-5c358c91edbf`.

- 2026-10-11 — **Clearer screens per role, no demo, kitchen on/off** (owner request; section 8).
  Kitchen on/off = commit 5631c89 (schema v5, POS + cloud checks); screens = cb36a8e. Checks:
  `dart format` clean, `flutter analyze` no issues; Flutter (via `scripts/test-local.ps1`,
  see BUILD_AND_RELEASE.md) **249 passed, 6 skipped** (opt-in end-to-end + screenshots), then
  device screens 24/24 with the new kitchen-off tests; cloud `npm test` **93 passed**,
  typecheck clean. New `integration_test/first_run_test.dart` **passed on the Android emulator**
  (`cafedesk_phone`, x86_64 debug): fresh install → Main till → setup → Admin account →
  shift → takeaway sale → bill saved, in a temporary folder. The emulator's old demo data was
  checked first (demo only); the test run uninstalls the app, so the debug build was installed
  again afterwards. Screenshots (opt-in tool) now include the till as Admin / waiter / kitchen
  and the waiter phone's To prepare tab. Android arm64 TEST APK rebuilt (profile):
  `dist\CafeDeskOnline-1.0.0+1-android-arm64-TEST-profile-cb36a8e.apk`, 73,749,243 bytes,
  SHA-256 `aacc4eab…795ebc19` (full hash in `.sha256`); package `com.cafedesk.online`.
  **Cloud not yet redeployed**: the deploy was stopped by the session's safety check and
  waits for the owner's go-ahead. Until then a waiter phone can mark orders ready over the café
  Wi-Fi, but not through the cloud (the live relay still refuses that for waiters), and the
  kitchen switch reaches phones on their next refresh rather than at once when they are on
  the cloud route.

## Assumptions and decisions

- The POS host is a Windows PC (spec §3). Android POS mode stays the offline standalone mode
  and does not serve other devices.
- The Dart package name stays `cafedesk`; only install/data identities changed.
- 2026-10-11, owner: no demo café or built-in accounts; Admin home with big buttons; kitchen
  can be switched off (waiters prepare).
- 2026-10-11, owner: no encrypted cloud backup. Backups stay local (as in the offline app).
  Spec §12 "backups remain private/encrypted" therefore applies to local files only, which are
  not encrypted (unchanged from the offline app).
- After a restore, this PC's device pairings are kept rather than the backup's: a phone removed
  after the backup must not come back, and a phone paired after it keeps working once the
  owner reconnects.

## Remaining limitations / open items

- Existing installs that used the demo café start at "What is this device for?" after
  updating; their demo data is deleted (it was sample data only).
- Phones keep the POS address from pairing; if the PC's IP changes they cannot reach it over
  the Wi-Fi until it is restored (reserve the IP in the router) or the phone is paired again.
  Automatic discovery is a possible follow-up.
- Cloud reports exist as an API only; there is no cloud dashboard app.

- This PC has Smart App Control on, so the unsigned Windows build cannot be launched here; the
  host is exercised through automated tests until a signed build or another PC is available.
