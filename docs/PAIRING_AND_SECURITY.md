# Pairing and security — CaféDesk Online

What protects the connection between the POS, phones and the cloud, what each side stores,
and how to set up Windows and the café Wi-Fi. Architecture: `docs/CONNECTED_ARCHITECTURE.md`;
wire format: `docs/PROTOCOL.md`.

## 1. In short

* Phones talk to the POS only over **TLS with a pinned certificate**. There is no plain-HTTP
  mode and no "accept any certificate" switch. A phone that sees a different certificate
  refuses to send anything and says so.
* A phone must be **paired** by the owner on the POS (QR code, single use, 10 minutes), and a
  person must **sign in** on it with their own email and password. Both are checked on every
  request, and again every 60 seconds on live connections.
* Passwords typed on a phone are **sealed to the POS's key** before they leave the phone; the
  cloud relay cannot read them.
* The POS checks every command itself (role, device kind, prices, availability, approvals).
  A waiter phone cannot take payment, refund, discount without an owner, or touch settings.
* Nothing secret is in Git or in the app: there is no universal password, admin token or
  shared key. Each POS makes its own keys on first use.

## 2. Keys and secrets

| Secret | Made by | Stored | Never |
|---|---|---|---|
| TLS certificate (EC P-256, self-signed) + private key | POS, when phone connections are first turned on | Private key in Windows secure storage; certificate (public) in the POS database | Leaves the PC |
| Ed25519 signing key (staff session tokens) | POS | Windows secure storage; public key given to phones and the cloud | Leaves the PC |
| X25519 seal key (passwords from phones) | POS | Windows secure storage; public key given to phones | Leaves the PC |
| Device credential `cdd1.<deviceId>.<secret>` | POS at pairing | The phone's secure storage; POS and cloud keep only its SHA-256 | Stored in plain text anywhere but the phone |
| Staff session token `cds1.…` (12 hours) | POS at sign-in | The phone's secure storage; POS keeps the session row | Accepted after sign-out, removal or a restore |
| Cloud host credential `cdh1.…` | Cloud at enrollment | Windows secure storage; cloud keeps only its hash | Shown in the app |
| Enrollment code | Operator CLI (`npm run issue-enrollment-code`) | Cloud keeps only its hash; single use, expires | Built into the app |

Staff passwords are hashed (salted) in the POS database exactly as in the offline app and are
never in events, the cloud, or on phones.

## 3. Pairing a phone

1. Owner: **Settings → Connected devices**, turn on *Let paired phones connect to this POS*,
   then *Pair a phone* and choose **Waiter phone** or **Kitchen display**.
2. The POS shows a QR code (and the same text to copy) holding: restaurant ID and name, POS
   device ID, the PC's LAN addresses and port, the **SHA-256 of the POS certificate**, a random
   pairing code, the role and the expiry time. It expires after **10 minutes** and works
   **once**.
3. Phone: *Use as a waiter phone or kitchen display* → scan (or paste) → name the phone.
   The phone connects, checks the certificate hash from the QR, and only then sends the code.
   The POS answers with the device credential and its public keys.
4. Failed pairing attempts are limited to **5 per minute per address**; so are sign-ins.

Removing a phone (*Connected devices → Remove*) disconnects it on the POS at once and ends its
sessions. If a cloud is connected, the cloud stops it as soon as the POS uploads the removal.
**Lost or stolen phone: remove it at once.**

*Reset device connections* makes new keys and a new certificate: every phone must be paired
again and the cloud connected again. Sales are not affected. Use it if the PC was replaced,
the keys were lost, or you are unsure who has paired phones.

## 4. Signing in on a phone

* Staff sign in with their own CaféDesk email and password (owner-created accounts, as on the
  POS). The phone seals the password to the POS's X25519 key (HKDF-SHA256 + AES-256-GCM, with
  a 10-minute replay window); only the POS can open it.
* The role must fit the device: waiter phones accept waiters, cashiers and owners; kitchen
  displays accept kitchen staff, cashiers and owners. Accounts that must change their password
  sign in on the POS first.
* Disabling a person or changing their role on the POS ends their phone sessions immediately
  (and in the cloud when the change is uploaded).
* Owner approvals asked for on a phone (for example cancelling an item the kitchen already
  has) are sealed the same way and expire after 5 minutes.

## 5. The cloud relay (optional)

* Enrolled once with a single-use code from whoever runs the cloud. The cloud **never** lets a
  second POS take over an existing restaurant.
* The cloud keeps credential **hashes**, the device list, revoked sessions, the event ledger and
  report projections. It can read order and sales data (that is what reports are made of). It
  cannot read passwords or sign sessions.
* Every request is checked for the right restaurant: a POS or phone of one restaurant cannot see
  or address another's data (tested in `cloud/test/isolation.test.ts`).
* Cloud addresses must be `https://` (only a local development Worker on `127.0.0.1`/`localhost`
  may use `http://`). No Cloudflare administrator credentials are in the app.
* Deployed 2026-10-11 at `https://cafedesk-online.growlineecommerce.workers.dev`; plain `http://`
  is refused there. Details and operation: `docs/CLOUDFLARE_SETUP.md` §8.

## 6. After restoring a backup

Restoring keeps **this PC's** pairings (a phone removed after the backup stays removed), ends
every staff session, and keeps phones and the cloud disconnected until the owner chooses
*Reconnect devices* (`PROTOCOL.md` §5.4). If the backup is restored on a different PC, its keys
are not there: use *Reset device connections* and pair the phones again.

## 7. Windows setup for the POS PC

* **Keep CaféDesk Online open** (it may be minimised). Closing it disconnects every phone.
* **Firewall:** the first time phone connections are turned on, Windows asks whether to allow
  CaféDesk Online. Allow it on **Private networks**. The café Wi-Fi or Ethernet connection must
  then be a *Private* network: Settings → Network & internet → (Wi-Fi or Ethernet) → your
  network → *Network profile type: Private*. On a Public profile, phones cannot connect.
  If the prompt was dismissed, an administrator can add the rule (PowerShell as administrator;
  change the path to the folder CaféDesk Online was unzipped to):

  ```powershell
  New-NetFirewallRule -DisplayName "CaféDesk Online phones" -Direction Inbound -Action Allow `
    -Protocol TCP -LocalPort 47821 -Profile Private `
    -Program "C:\Program Files\CafeDesk Online\cafedesk_online.exe"
  ```

  Use the port shown in Connected devices if you changed it.
* **Fixed address:** phones remember the PC's address from pairing. Reserve the PC's IP address
  in the router (DHCP reservation) so it does not change; otherwise phones fall back to the
  cloud (if set up) or need pairing again.
* **No sleep:** Settings → System → Power → *When plugged in, put my device to sleep after:
  Never*.
* **Unsigned build:** Smart App Control or SmartScreen may block an unsigned
  `cafedesk_online.exe`; sign it with the business's code-signing certificate before
  installing on café PCs (`docs/BUILD_AND_RELEASE.md`).

## 8. Android setup for phones and kitchen tablets

* Same Wi-Fi as the POS PC. **Guest networks often isolate devices from each other** ("client /
  AP isolation") — phones then cannot reach the POS. Use the staff network or turn isolation off.
* VPN or "data saver" apps on the phone can block local connections; turn them off for the café.
* On mobile data, phones can only reach the POS through the cloud relay (if set up).
* The camera is used only to scan the pairing QR; without it, paste the pairing text.
* Kitchen displays: tap the *Keep the screen on* button on the board; keep the volume up; leave
  the app open.
* Phones keep unsent orders through app restarts; nothing is lost if the app is closed.

## 9. Known limits (unchanged from the offline app unless noted)

* The POS database and local backups are **not encrypted**. Anyone with administrator access to
  the PC, or a backup file, can read the sales data. Protect the PC and the backup folder.
* The cloud operator can read the restaurant's order and sales data in the cloud.
* No encrypted cloud backup (owner decision, 2026-10-11).
* Not yet verified on physical phones, tablets, the Windows firewall prompt or real café
  networks — see `docs/CONNECTED_TEST_CHECKLIST.md`.
