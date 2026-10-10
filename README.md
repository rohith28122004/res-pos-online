# CaféDesk — offline café POS

Offline billing for cafés and small restaurants: orders, kitchen tickets (KOT), receipts,
cash/UPI/card payments, refunds, expenses, shifts, backups and a sales dashboard. One Flutter
codebase for **Android** (phones/tablets) and **Windows** desktop. **No internet, no cloud
account, no subscription.** "CaféDesk" is a working name; restaurant branding is configurable.

> **Each device is a separate installation.** An Android tablet and a Windows PC running
> CaféDesk do **not** share orders or sales — there is no live sync. Data moves between devices
> only by restoring a backup, which **replaces** the receiving device's data.

Do not put the database on OneDrive, Dropbox or a network share. It lives in the app's
private data folder.

## Features

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
.\scripts\build_android.ps1      # dist\CafeDesk-<ver>-android-<debug|release>-signed.apk
.\scripts\build_windows.ps1      # dist\CafeDesk-<ver>-windows-x64-unsigned.zip
```

## Documentation

| Doc | What |
|---|---|
| `OFFLINE_POS_BUILD_SPEC.md` | the specification / acceptance contract |
| `docs/PROGRESS.md` | status, checks run, assumptions, open items |
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
