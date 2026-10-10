# Claude implementation brief — res-pos-online

> Source of truth for the connected scope of this repository (CaféDesk Online). Saved verbatim
> from the owner's brief on 2026-10-11. The original offline specification is kept as history in
> `docs/OFFLINE_POS_BUILD_SPEC.md`.

## User decision and safety boundary

Build a NEW product/repository named `res-pos-online`, starting from the existing offline CaféDesk application in `https://github.com/rohith28122004/res-pos`.

The existing `res-pos` repository and its local checkout at `C:\Users\rohit\projects\cafedesk` must remain untouched. Do not edit it, change its Git remotes, commit to it, push to it, change its releases, or change any database/settings used by its installed application. Do not work in `qrmenu` either.

This is an extension of the existing app in a separate repository, not a rebuild from scratch. Preserve its working offline financial features and add online connectivity, waiter order collection, and kitchen mobile display. This document overrides inherited **offline-only/no-cloud/no-sync** product restrictions inside the NEW repository only. Existing money, permission, migration, audit, backup and printing guarantees remain mandatory.

## Prompt — implement the complete upgrade

You are implementing `res-pos-online`. Read this entire document, inspect the source baseline, then implement and verify all phases. Do not stop at a plan, a mock UI, or placeholder APIs. Record actual progress and unresolved dependencies honestly.

### 1. Establish an isolated workspace first

1. If already in a `res-pos-online` checkout, verify its root and remote before modifying anything.
2. Otherwise create a new sibling folder, such as `C:\Users\rohit\projects\res-pos-online`. Clone the source repository there with source Git hooks and remote access treated cautiously. Never clone into the original checkout.
3. Immediately remove the copied source `origin` from the NEW clone. Record the source URL and baseline commit in `docs/BASELINE.md`; the original source must not remain a writable push remote.
4. Keep the source commit history, and create a development branch such as `codex/connected-pos`. Do not discard history or reset/delete an existing new checkout.
5. Before any push, verify the destination is exactly the user's new `res-pos-online` repository, not `res-pos`, `qrmenu`, or any unrelated repository. If GitHub CLI authentication is available, create `rohith28122004/res-pos-online` as a PRIVATE repository if it does not already exist, using the new local checkout. If it exists, inspect it before attaching or pushing; do not overwrite unrelated work or force-push.
6. If repository creation/authentication is unavailable, finish the local implementation and leave the push pending with exact instructions. Do not claim GitHub creation succeeded unless verified.
7. Use a separate application identity: Android application ID, Windows application identity, display name, support-data directory, database filenames, lock files and backup paths must distinguish **CaféDesk Online** from CaféDesk offline. A user must be able to install both without overwriting either app or sharing their production database.
8. Do not import/copy the offline app's production data automatically. A later optional import uses a user-selected backup COPY, preview and confirmation; never opens or modifies the source database. Do not read real credentials or personal data for development.
9. Update `CLAUDE.md`, README, and progress in the NEW repository to reflect this document. Preserve the original offline specification as historical baseline rather than falsely treating it as the current connected scope.

### 2. Baseline to preserve

The inspected source is a Flutter Android/Windows app using Riverpod and Drift/SQLite. It already includes:

- Integer-paise pricing, tax modes, discounts, immutable bill snapshots and partial refunds.
- Durable orders, tables, idempotent kitchen ticket submission/corrections and kitchen board.
- Email/password local sign-in with Argon2id, owner/cashier/kitchen roles, approval workflows.
- Atomic idempotent checkout, split payments, cash change, receipt numbering and audit.
- SQL sales dashboard, CSV export, shifts, drawer movements and expenses.
- Durable receipt/KOT print queue with Bluetooth, TCP and Windows spooler adapters.
- Consistent backup/restore, schema migrations and separate demo mode.

Re-inspect the actual checkout: file names/schema versions may have advanced. Useful integration points observed in the baseline:

```text
lib/app/runtime.dart
lib/app/providers.dart
lib/core/service_context.dart
lib/core/database/app_database.dart
lib/core/database/tables.dart
lib/core/security/permissions.dart
lib/features/auth/application/auth_service.dart
lib/features/orders/application/order_service.dart
lib/features/orders/presentation/kitchen_screen.dart
lib/features/checkout/application/checkout_service.dart
lib/features/dashboard/application/report_service.dart
lib/core/printing/queue/
lib/core/backup/backup_service.dart
docs/PROGRESS.md
scripts/dev-env.ps1
```

Run baseline checks in the NEW checkout and record the results. Existing source progress reports are historical evidence, not checks run in this session. Preserve the pinned Flutter/toolchain guidance unless a verified reason requires change; do not repeat large tool installations without checking what is installed.

### 3. Product architecture: one authority per café

Use this topology:

```text
Waiter Android app ---- LAN TLS ----> POS desktop host / SQLite
Kitchen Android app -- LAN TLS ---->          |
                                              | outbound HTTPS / WebSocket
                                              v
Waiter / kitchen -- HTTPS --> Cloudflare Worker + restaurant Durable Object
                                      |             |
                                      D1            R2
                               cloud projections   images / backup files
```

- The designated Windows POS host is the sole authority for live order changes, kitchen submissions, pricing, checkout, refunds and receipt sequences for its restaurant.
- The host can continue billing and serve paired local devices without internet, provided the café LAN works and the host is running.
- The cloud relays commands to the same host, keeps durable command status, replicates accepted events, and supplies cloud report projections/backups. It does not independently finalize bills or mutate live orders when the host is unreachable.
- A standalone Android POS mode may retain independent offline billing, but it is not a second simultaneous authority for an enrolled restaurant. Designate mode explicitly. Promotion/failover to another host is outside the first connected release.
- No sharing SQLite over network drives. No two-way whole-database replication. No last-write-wins reconciliation for bills/payments or table ownership.

Connectivity behavior:

| Condition | Expected behavior |
|---|---|
| Host + LAN available, internet down | POS, waiter orders and kitchen updates work locally; cloud events queue |
| Host reachable through cloud, LAN unavailable | Paired devices send commands through cloud relay; same host accepts them |
| Host unreachable but cloud available | Saved drafts/pending commands only; no accepted-order/kitchen/payment confirmation |
| Both connections unavailable | POS host bills locally; isolated phones save drafts and show not delivered |
| Internet reconnects | Replay events and queued commands safely; do not duplicate tickets, sales or printing |

Prefer LAN when reachable; fall back to cloud. Both routes must reuse the same command ID/body and reach the same authority. Host startup/restore must not create two active host identities. Cloud enrollment prevents another device assuming the host role silently. Show host status and last cloud sync time.

### 4. Cloudflare services

Implement a TypeScript Worker backend under `cloud/` with Wrangler local development, migrations and tests.

- **Workers:** authenticated HTTP API, validation, enrollment, sync endpoints, report reads and private R2 access.
- **Durable Objects:** one logical coordination object per restaurant, authenticated WebSocket routing, durable cloud command mailbox and notification sequence. Prefer the documented hibernation API for idle sockets. Sockets alone are not durable delivery.
- **D1:** restaurant/device metadata, accepted event ledger, command results where appropriate, report projections, and indexes. Treat projections as rebuildable from immutable host events.
- **R2:** private restaurant-scoped menu images and optional encrypted backup archives with checksums/manifests. Do not expose public backups or ship R2/Cloudflare administrator credentials in the app.

Use a single development deployment with strict restaurant scoping first. Every cloud row, object key, socket and lookup must bind to an authenticated restaurant; never trust a client-provided restaurant ID alone. Automated tests must prove cross-restaurant isolation. Do not promise free hosting or invent pricing/limits; document required services and check current official limits before sizing.

Keep Durable Object acceptance of a relay command distinct from POS business acceptance. A queued cloud command is not yet an accepted kitchen order. Design cross-store updates with replayable state, not an imaginary transaction spanning D1, Durable Object storage and desktop SQLite.

Deliver `.dev.vars.example`/environment examples without secrets, Wrangler configuration, D1 migrations, Durable Object migrations, R2 setup instructions, local development commands and deployment runbook. Implement locally first. Production deployment requires an explicit final instruction; repository creation does not authorize publishing production services.

### 5. Pairing, authentication and roles

- Preserve existing local owner/cashier/kitchen accounts; add waiter with narrow ordering permissions. Waiters cannot collect payments, refund, discount without approval, manage staff or read financial reports.
- Kitchen users see ticket data and may perform allowed preparing/ready transitions; they cannot edit prices, bills or unrelated settings.
- Owner enrollment creates a restaurant identity and a host device identity. Pair waiter/kitchen devices with an owner-generated short-lived, single-use QR/code bound to the restaurant and intended device role.
- Pairing must provision a revocable device credential and establish the LAN server certificate trust. Never disable certificate validation or allow cleartext credentials on the café Wi-Fi.
- Authenticated staff sessions remain required after device pairing. Derive the actor from server-verified credentials; never accept an arbitrary client-supplied owner role or staff ID as proof.
- Enforce permissions and disabled-account checks on the host, cloud API and socket subscription boundaries. Validate a device token AND its staff session as applicable.
- Use maintained cryptography, OS secure storage and short-lived access tokens with rotation/revocation. Protect refresh credentials and private keys; no universal password, admin token or secrets committed to Git.
- Define offline authorization honestly: a revocation performed remotely cannot reach an isolated host until connectivity returns. Local owner revocation is immediate; credential expiry limits offline access. Document the policy and UI.
- Rate-limit sign-in/pairing, cap request size/line counts, validate payloads, avoid passwords/tokens/order personal details in logs, and authenticate every LAN route including sockets and snapshots.
- Document Windows firewall setup and Android networking permissions. Keep the host service running while minimized; if the user closes it, explicitly show that waiter/kitchen connectivity stops. Background service mode is a separate enhancement unless implemented and tested.

### 6. Command/event protocol and migrations

Define and document a versioned protocol shared by LAN and cloud transports:

```text
Command: protocolVersion, commandId, deviceId, restaurantId,
         hostEpoch, action, aggregateId, expectedRevision, payload
Result:  commandId, state, resultId, revision, structuredError
Event:   protocolVersion, eventId, hostEpoch, sequence,
         aggregateId, revision, type, committedAtUtc, payload
```

Identity fields are validated against authenticated credentials. Client timestamps do not establish financial order or business date; host commits do.

- Generate command IDs once, persist them on the client, and reuse through timeouts, route switches and restart.
- In the host database transaction, store command ID + canonical body hash + accepted result alongside business changes and outbox events. Same ID/same request returns its stored result; same ID/different body is rejected. Adapt existing idempotency without removing it.
- Reject stale expected revisions for conflicting order/table edits. Return enough safe current state for a user to resolve the conflict. Do not silently overwrite another waiter's work.
- Atomic table opening prevents two accepted active dine-in orders for one table. Associate later edits with the existing accepted order.
- Financial writes and their outbox records commit together. Cloud delivery is at-least-once; cloud inbox deduplicates by restaurant/host epoch/event ID and checks content equality on duplicates.
- Maintain ordered replay with cursor/gap detection; acknowledge only durable ingest. Rebuild snapshots/projections idempotently. Mobile clients recover via snapshot plus cursor, then live events; handle events during snapshot without missing updates.
- Retries use bounded exponential backoff with jitter. Show terminal conflicts and authorization failures for review, not endless retries.
- Do not implement sync as uploading the entire SQLite file after every sale. Archives are backups, not live synchronization.
- Pending waiter commands should have an expiry and review policy. Do not send yesterday's isolated draft to the kitchen automatically. Accepted commands retain retrievable results after expiry.
- Queued kitchen transitions carry the ticket revision. Reconcile obsolete updates when reconnecting instead of regressing completed tickets.
- For backup restore, preserve financial IDs/sequences, pause networking, create a new host epoch, and establish reconciliation before reconnecting. Quarantine pre-restore queued commands/print jobs; do not blindly replay them or erase newer cloud history with an old backup. For initial connected release, require online re-enrollment/reconciliation after restore before connected operation resumes.

Add Drift tables/versioned migrations for device pairing, sessions where needed, order revisions, command receipts, host outbox, sync checkpoints and client draft/outbox/cache. Derive additions from the actual baseline schema; never edit frozen schema dumps/old migrations. Test upgrades from a populated baseline database.

### 7. Waiter mobile experience

Use the existing Flutter project with explicit **POS / Waiter / Kitchen** device modes. Reuse domain models/widgets where useful; avoid duplicating pricing implementations.

- Pair device, staff sign-in, visible host/cloud connectivity.
- Table list and occupancy, select/open table, menu search, categories, variants, modifiers, quantity and notes.
- Review order and send to kitchen through host acceptance. Show drafts distinctly from accepted orders.
- Explicit states: saved on device, queued for host, accepted by POS, kitchen ticket created, preparing, ready, cancelled/conflict.
- Resume accepted table orders, submit additions, show who placed them; corrections use the existing authorized correction workflow.
- Prices shown from cached menu are estimates until accepted by the host. On menu changes, present a price/availability conflict for confirmation, rather than silently submitting a different total.
- Avoid editing checkout-locked/finalized orders. Include waiter attribution and table/order references in audit and ticket data.
- Cached read data is clearly marked stale when disconnected. Sign-out must isolate each user's pending drafts and avoid delivering one user's drafts under another account.

### 8. Kitchen display experience

- Pair/login in Kitchen mode, responsive phone/tablet landscape board.
- Cards show table/order reference, waiter, accepted timestamp, elapsed time, items, variants/modifiers, notes and correction indicators.
- Preparing/ready transitions go through host authorization and revision checks.
- Audible notification only after a newly accepted durable ticket event; avoid duplicate alarms on replay/reconnect. Provide mute and clear disconnected banner.
- Keep screen awake when supported and explicitly enabled. Recover board after app restart; no ephemeral-only tickets.
- Show offline cached board and pending state updates honestly. A locally tapped status is not accepted until acknowledged.
- Separate printer submission state from ticket acceptance. Kitchen screen can show an accepted ticket even if its KOT printer fails.

### 9. POS, printing and reports

- Keep current checkout, refund, pricing, shifts and expense services; add remote-command adapters, not direct unvalidated mobile database writes.
- Host owns all receipt/KOT printing and printer configuration. Waiter/kitchen/cloud delivery does not create additional print jobs.
- One business acceptance creates one logical ticket/print job. Preserve submitted/failed/unknown physical print outcomes and explicit retries. No exactly-once physical printing claims.
- Add Connected Devices, Pair Device, Cloud Connection, Sync Queue, Last Sync and Host Status screens/settings.
- Existing POS dashboard remains authoritative and works offline. Cloud report projection is clearly marked with source host and last synchronized cursor/time; do not present stale totals as live.
- Replicate immutable bills, tax/charge components, payments/refunds, expenses and shifts sufficiently to reproduce baseline report definitions. Preserve UTC timestamps and stamped business dates.
- Cloud backup is opt-in. Encrypt uploaded financial backup archives with a maintained authenticated-encryption implementation and an explicit owner recovery key policy. Losing the recovery key must be explained; no hardcoded encryption key or uploading password hashes as reporting data.

### 10. Suggested new structure

```text
lib/core/connectivity/        # LAN/cloud selection and health
lib/core/network/             # authenticated API/WebSocket transports
lib/core/protocol/            # validated commands, results, events
lib/core/sync/                # durable outbox, replay, checkpoints
lib/core/host/                # TLS server, sessions, command dispatcher
lib/features/devices/        # enrollment, pairing, revocation
lib/features/waiter/         # drafts, tables, ordering UI
lib/features/kitchen/        # remote board/status UI (reuse existing board)
cloud/src/                   # Worker routes/auth/validation
cloud/src/restaurant_hub/    # Durable Object relay/mailbox
cloud/migrations/            # D1 schema/projections
cloud/test/
docs/CONNECTED_ARCHITECTURE.md
docs/PROTOCOL.md
docs/PAIRING_AND_SECURITY.md
docs/CLOUDFLARE_SETUP.md
docs/CONNECTED_TEST_CHECKLIST.md
docs/BASELINE.md
```

Adjust names to actual project conventions. Maintain a protocol compatibility policy so old mobile apps receive an explicit update-required error instead of corrupting data.

### 11. Implementation order

1. Safe new clone/repository and separate app/data identities; baseline checks and documentation.
2. Versioned protocol, waiter role, migrations, idempotent command dispatcher, transactional host outbox and tests.
3. Authenticated TLS LAN host, pairing, staff sessions, client persistence and connection status.
4. End-to-end waiter order → host acceptance → kitchen display → ready, including corrections and conflicts.
5. Cloudflare Worker/DO/D1/R2 local implementation, cloud relay, event ingest/replay/projection, secure enrollment and backups.
6. LAN/cloud fallback, outage/restart recovery, sync status, cloud report freshness and restore reconciliation.
7. Regression/security tests, Android/Windows builds, setup/runbooks and pilot checklist.

Finish each phase with functioning persistence, tests and progress updates. Do not claim later phases complete just because files/routes exist.

### 12. Required verification

- Original offline repo remains unchanged, and new app does not access its data directories or overwrite its installation.
- Existing financial/printer/backup/report tests pass in the new checkout.
- Populated baseline schema upgrades without changing historical financial values.
- Duplicate command over LAN + cloud produces one order mutation, one kitchen ticket and one logical print job.
- Same command ID/different body is rejected; simultaneous table creation and stale line edits are handled.
- Missing response after host commit is resolved by result lookup without repeating the business action.
- Internet outage with functioning LAN preserves the complete waiter/kitchen flow.
- Cloud relay works when LAN is unavailable but the enrolled host is online.
- Host offline never creates a false accepted order or completed bill in cloud.
- Restart/crash with queued events/commands preserves accepted results; replay gaps and duplicate/out-of-order events are handled.
- Snapshot/live subscription race does not lose events; kitchen reconnect does not repeat alarms.
- Cloud reports reconcile with baseline financial fixtures and correctly show staleness.
- Pairing expiry/reuse, device revocation, staff disabled status, wrong role, forged actor, wrong certificate and cross-restaurant access fail safely.
- Backups remain private/encrypted; restore epoch/reconciliation prevents duplicate uploads or stale command execution.
- Route switching and slow sockets do not block the cashier or UI thread.
- Both APK modes and Windows bundle use separate identities; physical thermal printer status remains honest.

Run formatting, Flutter analysis and appropriate automated tests with the baseline's pinned toolchain. Run Worker typecheck/unit/integration tests with local Cloudflare bindings. Exercise real network outage paths on test devices if available. Use fakes for automated coverage, but never label them physical-device verification.

### 13. Deliverables and completion report

Deliver working source in the NEW repo, locked dependencies, migrations, documented protocol/security, test results, commands to run the host/waiter/kitchen apps and local backend, and Android/Windows artifacts if actually built. Keep signing keys, cloud secrets, TLS private keys, databases and backup archives out of Git.

Report the exact new repo URL/branch if created/pushed, app identities, preserved source baseline commit, checks run, checks unavailable, Cloudflare deployment status, physical printer verification status and remaining pilot steps. The upgrade is not complete if only scaffolding/mock data exists. When a toolchain/account/device is unavailable, finish independent work and name the concrete pending dependency without claiming success.

Start now by establishing the safe new workspace and inspecting the baseline. Continue through implementation; keep `docs/PROGRESS.md` current. If context is exhausted, resume from that file and existing code rather than rebuilding completed phases.

## Official references to verify during implementation

- Workers / D1 bindings: https://developers.cloudflare.com/d1/worker-api/
- Durable Object WebSockets: https://developers.cloudflare.com/durable-objects/best-practices/websockets/
- Durable Object hibernation example: https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/
- R2 Worker API: https://developers.cloudflare.com/r2/api/workers/workers-api-reference/

These services support the cloud portion. Cloudflare does not provide a café's offline LAN server; that runs on the designated POS host.
