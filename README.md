# CaféDesk Online — connected café POS

CaféDesk Online extends the offline CaféDesk POS (`res-pos`, see `docs/BASELINE.md`) for cafés
that want waiters and the kitchen on their own phones or tablets:

* **POS host (Windows):** the main till. It keeps every offline feature below and is the only
  place where orders are accepted, kitchen tickets are created, bills are finalized and
  receipts are printed. It keeps billing even with no internet.
* **Waiter phones (Android):** take table orders and send them to the kitchen through the host.
* **Kitchen display (Android phone/tablet):** see accepted tickets and mark them preparing /
  ready.
* **Cloud relay (Cloudflare, optional):** reaches the host when a phone is off the café Wi-Fi,
  keeps an off-site copy of accepted sales for owner reports, and stores optional encrypted
  backups. It never finalizes a bill itself.

Phones talk to the host over the café Wi-Fi using TLS with a certificate pinned when the phone
is paired, and fall back to the cloud relay when the Wi-Fi path is down. The scope and rules
are in `CONNECTED_BUILD_SPEC.md`; status is in `docs/PROGRESS.md`.

CaféDesk Online installs **next to** the offline CaféDesk without touching it: different app
ID, Windows program, data folder and database files.

Do not put the database on OneDrive, Dropbox or a network share. It lives in the app's
private data folder.

## Features inherited from offline CaféDesk

* First-run setup (no default accounts), owner recovery code, owner / cashier / kitchen roles
* Email + password sign-in; only an owner creates accounts (Staff → Create account) and a
  new person chooses their own password at first sign-in. The email is a sign-in name only:
  nothing is sent to it and nothing goes online
* Salted Argon2id password hashes, retry delay, inactivity lock, owner password approvals for big discounts,
  voids after KOT, refunds, shift reopen/carry-over and restore
* Menu with categories, variants, add-ons, sold-out toggle, archive; CSV import/export
* Tables (occupancy from open orders), dine-in / takeaway / delivery, durable open orders
* One pricing engine: inclusive / exclusive / no tax, CGST/SGST-style splits, line and bill
  discounts, service and delivery charges, optional rounding — integer paise only
* KOT: only new items per submission, retry-safe, correction tickets, kitchen status board
* Atomic, idempotent checkout; split tender; change; sequential receipt numbers with a
  per-device prefix; immutable bills; COPY reprints
* Partial/full refunds that reverse the original captured amounts
* Shifts with expected vs counted cash; expenses; dashboard and CSV exports
* ESC/POS printing 58/80 mm: Android Bluetooth Classic, Windows installed printers (RAW or
  driver-rendered), LAN TCP 9100; durable print queue with honest sent/failed/unknown states
* Consistent backups (scheduled + manual), validated restore with automatic pre-restore
  backup and rollback
* Separate demo café database

Taxes are **off** until an owner configures them. CaféDesk does not assume your GST
registration or rates, and its reports are operational, not statutory tax reports.

## Quick start (development)

Toolchain on this machine (see `docs/BUILD_AND_RELEASE.md` for details and why):

```powershell
. .\scripts\dev-env.ps1          # puts Flutter, Android SDK and Java on PATH for this shell
flutter pub get
dart run build_runner build      # regenerate Drift code after schema changes
.\scripts\check.ps1              # format check, analyze, all tests
flutter run -d windows           # or: flutter run (Android device)
```

Demo: on first launch choose **Try the demo café**. Demo sign-ins are shown on the lock screen
(owner@demo.test, cashier@demo.test, kitchen@demo.test — password demo1234). The demo uses its own database file; leave it from
Settings.

Builds:

```powershell
.\scripts\build_android.ps1      # dist\CafeDeskOnline-<ver>-android-<debug|release>-signed.apk
.\scripts\build_windows.ps1      # dist\CafeDeskOnline-<ver>-windows-x64-unsigned.zip
```

## Documentation

| Doc | What |
|---|---|
| `CONNECTED_BUILD_SPEC.md` | the connected product's specification / acceptance contract |
| `docs/PROGRESS.md` | connected build status, checks run, assumptions, open items |
| `docs/BASELINE.md` | source repo and commit, identity changes, baseline checks |
| `docs/CONNECTED_ARCHITECTURE.md` | POS host, phones and cloud relay: pieces, flows, outages, retention |
| `docs/PROTOCOL.md` | wire protocol v1: commands, events, restore, LAN and cloud APIs |
| `docs/PAIRING_AND_SECURITY.md` | keys, pairing, sign-in, cloud trust, Windows firewall and Android Wi-Fi setup |
| `docs/CLOUDFLARE_SETUP.md` | cloud relay: local development, the deployed production relay, enrollment codes, rollback |
| `docs/CONNECTED_TEST_CHECKLIST.md` | physical phone/tablet/Wi-Fi checks and pilot steps |
| `docs/OFFLINE_POS_BUILD_SPEC.md` | historical: the offline specification |
| `docs/OFFLINE_PROGRESS.md` | historical: the offline build log |
| `docs/ARCHITECTURE.md` | layers, principles, startup, folder map |
| `docs/DATA_MODEL.md` | tables, constraints, migrations |
| `docs/PRICING.md` | calculation order, tax, discounts, refunds |
| `docs/REPORT_DEFINITIONS.md` | every dashboard metric + hand-calculated fixture |
| `docs/PRINTER_SETUP.md` | printer setup, job states, compatibility matrix |
| `docs/BACKUP_RESTORE.md` | backup format, schedule, restore safety |
| `docs/BUILD_AND_RELEASE.md` | toolchains, builds, signing, clean-machine install |
| `docs/MANUAL_TEST_CHECKLIST.md` | hardware/device acceptance checks |
| `docs/DEPENDENCIES.md` | packages, platform support, licenses |

## Security notes

* Passwords restrict normal use of the app. They do **not** encrypt the database or backups: anyone
  with administrator access to the device, or a backup file, can read the data.
* Backups are not encrypted. Keep copies somewhere you control.
* Card and UPI payments are recorded manually; CaféDesk never stores card numbers or UPI
  credentials and does not verify payments.
* Owner recovery: the one-time recovery code from setup (or a second owner account). There is
  no master password.
* Phones reach the POS only over TLS with a pinned certificate, after owner pairing and a
  personal sign-in; the cloud relay never sees passwords. Details, Windows firewall and Android
  Wi-Fi setup: `docs/PAIRING_AND_SECURITY.md`.
