# CaféDesk Online — connected architecture

How the Windows POS, waiter phones, kitchen displays and the optional cloud relay fit
together. The wire format is `docs/PROTOCOL.md`; keys, pairing and network setup are in
`docs/PAIRING_AND_SECURITY.md`; the offline app's layers are in `docs/ARCHITECTURE.md`.

## 1. The one rule

**The POS decides.** Every order, kitchen ticket, bill, refund and receipt number is created
by the POS host (the Windows PC running CaféDesk Online in POS mode), in its own SQLite
database, inside one transaction. Phones only *ask* (commands) and *show* (a cached copy).
The cloud only *relays* commands to that same POS and keeps a *copy* of what the POS has
already decided, for reports. Nothing else can accept an order or finish a bill, so a lost
connection can delay an order but never invent or duplicate one.

```
 Waiter phone ─┐   café Wi-Fi: HTTPS + WebSocket,          ┌─────────────────────────────┐
 Kitchen tab ──┼── pinned self-signed certificate ────────▶│ POS host (Windows)           │
               │                                           │  LanServer  ─┐               │
               │   anywhere: HTTPS / WSS                   │  HostApi ────┼─ dispatcher ─▶ SQLite (truth)
               └──▶ Cloud relay (Cloudflare, optional) ◀───│  CloudConnector             │   + event outbox
                    Worker · RestaurantHub DO · D1 · R2    └─────────────────────────────┘
                    relays commands, stores the event copy,           │
                    serves report projections                   receipt / KOT printers
```

## 2. Pieces and where they live

### POS host (Windows, `lib/core/host/`, `lib/core/sync/host_outbox.dart`)

| Piece | File | Job |
|---|---|---|
| `HostConnectivity` | `host_connectivity.dart` | Starts/stops the LAN server and cloud connector with the app; `HostStatus` for the top-bar chip; refuses to start after a restore until the owner reconnects |
| `HostIdentityService` | `host_identity.dart` | Restaurant ID, host device ID, epoch, certificate; LAN on/off; reset connections; reconnect after restore |
| `HostKeys` | `host_keys.dart` | TLS certificate + key, Ed25519 signing key, X25519 seal key, cloud credential — private parts only in Windows secure storage |
| `LanServer` | `lan_server.dart` | HTTPS routes and the live WebSocket; pushes outbox events to phones |
| `HostApi` | `host_api.dart` | Everything both transports share: authentication, pairing, sealed sign-in, snapshots, events, command handling, rate limits |
| `CommandDispatcher` | `command_dispatcher.dart` | Turns a validated command into normal service calls (orders, kitchen) inside one transaction; stores the result with the command ID and body hash (idempotency) |
| `HostSessions` | `session_service.dart` | Staff sessions on phones: signed tokens checked against live rows |
| `HostOutbox` | `../sync/host_outbox.dart` | Every change writes an event in the same transaction, numbered from one counter; pruning |
| `CloudConnector` | `cloud_connector.dart` | Enrollment, history backfill, ordered upload with acknowledgements, the relay socket |

### Phone (waiter / kitchen, `lib/core/sync/`, `lib/features/waiter|kitchen|devices/`)

| Piece | File | Job |
|---|---|---|
| `ClientDatabase` | `client_database.dart` | The phone's own SQLite: link, session, pending commands, drafts, cached snapshot, alarms. Never the POS database |
| `DeviceSync` | `device_sync.dart` | Pairing, sign-in, snapshot + cursor + live events, the durable command queue, link status |
| `LanRoute` / `CloudRoute` | `host_route.dart`, `cloud_route.dart` | The two ways to reach the same POS; LAN first |
| `DeviceRuntime` | `lib/app/device_runtime.dart` | Opens the phone database and engine in device mode |

### Cloud (`cloud/`; deployed 2026-10-11 as `cafedesk-online` — `CLOUDFLARE_SETUP.md` §8)

| Piece | Where | Job |
|---|---|---|
| Worker | `cloud/src/index.ts`, `routes/` | Enrollment, authentication, validation, ingest, reports, private storage |
| `RestaurantHub` Durable Object | `cloud/src/restaurant_hub/` | One per restaurant: host and device sockets, the command mailbox (30-minute expiry, quarantine on a new epoch), request relay |
| D1 | `cloud/migrations/` | Restaurants, hashed credentials, device registry, epochs, the immutable event ledger, report projections |
| R2 | private bucket | Menu images; backup routes exist but the POS does not upload backups (owner decision) |

## 3. Main flows

### Waiter order over the café Wi-Fi
1. The waiter builds a draft (saved on the phone) and taps Send. The phone writes a
   pending command with a new command ID and the exact body, then sends it.
2. The POS checks the device credential, the staff session, the role, the payload, prices and
   availability, then places the order, creates one kitchen ticket and one KOT print job — and
   stores the result under the command ID — in one transaction, with outbox events.
3. The phone shows *Accepted by the POS* only when it gets that result. If the answer is lost,
   it asks for the stored result by command ID instead of sending again.
4. The kitchen display receives the `ticket.updated` event on its live socket and sounds once.

### The same order when the phone cannot reach the POS directly
The phone sends the **same command ID and body** to the cloud. The cloud stores it in the
restaurant's mailbox and hands it to the POS over the POS's own outbound socket; the POS
handles it exactly as above and the result travels back. If the POS is offline, the command
waits (shown as *Waiting in the cloud*); it expires after 30 minutes and is never delivered
late. Sending it over the LAN later returns the stored result — no second order.

### Reports in the cloud
The POS uploads its outbox in order; the cloud acknowledges only after the batch is stored,
skips identical duplicates and refuses changed content or gaps. Report projections are SQL over
the ledger, so they can be rebuilt at any time and say how fresh they are.

### Restore
See `PROTOCOL.md` §5.4: a new epoch, phones and cloud held off until the owner reconnects,
the restored history re-sent, and report rows the restored POS no longer has removed.

## 4. When something is down

| Situation | Waiters / kitchen | POS |
|---|---|---|
| Internet down, Wi-Fi fine | Everything works over the LAN | Normal; cloud copy catches up later |
| Phone off the Wi-Fi (cloud set up, POS online) | Works through the cloud | Normal |
| Phone off the Wi-Fi, no cloud | Orders saved on the phone, sent when back | Normal |
| POS app closed / PC off | Orders saved on the phone (or waiting in the cloud ≤ 30 min); banner says so | — |
| Phone app closed with unsent orders | Kept; sent once when the app opens again (or held for review after 30 minutes) | — |
| POS restored from a backup | Old unsent orders held for the waiter to check | Phones and cloud wait for *Reconnect devices* |

## 5. Storage and retention

| Data | Where | Kept |
|---|---|---|
| Orders, bills, refunds, shifts… | POS database | Forever (as in the offline app) |
| Outbox events | POS database | 7 days; with a cloud, current-epoch events until acknowledged |
| Command results | POS database | Forever (so lookups always work) |
| Phone cache, drafts, queue | Phone database | Until unpaired |
| Mailbox commands | Cloud DO | 30 minutes undelivered, then expired |
| Event ledger, projections | Cloud D1 | Not pruned yet (see `CLOUDFLARE_SETUP.md`) |

## 6. Not in this version

* One POS host per restaurant; no second till sharing the database.
* An Android device cannot be the POS host for phones (it stays a standalone till).
* No billing in the cloud and no cloud dashboard app; cloud reports are an API.
* No encrypted cloud backup (owner decision, 2026-10-11); backups stay on the PC.
* Phones find the POS at the address saved when pairing (no automatic discovery).
