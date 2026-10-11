# Cloudflare setup — CaféDesk Online cloud relay

Status (2026-10-11): **deployed on the owner's instruction** to the `production` environment —
`https://cafedesk-online.growlineecommerce.workers.dev` (details in §8). Local development and
the test suites are unchanged and still use only local simulations.

The cloud is a relay and a projection, never an authority: the POS host decides every order,
ticket, bill and refund. The protocol is `docs/PROTOCOL.md` (§8 is the cloud API).

## 1. Services

| Service | Used for | Binding |
|---|---|---|
| Workers | HTTP API: enrollment, auth, validation, event ingest, reports, private R2 access | — |
| Durable Objects (SQLite storage) | `RestaurantHub`, one per restaurant (`idFromName(restaurantId)`): hibernating WebSockets for the host and devices, the durable command mailbox, request relay, alarms for expiry/clean-up | `HUB` |
| D1 | restaurants, enrollment codes (hashed), credentials (hashed), devices, host public keys, revoked sessions, staff access, epochs, the immutable event ledger, report projections, backup manifests, enrollment rate limits | `DB` |
| R2 (private) | encrypted backup archives `restaurants/<restaurantId>/backups/<backupId>.cdenc`; menu images `restaurants/<restaurantId>/media/<name>` | `BUCKET` |

Limits and prices change; **check the official pages before sizing anything** — this document
deliberately quotes no prices or free-tier numbers:

* Workers: <https://developers.cloudflare.com/workers/platform/limits/>,
  <https://developers.cloudflare.com/workers/platform/pricing/>
* Durable Objects: <https://developers.cloudflare.com/durable-objects/platform/limits/>,
  <https://developers.cloudflare.com/durable-objects/platform/pricing/>
* D1: <https://developers.cloudflare.com/d1/platform/limits/>,
  <https://developers.cloudflare.com/d1/platform/pricing/>
* R2: <https://developers.cloudflare.com/r2/platform/limits/>, <https://developers.cloudflare.com/r2/pricing/>

Design choices made because of documented limits (values: see the pages above):

* D1 caps bound parameters per statement and queries per Worker invocation (lower on the Free
  plan). Event ingest therefore writes a whole batch (≤ 500 events, ≤ 1 MiB) with a small,
  fixed number of statements: rows travel as one JSON parameter read with `json_each(?)`
  (`src/ingest/bulk.ts`), chunked below D1's maximum value size.
* A D1 `batch()` is one transaction; each ingest is one batch, so ledger rows, device-registry
  changes and projections commit together or not at all.
* Backup uploads are buffered to verify SHA-256 before storing, so `MAX_BACKUP_BYTES`
  (50 MiB by default) must stay well under the Worker memory limit.

## 2. Layout

```
cloud/
  wrangler.jsonc              Worker, D1 (DB), R2 (BUCKET), DO (HUB → RestaurantHub, SQLite, tag v1)
  migrations/0001_*.sql       D1 schema (forward-only)
  src/index.ts                router; exports RestaurantHub
  src/auth/                   host/device credentials, Ed25519 session tokens, role table
  src/http/                   errors {error:{code,message,retryable,details}}, body limits, rate limit
  src/protocol/               canonical JSON + hashes, constants, zod schemas, enrollment codes
  src/ingest/                 POST /v1/host/events (contiguity, duplicates, gaps, epochs)
  src/projections/            projection SQL (one definition for ingest, rebuild and the CLI)
  src/reports/summary.ts      GET /v1/reports/summary (docs/REPORT_DEFINITIONS.md)
  src/restaurant_hub/         Durable Object: sockets, mailbox, relay
  src/routes/                 route handlers
  scripts/                    issue-enrollment-code, rebuild-projections (LOCAL D1 only)
  test/                       Vitest suites (run inside workerd)
protocol/vectors/canonical_hash.json   shared canonical-JSON vectors (Dart and TypeScript)
```

## 3. Local development

Requirements: Node ≥ 22.18 (Node 24 used here), npm. All bindings are simulated locally by
Wrangler/Miniflare; local state lives in `cloud/.wrangler/state` (git-ignored).

```powershell
cd cloud
npm install                      # exact versions from package-lock.json
npm run db:migrate:local         # apply D1 migrations to the local database
npm run dev                      # wrangler dev → http://localhost:8787/v1/health
npm test                         # vitest run (local D1, R2 and Durable Objects)
npm run typecheck                # wrangler types, then tsc for src/ and test/
npm run issue-enrollment-code -- --hours 24 --label "Cafe name"
npm run rebuild-projections      # or: npm run rebuild-projections -- --restaurant <id>
```

Notes:

* npm 11 prints `allow-scripts` warnings for `esbuild` and `workerd`; their install scripts are
  only checks — the binaries come from platform packages. Nothing needs approving.
* `issue-enrollment-code` prints a code like `ABCD-EFGH-JKMN-PQRS` **once** and stores only its
  SHA-256 — in the local D1, or with `--env production` in the deployed one (§8). Codes are
  single-use and expire (default 24 h). A bare `--remote` is refused; `rebuild-projections`
  stays local-only.
* `rebuild-projections` clears the report projections and replays them from the immutable
  ledger with the same SQL ingest uses; running it twice changes nothing.
* Tests run with one worker and without per-file isolation (`vitest.config.ts`), because the
  Workers Vitest integration does not support WebSockets to Durable Objects with per-file
  storage isolation (documented known issue). Every test enrolls its own restaurants.
* On this PC the very first test run took about 16 minutes before any test started (Windows
  scanning the new `workerd.exe`); one later run aborted with "Timeout starting
  cloudflare-pool runner" and one run stalled ~24 minutes inside a single test. Re-running
  passed each time (≈ 45 s for the whole suite). If it happens, re-run.

### Environment

* `wrangler.jsonc` `vars`: `MAX_BACKUP_BYTES` (50 MiB), `MAX_MEDIA_BYTES` (5 MiB). Tests lower
  `MAX_BACKUP_BYTES` to 1 MiB.
* `cloud/.dev.vars.example` documents local overrides. **The Worker needs no secrets**: host and
  device credentials are random per restaurant and only their hashes are stored; staff sessions
  are verified with each restaurant's public Ed25519 key. No Cloudflare/R2 administrator
  credential exists in the app or the repository.

## 4. API (base `https://<worker-host>/v1`)

| Route | Auth | Notes |
|---|---|---|
| `GET /health` | none | `{ok, minProtocolVersion: 1, maxProtocolVersion: 1}` |
| `POST /enroll` | enrollment code | `{enrollmentCode, restaurantId, restaurantName, hostDeviceId, hostSigningPublicKey, hostSealPublicKey, appVersion}` → 201 `{restaurantId, hostCredential}`; existing restaurantId → 409 `CONFLICT`; bad/used/expired code → 401; > 5 attempts/min per address → 429 |
| `POST /host/credential/rotate` | host | → `{hostCredential}`; old credential stops working, its sockets close |
| `GET /host/sync-state` | host | `{currentEpoch, epochs:[{epoch, startSequence, nextSequence}]}` |
| `POST /host/epoch` | host | `{epoch, startSequence, reason}`; idempotent for the same values; older/other → 409 `EPOCH_CHANGED`; returns sync state + `quarantinedCommands` |
| `POST /host/events` | host | `{hostEpoch, events}` ≤ 500 / ≤ 1 MiB → `{ackedThrough:{hostEpoch, sequence}, appended, duplicates}`; 409 `GAP {expectedNext}`, 409 `CONTENT_MISMATCH`, 409 `EPOCH_CHANGED {currentEpoch}` |
| `GET /host/socket` | host | WebSocket relay channel (§8.1) |
| `PUT /host/backups/{id}` | host | body = encrypted archive; `X-Content-SHA256` (hex) must match; `X-Manifest` = b64url JSON object (≤ 16 KiB) |
| `GET /host/backups`, `GET /host/backups/{id}` | host | own restaurant only; download carries `X-Content-SHA256`, `X-Manifest` |
| `PUT/GET/DELETE /host/media/{name}`, `GET /host/media` | host | **extension**: menu images `<id>.jpg|jpeg|png|webp` |
| `GET /device/media/{name}` | device | **extension**: menu image download |
| `POST /device/requests` | device (+ session unless `sealed_auth`) | `{kind, body}` relayed to the host; 503 `HOST_UNREACHABLE`, 504 `HOST_TIMEOUT` (8 s) |
| `POST /device/commands` | device + session | → `{commandId, mailboxState, receivedAt, result?}`; waits ≤ 8 s when the host is connected |
| `GET /device/commands/{id}` | device + session | own device's commands only (else 404) |
| `GET /device/events?epoch=&after=&limit=` | device + session | `{hostEpoch, events, through, latestSequence, snapshotRequired}` (same page shape as the LAN host) |
| `GET /device/socket` | device + session | notifications (§8.1) |
| `GET /reports/summary?from=&to=` | host, or device + **owner** session | cards of REPORT_DEFINITIONS.md, daily/hourly/top items/categories/order types/refund list, `freshness` |

Every error is `{"error":{"code","message","retryable","details"}}`. Responses carry
`Cache-Control: no-store` (media: `private, max-age=300`) and `X-Content-Type-Options: nosniff`.
Plain `http://` requests are refused with 403 `FORBIDDEN` ("Use https://"), except on
`localhost`/`127.0.0.1` for `wrangler dev`.

## 5. R2 bucket

* One bucket per environment (`cafedesk-online-dev` in `wrangler.jsonc`), bound as `BUCKET`.
* Keep it **private**: no r2.dev URL (`wrangler r2 bucket dev-url` stays disabled), no custom
  domain on the bucket, no CORS rules. All access goes through the Worker, which derives the
  `restaurants/<restaurantId>/` prefix from the authenticated credential.
* Backups are encrypted by the host before upload; the cloud never has the key. The Worker
  verifies the SHA-256 itself and passes it to R2 (`put(..., {sha256})`) as a second check.

## 6. Security notes

* Restaurant scoping: every D1 row, R2 key, Durable Object and socket is bound to the restaurant
  of the authenticated credential row; IDs in bodies/URLs are only compared (tested in
  `test/isolation.test.ts`).
* Stored secrets: only `sha256hex` of host credentials, device credentials and enrollment codes.
  Host public keys only. Session tokens are kept in the mailbox only while a command waits for
  delivery, and cleared when it is answered, expired or quarantined.
* Staff sessions: Ed25519 signature with the host signing key, `rid`/`did` binding, expiry,
  lifetime ≤ 12 h, replicated revocations (`session.revoked`), disabled staff and role changes
  (`staff.access_changed`), current host epoch, role vs device kind, role vs action.
* No admin route exists. Operator actions (enrollment codes, projection rebuild) are local
  scripts; remote use is an owner decision.
* Logs never contain request bodies, headers, credentials or tokens.

## 7. Verified documentation (read 2026-10-11)

| Page | Facts relied on |
|---|---|
| <https://developers.cloudflare.com/durable-objects/best-practices/websockets/> | `ctx.acceptWebSocket`, `webSocketMessage/Close/Error`, `serializeAttachment` (≤ 16,384 bytes, survives hibernation), ping/pong auto-response does not wake the object, alarms/requests/timers prevent hibernation, `web_socket_auto_reply_to_close` from compatibility date 2026-04-07 |
| <https://developers.cloudflare.com/durable-objects/examples/websocket-hibernation-server/> | 101 response with `webSocket: client`; `new_sqlite_classes` migration |
| <https://developers.cloudflare.com/durable-objects/api/state/> | `acceptWebSocket(ws, tags)` (≤ 10 tags, ≤ 256 chars), `getWebSockets(tag)`, `setWebSocketAutoResponse` |
| <https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/> | `ctx.storage.sql.exec` cursors (`toArray`, `one`), no `BEGIN` in `exec`, `setAlarm/deleteAlarm` |
| <https://developers.cloudflare.com/d1/worker-api/d1-database/>, <https://developers.cloudflare.com/d1/worker-api/prepared-statements/> | `batch()` is a transaction and rolls back on failure; `?NNN` parameters; `first/all/run` shapes |
| <https://developers.cloudflare.com/d1/platform/limits/> | per-statement bound-parameter and size limits, queries per invocation (see §1) |
| <https://developers.cloudflare.com/d1/reference/migrations/> | `migrations/` folder, `migrations_dir`, `wrangler d1 migrations apply` |
| <https://developers.cloudflare.com/r2/api/workers/workers-api-reference/> | `put(key, value, {sha256, httpMetadata, customMetadata})`, `get/head/list({prefix, cursor})/delete` |
| <https://developers.cloudflare.com/workers/runtime-apis/web-crypto/> | Ed25519 `sign/verify/importKey` supported; `timingSafeEqual`, `DigestStream` exist |
| <https://developers.cloudflare.com/workers/configuration/compatibility-flags/> | latest documented date 2026-08-04 (`nodejs_compat` default); `durable_object_io_tasks_prevent_eviction` 2026-10-01 |
| <https://developers.cloudflare.com/workers/testing/vitest-integration/> (+ write-your-first-test, configuration, test-apis, known-issues, migrate-to-vitest-plugin) | `@cloudflare/vitest-pool-workers` is renamed **`@cloudflare/vitest-plugin`** (npm marks the old package deprecated); `cloudflareTest()` plugin, `readD1Migrations` + `applyD1Migrations`, `exports.default.fetch` replaces `SELF`, `runInDurableObject`, `runDurableObjectAlarm`, `evictDurableObject`; WebSockets + per-file isolation unsupported |

Versions in use (exact, `package-lock.json`): wrangler 4.149.0 (bundled workerd 2026-10-06),
@cloudflare/vitest-plugin 1.4.0 (peer vitest ^4.1 || ^5; docs install vitest ^4.1 — 4.1.11
used), typescript 6.0.3, zod 4.6.5. `compatibility_date` = **2026-10-01** (supported by the
bundled workerd; includes `web_socket_auto_reply_to_close`).

## 8. Deployment — DONE on 2026-10-11 (owner's instruction)

| Item | Value |
|---|---|
| Cloudflare account | "Growlineecommerce@gmail.com's Account" (`wrangler whoami`, OAuth login already on the dev PC) |
| Worker | `cafedesk-online` (`wrangler.jsonc` → `env.production`) |
| URL (give this to the POS) | `https://cafedesk-online.growlineecommerce.workers.dev` |
| D1 | `cafedesk-online`, id `c511424f-2485-49d9-bee5-124ce4d8a8c2`, location hint APAC; migration `0001_initial_schema.sql` applied |
| R2 | `cafedesk-online`, location hint APAC, private (no r2.dev URL, no custom domain, no CORS) |
| Durable Object | `RestaurantHub`, SQLite storage, migration tag `v1` |
| Versions | `e52535a1-7e41-4c31-93ab-65983351897a` (first), `91be11a3-0b37-472b-8f38-8576c2d69484` (https-only; current) |
| Secrets | none (the Worker needs none) |

Smoke checks run against the deployed URL: `GET /v1/health` → 200 with `no-store` and
`nosniff`; host route without / with a bogus credential → 401; enroll with malformed keys → 400,
with a wrong code → 401; unknown route → 404; plain `http://` → 403. **Not yet run:** the full
end-to-end test against the deployed relay (it enrolls test restaurants in the production
database, so it waits for the owner's OK):
`flutter test --dart-define=CAFEDESK_CLOUD_URL=https://cafedesk-online.growlineecommerce.workers.dev test/e2e`.

Day-to-day operation (from `cloud/`):

```powershell
npm run issue-enrollment-code -- --env production --label "Cafe name" --hours 24   # code for a café's POS
npx wrangler deploy --env production          # after npm test + npm run typecheck pass
npx wrangler deployments list --env production
npx wrangler rollback <version-id> --env production   # code only, never data
npx wrangler d1 migrations apply DB --env production --remote   # new migrations, before deploying code that needs them
```

Not done (optional): a custom domain, and checking the account's Workers plan against the limits
in §1 (the free plan's per-request CPU limit is the one most likely to matter for large uploads).

### Original runbook (as followed)

1. `cd cloud && npx wrangler login` (the owner's Cloudflare account, in a browser).
2. Create resources (pick an environment suffix, e.g. `prod`):
   * `npx wrangler d1 create cafedesk-online-prod` → copy the printed `database_id` into
     `wrangler.jsonc` (`d1_databases[0].database_id`; also set `database_name`).
   * `npx wrangler r2 bucket create cafedesk-online-prod` → set `r2_buckets[0].bucket_name`.
     Leave r2.dev access and bucket custom domains **off**.
   * Rename the Worker (`name`) if wanted; the Durable Object migration `v1`
     (`new_sqlite_classes: ["RestaurantHub"]`) is applied by the first deploy. Never edit an
     applied migration; add `v2` etc.
3. Schema: `npx wrangler d1 migrations apply DB --remote`.
4. Deploy: `npx wrangler deploy`. Note the version ID; `npx wrangler rollback <version-id>`
   reverts code (not data). Deploying closes all open WebSockets; clients reconnect.
5. Domain/TLS: add a Custom Domain for the Worker (Workers & Pages → the Worker → Domains, or
   `routes: [{ "pattern": "api.example.com", "custom_domain": true }]` in `wrangler.jsonc`);
   Cloudflare issues the certificate. Consider disabling the `workers.dev` route
   (`"workers_dev": false`) so only the custom domain serves the API.
   (<https://developers.cloudflare.com/workers/configuration/routing/custom-domains/>)
6. Secrets: none are needed today. If one is added: `npx wrangler secret put NAME`
   (<https://developers.cloudflare.com/workers/configuration/secrets/>), never in the repo.
7. Enrollment codes for real cafés: the local script refuses `--remote` on purpose. With the
   owner's decision, generate a code locally and insert only its hash remotely, e.g. adapt
   `scripts/issue-enrollment-code.mjs` to print the SQL and run
   `npx wrangler d1 execute DB --remote --command "INSERT INTO enrollment_codes …"`.
8. Smoke test: `GET https://<domain>/v1/health`, then enroll one test restaurant.
9. Projection rebuild in production (only if a projection bug is fixed): run
   `rebuildProjections()` logic against the remote D1 via a reviewed one-off, with the owner's
   approval; the ledger itself is never modified.

## 9. Known limitations / pending

* Deployed (§8), but only smoke-checked: the full end-to-end run against the deployed relay, real
  phones and real café networks are still pending.
* Backups are buffered in memory (size cap) rather than streamed.
* `events_available` from the host is recorded but not forwarded; devices are woken only after
  a batch is durably ingested.
* The cloud never prunes the event ledger yet; a retention policy is a later decision.
