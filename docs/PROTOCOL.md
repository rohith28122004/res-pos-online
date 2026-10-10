# CaféDesk Online protocol — version 1

One protocol for both routes: phones ↔ POS host over the café LAN (HTTPS/WSS with a pinned
certificate) and phones ↔ Cloudflare relay ↔ POS host. The POS host is the only place where a
command becomes a business change. The cloud stores, forwards and replays; it never decides.

Status of this document: **normative** for `lib/core/protocol`, `lib/core/host`, the client
sync engine and `cloud/`. Change it together with the code and the shared test vectors in
`protocol/vectors/`.

## 1. Versioning and compatibility

* `protocolVersion` is an integer. This document defines **1**.
* Every request that carries a command, an event batch or a pairing request states the
  version it speaks. The host and the cloud each declare `minProtocolVersion` and
  `maxProtocolVersion` (both 1 today) in `GET /v1/health`.
* A request with an unsupported version is refused with HTTP **426** and error code
  `UPDATE_REQUIRED` (`details: {min, max}`) — never partially applied. The app shows
  "Update CaféDesk Online on this device".
* Adding an optional field is compatible. Removing or changing the meaning of a field, a new
  required field, a new action that old hosts cannot run, or a new event type old clients must
  understand needs a new version. Unknown event types are ignored by clients (they still
  advance the cursor). Unknown actions are refused by the host with `UPDATE_REQUIRED`.

## 2. Encoding

* JSON, UTF-8, `Content-Type: application/json`. Request bodies ≤ **256 KiB** (event batches to
  the cloud ≤ **1 MiB**). Larger → HTTP 413, `TOO_LARGE`.
* Money: integer paise. Never floats anywhere in the protocol; any non-integer number is a
  validation error.
* Times: integer milliseconds since the Unix epoch, UTC (`…At` fields). Business dates:
  `YYYY-MM-DD` strings stamped by the host.
* IDs: strings, 1–64 characters of `[A-Za-z0-9_-]` (UUIDs in practice).
* **Canonical JSON** (used for hashes): object keys sorted by UTF-16 code unit order (the
  default `String.compareTo` in Dart and `Array.prototype.sort` in JavaScript), no
  insignificant whitespace, strings escaped exactly as `jsonEncode` (Dart) /
  `JSON.stringify` (JavaScript) do, integers only. Lone surrogates are invalid input.
* `sha256hex(x)` = lower-case hex SHA-256 of the UTF-8 bytes of `x`.
* `b64url` = base64url without padding.

Shared vectors: `protocol/vectors/canonical_hash.json` lists inputs with their canonical
string and hash. Both the Dart and the TypeScript test suites check them.

## 3. Identities and credentials

| Thing | Created by | Format | Stored where |
|---|---|---|---|
| Restaurant ID | Cloud at enrollment (or the host locally until enrolled) | UUID | host DB, cloud D1 |
| Host device ID | Host at first start in POS mode | UUID | host DB, cloud |
| Host epoch | Host; starts at 1, +1 after every restore | integer ≥ 1 | host DB, cloud |
| Host TLS certificate | Host, self-signed EC P-256, 10 years | X.509 PEM; pinned by SHA-256 of DER | cert in host DB, private key in OS secure storage |
| Host signing key | Host, Ed25519 | public key 32 bytes `b64url` | private key in OS secure storage |
| Host seal key | Host, X25519 | public key 32 bytes `b64url` | private key in OS secure storage |
| Host cloud credential | Cloud at enrollment | `cdh1.<restaurantId>.<hostDeviceId>.<secret>` | host OS secure storage; cloud keeps `sha256hex` |
| Device ID | Host at pairing | UUID | host DB, device DB, cloud (via event) |
| Device credential | Host at pairing | `cdd1.<deviceId>.<secret>` | device OS secure storage; host and cloud keep `sha256hex(credential)` |
| Staff session token | Host at sign-in | `cds1.<claims>.<signature>` (§3.2) | device OS secure storage; host keeps the session row |

`<secret>` is 32 random bytes from a CSPRNG, `b64url` encoded.

### 3.1 Headers

* Device requests: `X-CafeDesk-Device: cdd1.<deviceId>.<secret>`. After sign-in also
  `Authorization: Bearer cds1.…`.
* Host → cloud requests: `Authorization: Bearer cdh1.…`.
* WebSocket upgrades carry the same headers.

### 3.2 Staff session tokens

`cds1.` + `b64url(claimsJson)` + `.` + `b64url(signature)`, where the signature is Ed25519 by
the host signing key over the ASCII bytes of `cds1.<b64url(claimsJson)>`.

Claims (all required):

```json
{"v":1,"sid":"<session id>","rid":"<restaurantId>","did":"<deviceId>","sub":"<staffId>",
 "name":"Asha","role":"waiter","ep":1,"iat":1760000000,"exp":1760043200}
```

`iat`/`exp` are **seconds**. Lifetime 12 hours. A verifier (host or cloud) accepts a token only
if: the signature verifies with the restaurant's host signing public key; `rid` equals the
restaurant of the authenticated device; `did` equals the authenticated device ID; `exp` is in
the future; `sid` is not revoked; `sub` is not a disabled staff member. The host additionally
checks its live session and staff rows (authoritative); the cloud uses the revocation lists the
host replicates through events (`session.revoked`, `staff.access_changed`).

### 3.3 Roles and what they may do remotely

| Role | Device kinds | Commands | Reads |
|---|---|---|---|
| owner | waiter, kitchen | all | snapshots, cloud reports |
| cashier | waiter, kitchen | all order and ticket commands | snapshots |
| waiter | waiter | `order.place`, `order.add`, `order.change_quantity`, `order.send_to_kitchen` | waiter snapshot |
| kitchen | kitchen | `ticket.set_status` | kitchen snapshot |

Payments, refunds, checkout, discounts, staff and settings are **not** remote actions in v1;
they stay on the POS.

## 4. Commands

### 4.1 Envelope

```json
{
  "protocolVersion": 1,
  "commandId": "0193f6a2-…",
  "restaurantId": "…",
  "deviceId": "…",
  "staffId": "…",
  "hostEpoch": 1,
  "action": "order.place",
  "aggregateId": null,
  "expectedRevision": null,
  "issuedAt": 1760000000000,
  "payload": { }
}
```

* `commandId` is generated **once** when the user taps Send, stored on the device with the
  exact body, and reused unchanged through timeouts, LAN/cloud route switches and restarts.
* `bodyHash = sha256hex(canonicalJson(command))` over the whole envelope above.
* `restaurantId`, `deviceId`, `staffId` must match the authenticated device credential and
  session token; otherwise `FORBIDDEN`. They bind the command; they are never proof.
* `hostEpoch` must equal the host's current epoch, else `EPOCH_CHANGED` (not stored; the device
  shows the command for review).
* `issuedAt` is informational. The host's clock decides business dates and order.

### 4.2 Result

```json
{
  "commandId": "…",
  "state": "accepted",
  "resultId": "<orderId or ticketId>",
  "revision": 7,
  "hostEpoch": 1,
  "eventSequence": 1234,
  "acceptedAt": 1760000000500,
  "result": { },
  "error": null
}
```

* `state` is `accepted` or `rejected`. A rejected result has `error`:
  `{"code":"PRICE_CHANGED","message":"…","retryable":false,"details":{…}}`.
* `eventSequence` is the highest event sequence written by this command (0 if none).

### 4.3 Idempotency (host)

In **one** database transaction the host: checks the command receipt table; runs the action
through the existing services; writes the receipt `(commandId, bodyHash, state, resultJson)`;
writes the outbox events. Then:

* same `commandId`, same `bodyHash` → the stored result, nothing re-run (also after restart);
* same `commandId`, different `bodyHash` → `COMMAND_ID_REUSED`, nothing run, not stored;
* business rejections (validation, conflict, price change, …) are stored like acceptances: the
  same command always gets the same answer. A corrected attempt uses a **new** `commandId`;
* authentication, authorization, epoch and version failures are **not** stored (they are not
  business outcomes) so the same command can be retried after signing in again.

`GET /v1/commands/{commandId}` returns the stored result (404 `NOT_FOUND` if the host never
committed it). This resolves "the request timed out — did it happen?" without re-running.

### 4.4 Actions

`Line` (used by `order.place` / `order.add`):

```json
{"itemId":"…","variantId":null,"modifierIds":["…"],"quantity":2,"note":"less sugar",
 "expectedUnitPrice":4500}
```

`quantity` 1–99; `note` ≤ 140 chars; `expectedUnitPrice` = unit price + modifiers the device
showed (paise); at most **50** lines per command.

| Action | aggregateId | expectedRevision | Payload | Result |
|---|---|---|---|---|
| `order.place` | null | null | `{orderType:"dine_in"\|"takeaway", tableId?, guestCount?, note?, lines:[Line], sendToKitchen:true}` | `{orderId, orderNo, orderRef, revision, ticketId?, ticketNo?, estimatedTotal}` |
| `order.add` | orderId | optional (null = append) | `{lines:[Line], sendToKitchen:true}` | same as above |
| `order.change_quantity` | orderId | **required** | `{lineId, quantity, reason?, approvalId?}` | `{orderId, revision, ticketId?}` |
| `order.send_to_kitchen` | orderId | null | `{}` | `{orderId, revision, ticketId?, ticketNo?}` |
| `ticket.set_status` | ticketId | **required** | `{status:"preparing"\|"ready"}` | `{ticketId, status, revision}` |

Rules:
* `order.place` with a table opens the table atomically. If the table already has an open
  order → `TABLE_OCCUPIED` with `details:{orderId, orderNo, revision, createdByName}` so the
  device can offer "add to that order" (`order.add`). Two phones racing for one table: exactly
  one is accepted.
* Prices: the host prices from its menu. If any line's current unit price ≠
  `expectedUnitPrice` → `PRICE_CHANGED` with `details:{lines:[{index, itemId, expected, current}]}`;
  sold out / archived / variant or modifier gone → `ITEM_UNAVAILABLE` with
  `details:{lines:[{index, itemId, reason}]}`. Nothing is written. The device shows the new
  prices and the user confirms with a **new** command.
* `order.change_quantity` with a stale `expectedRevision` → `STALE_REVISION` with
  `details:{currentRevision, order:<OrderView>}`. Reducing below what the kitchen already has
  needs a reason and an owner approval (`approvalId` from a sealed `approve` request, §6);
  without it → `APPROVAL_REQUIRED`.
* Finalized or cancelled orders → `ORDER_CLOSED` (`details:{status}`).
* `ticket.set_status` is forward-only: pending → preparing → ready, or pending → ready. A
  stale revision → `STALE_REVISION` with `details:{ticket:<TicketView>}`; a backwards move →
  `TRANSITION_NOT_ALLOWED`. A queued "preparing" that arrives after the POS marked the ticket
  ready therefore never regresses it.
* One accepted command creates at most one kitchen ticket and at most one logical KOT print job
  (the host's existing KOT operation id is derived from the command id).

### 4.5 Error codes

| Code | HTTP (when not inside a result) | Stored in receipt | Meaning |
|---|---|---|---|
| `UPDATE_REQUIRED` | 426 | no | protocol version not supported |
| `UNAUTHENTICATED` | 401 | no | missing/invalid device credential or token |
| `SESSION_EXPIRED` | 401 | no | sign in again |
| `DEVICE_REVOKED` | 401 | no | pair this device again |
| `FORBIDDEN` | 403 | no | role may not do this, or identity fields don't match |
| `STAFF_DISABLED` | 403 | no | account disabled |
| `VALIDATION` | 400 | yes (inside result) / no (malformed envelope) | bad input |
| `TOO_LARGE` | 413 | no | body or line count over the limit |
| `RATE_LIMITED` | 429 | no | slow down (`details:{retryAfterMs}`) |
| `EPOCH_CHANGED` | 409 | no | the host was restored; review before resending |
| `COMMAND_ID_REUSED` | 409 | no | same id, different body |
| `STALE_REVISION` | — | yes | someone else changed it first |
| `TABLE_OCCUPIED` | — | yes | table already has an open order |
| `ORDER_CLOSED` | — | yes | order billed or cancelled |
| `PRICE_CHANGED` | — | yes | confirm new prices |
| `ITEM_UNAVAILABLE` | — | yes | sold out / removed |
| `APPROVAL_REQUIRED` | — | yes | owner approval needed |
| `TRANSITION_NOT_ALLOWED` | — | yes | kitchen status can't go backwards |
| `CONFLICT` | 409 / — | yes when inside a result | another business conflict reported by an existing POS rule |
| `NOT_FOUND` | 404 / — | yes when inside a result | unknown order, ticket, line or command |
| `HOST_UNREACHABLE` | 503 | no | cloud: host not connected |
| `HOST_TIMEOUT` | 504 | no | cloud: host did not answer in time; ask again |
| `EXPIRED` | — (mailbox state) | cloud mailbox | not delivered within its time limit |
| `QUARANTINED` | — (mailbox state) | cloud mailbox | queued before a restore; needs review |
| `INTERNAL` | 500 | no | bug; nothing was committed |

Retry policy on devices: transport failures and `HOST_UNREACHABLE` / `HOST_TIMEOUT` /
`RATE_LIMITED` retry with exponential backoff (1 s, 2 s, 4 s … capped at 60 s) with full
jitter, always with the same command. Every other error is terminal and shown for review.

## 5. Events

### 5.1 Envelope

```json
{
  "protocolVersion": 1,
  "eventId": "0193f6a2-…",
  "hostEpoch": 1,
  "sequence": 1234,
  "type": "ticket.updated",
  "aggregateType": "kitchen_ticket",
  "aggregateId": "…",
  "revision": 3,
  "committedAtUtc": 1760000000500,
  "businessDate": "2026-10-11",
  "payload": { }
}
```

* Written to the host outbox **in the same transaction** as the change.
* `sequence` comes from the host's sequence table inside that transaction: per epoch it is
  gap-free and strictly increasing. Event identity is `(restaurantId, hostEpoch, sequence)`;
  `eventId` is unique too.
* `contentHash = sha256hex(canonicalJson(event))`. The cloud stores it; a duplicate
  `(epoch, sequence)` or `eventId` with a different hash is refused with `CONTENT_MISMATCH`.
* Events are immutable once written. Payloads are full aggregate snapshots, so a consumer
  only needs the newest revision of each aggregate.

### 5.2 Types

| Type | Aggregate | Audience | Payload |
|---|---|---|---|
| `order.updated` | order | devices + cloud | `OrderView` |
| `ticket.updated` | kitchen_ticket | devices + cloud | `TicketView` |
| `menu.changed` | menu | devices + cloud | `{}` (refetch the snapshot) |
| `tables.changed` | dining_tables | devices + cloud | `{}` (refetch the snapshot) |
| `bill.finalized` | bill | cloud | `{bill, lines, charges, taxComponents, payments}` |
| `refund.created` | refund | cloud | `{refund, lines, charges, taxComponents, payments}` |
| `expense.recorded` / `expense.voided` | expense | cloud | `{expense}` |
| `shift.updated` | shift | cloud | `{shift, closures}` |
| `cash_movement.recorded` | cash_movement | cloud | `{movement}` |
| `device.paired` | device | cloud | `{deviceId, role, name, credentialHash, pairedAt}` |
| `device.revoked` | device | cloud | `{deviceId, revokedAt}` |
| `session.revoked` | staff_session | cloud | `{sid, staffId, revokedAt}` |
| `staff.access_changed` | staff | cloud | `{staffId, role, disabled}` |

Financial payload rows are the host's database rows serialized with Drift `toJson()` —
camelCase field names exactly as in `lib/core/database/tables.dart` (for example
`bill.total`, `bill.businessDate`, `lines[].netEx`, `payments[].method`,
`payments[].applied`). Booleans are JSON booleans. They carry everything
`docs/REPORT_DEFINITIONS.md` needs. Password hashes, recovery codes and audit details are never
in events.

`OrderView`:

```json
{"orderId":"…","orderNo":12,"orderRef":"T4 · #12","orderType":"dine_in","tableId":"…",
 "tableLabel":"T4","status":"open","revision":5,"createdBy":"…","createdByName":"Asha",
 "createdAt":0,"guestCount":2,"note":null,"cancelledAt":null,"cancelBusinessDate":null,
 "estimatedTotal":45000,
 "lines":[{"lineId":"…","itemId":"…","itemName":"Filter coffee","variantName":null,
  "modifiers":["Extra shot"],"note":null,"quantity":2,"sentQuantity":2,"unitPrice":4500,
  "createdBy":"…","createdByName":"Asha"}]}
```

`TicketView`:

```json
{"ticketId":"…","ticketNo":31,"orderId":"…","orderRef":"T4 · #12","tableLabel":"T4",
 "kind":"order","reason":null,"status":"pending","revision":1,"createdByName":"Asha",
 "createdAt":0,"lines":[{"itemName":"Filter coffee","variantName":null,
 "modifiersText":"Extra shot","note":null,"quantityDelta":2}]}
```

### 5.3 Ordered replay

* Consumers keep a cursor `(hostEpoch, sequence)` = the last event applied.
* Delivery is at-least-once. A consumer ignores events at or below its cursor and treats a jump
  (`sequence > cursor + 1` in the same epoch) as a gap: it asks for the missing range, or for a
  fresh snapshot.
* Devices recover with **snapshot + cursor**: the snapshot response includes the cursor it was
  read at (same database read). The device then opens the event stream with `after=<cursor>`;
  the host streams from its durable outbox first and then live, so changes committed between
  the snapshot and the subscription are never lost.
* If the cursor's epoch is not the host's current epoch, or the host has pruned events after
  it, the stream answers `{"t":"snapshot_required"}`.
* The host keeps outbox events at least 7 days and never prunes events the cloud has not yet
  acknowledged.

## 6. Sealed requests (passwords)

Passwords never travel in readable form outside the host, on either route. A device encrypts
them to the host's X25519 seal key (received at pairing):

```json
{"v":1,"alg":"X25519-HKDF-SHA256-A256GCM","epk":"<b64url 32B>","nonce":"<b64url 12B>",
 "ct":"<b64url ciphertext||tag>"}
```

* `shared = X25519(ephemeralPrivate, hostSealPublic)`;
  `key = HKDF-SHA256(ikm=shared, salt=epk||hostSealPublic, info="cafedesk-seal-v1", L=32)`;
  AES-256-GCM with the 12-byte nonce and AAD `"cafedesk-seal-v1|" + deviceId`.
* Plaintext: `{"kind":"sign_in","email":"…","password":"…","requestId":"…"}` or
  `{"kind":"approve","email":"…","password":"…","purpose":"…","requestId":"…"}`.
* The host refuses a `requestId` it has seen in the last 10 minutes.
* `sign_in` response: `{sessionToken, expiresAt, staff:{staffId, name, role}}`. Accounts that
  must choose a new password are refused with `FORBIDDEN` ("sign in on the POS once first").
  The role must fit the device kind (§3.3).
* `approve` response: `{approvalId, ownerName, expiresAt}` — a single-use owner approval held
  by the host for 5 minutes, usable in one command's `approvalId`.

## 7. LAN API (POS host)

Base `https://<host-lan-address>:47821`. TLS only; the device pins the host certificate by
SHA-256 of its DER (from the pairing code) and accepts no other certificate.

| Method & path | Auth | Body → response |
|---|---|---|
| `GET /v1/health` | none | `{ok, minProtocolVersion, maxProtocolVersion}` |
| `POST /v1/pair` | pairing code | `{protocolVersion, pairingCode, deviceName, platform, appVersion}` → `{deviceId, deviceCredential, role, restaurantId, hostDeviceId, hostEpoch, hostSigningPublicKey, hostSealPublicKey, cloudUrl}` |
| `POST /v1/auth/sealed` | device | `{sealed}` → §6 |
| `POST /v1/auth/sign-out` | device + session | → `{ok}` |
| `GET /v1/snapshot?scope=waiter\|kitchen` | device + session | §7.1 |
| `POST /v1/commands` | device + session | command → result |
| `GET /v1/commands/{id}` | device + session | stored result or 404 |
| `GET /v1/events?epoch=&after=&limit=` | device + session | `{events:[…], latestSequence}` (device audience only) |
| `GET /v1/socket?epoch=&after=` (WebSocket) | device + session | §7.2 |

Pairing codes are single-use, expire after 10 minutes, are bound to a role, and are
rate-limited (5 failed attempts per minute per address). Sign-in is rate-limited the same way
and also by the existing per-account lockout.

### 7.1 Snapshot

```json
{"hostEpoch":1,"cursor":1234,"generatedAt":0,"restaurantName":"…",
 "menu":{"categories":[…],"items":[…]},        // waiter scope
 "tables":[{"tableId","name","capacity","openOrderId","openOrderNo"}],   // waiter
 "orders":[OrderView],                            // open orders (waiter)
 "tickets":[TicketView]}                          // not-ready + recent ready (kitchen)
```

Menu items carry `itemId, categoryId, name, price, available, variants[{variantId,name,price}],
modifiers[{modifierId,name,price}]`.

### 7.2 WebSocket messages

Server → device: `{"t":"hello","hostEpoch":1,"latestSequence":1234}`,
`{"t":"event","event":<Event>}`, `{"t":"snapshot_required"}`, `{"t":"ping"}`.
Device → server: `{"t":"pong"}`. The socket is read-only; commands go through
`POST /v1/commands`.

## 8. Cloud API

Base `https://<worker-host>/v1`. Every route except `health` and `enroll` authenticates a host
or a device credential and derives the restaurant from **that credential's row**; a
restaurant ID in a body or URL is only compared, never trusted.

| Method & path | Auth | Purpose |
|---|---|---|
| `GET /health` | none | `{ok, minProtocolVersion, maxProtocolVersion}` |
| `POST /enroll` | single-use enrollment code (issued by the operator) | `{enrollmentCode, restaurantName, hostDeviceId, hostSigningPublicKey, hostSealPublicKey, appVersion}` → `{restaurantId, hostCredential}` |
| `POST /host/credential/rotate` | host | → `{hostCredential}` (old one stops working) |
| `GET /host/sync-state` | host | `{currentEpoch, epochs:[{epoch, startSequence, nextSequence}]}` |
| `POST /host/epoch` | host | `{epoch, startSequence, reason}` — open a new epoch after a restore; queued commands of older epochs become `QUARANTINED` |
| `POST /host/events` | host | `{hostEpoch, events:[Event]}` (≤ 500 events) → `{ackedThrough}`; 409 `GAP` `{expectedNext}`; 409 `CONTENT_MISMATCH` |
| `GET /host/socket` (WebSocket) | host | relay channel, §8.1 |
| `PUT /host/backups/{backupId}` | host | encrypted archive body; headers `X-Content-SHA256`, `X-Manifest` (b64url JSON) |
| `GET /host/backups`, `GET /host/backups/{backupId}` | host | list / download own backups |
| `POST /device/requests` | device (+ session except `sealed_auth`) | `{kind:"sealed_auth"\|"snapshot"\|"command_lookup", body}` → relayed host response; 503 `HOST_UNREACHABLE`, 504 `HOST_TIMEOUT` |
| `POST /device/commands` | device + session | command → `{commandId, mailboxState, result?}`; waits up to 8 s for the host |
| `GET /device/commands/{commandId}` | device + session | mailbox state and result (own commands only) |
| `GET /device/events?epoch=&after=&limit=` | device + session | device-audience events from the ledger |
| `GET /device/socket` (WebSocket) | device + session | notifications, §8.1 |
| `GET /reports/summary?from=&to=` | owner session or host | report cards + freshness, §8.2 |

### 8.1 Durable Object relay

One Durable Object per restaurant (`idFromName(restaurantId)`), using the WebSocket
hibernation API. It holds:

* the host socket (at most one; a newer authenticated host connection replaces the older);
* device sockets (tagged with device ID);
* the **command mailbox** in Durable Object storage: per `commandId` — body, `bodyHash`,
  device, staff, the session token to forward, `receivedAt`, `mailboxState`
  (`queued` → `delivered` → `answered`, or `expired` / `quarantined`), and the host result.

Mailbox rules:
* Same `commandId` + same `bodyHash` → returns the existing entry; different hash →
  `COMMAND_ID_REUSED`.
* `queued` commands are sent to the host when it connects, oldest first. A command not
  delivered within **30 minutes** of `receivedAt` becomes `expired` and is never delivered.
* Mailbox acceptance (`queued`) is **not** business acceptance. Only a host result with
  `state: accepted` is.
* Results are kept 7 days.

Host socket messages: DO → host `{"t":"command","command":{…},"sessionToken":"…","deviceId":"…"}`,
`{"t":"request","requestId":"…","kind":"…","deviceId":"…","sessionToken":"…"|null,"body":{…}}`;
host → DO `{"t":"result","result":<Result>}`, `{"t":"response","requestId":"…","status":200,"body":{…}}`,
`{"t":"events_available","hostEpoch":1,"latestSequence":1234}`. Pings both ways.

Device socket messages: DO → device `{"t":"events","hostEpoch":1,"latestSequence":1234}`,
`{"t":"command","commandId":"…","mailboxState":"…","result":…}`,
`{"t":"host","connected":true}`.

### 8.2 Cloud reports

`GET /reports/summary` returns the cards of `docs/REPORT_DEFINITIONS.md` computed from the
projection, plus freshness: `{source:{hostDeviceId}, ackedThrough:{hostEpoch, sequence},
lastEventCommittedAt, lastIngestedAt}`. Projections are rebuilt idempotently from the event
ledger (`npm run rebuild-projections`).
