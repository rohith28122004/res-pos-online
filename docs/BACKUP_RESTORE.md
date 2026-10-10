# Backup and restore

## What a backup is

A `.cdbackup` file is a ZIP containing exactly two entries:

* `cafedesk.sqlite` — a consistent snapshot made with SQLite `VACUUM INTO` while the app runs
  (includes everything committed in the WAL; no `-wal`/`-shm` or lock files are copied)
* `manifest.json` — format version, app version, schema version, created-at (UTC),
  installation id, receipt prefix, restaurant name, currency, bill count, SHA-256 of the
  database, platform, reason (`manual`, `scheduled`, `pre-restore`), `"encrypted": false`

**Backups are not encrypted.** Anyone with the file can open the sales data. Keep copies on
storage you control. Passwords protect the app, not the files.

## When backups happen

* **Manual:** Settings → Backup and restore → Back up now.
* **Scheduled:** every N hours (default 24) while CaféDesk is open, checked every 15 minutes,
  plus a catch-up shortly after launch if one is overdue. Not in demo mode.
* **Pre-restore:** automatically, before any restore replaces data.
* Retention keeps the newest N scheduled backups (default 14); manual and pre-restore backups
  are never deleted automatically.

Default folder: Windows `%APPDATA%\com.cafedesk\cafedesk\backups`; Android
`Android/data/com.cafedesk.cafedesk/files/backups` (reachable over USB file transfer, removed
if the app is uninstalled). On Windows an owner can choose another local folder (not OneDrive,
Dropbox or a network share). **Save a copy elsewhere** (USB drive, another PC) with "Save a copy"
— a backup on the same device does not survive the device failing.

## Restore

Settings → Backup and restore → Restore from a file… (or pick one from the list). Owner only.

1. The archive is opened and checked before anything changes:
   * only the two expected entries; any absolute path, drive letter, backslash or `..` segment
     is rejected (path traversal)
   * manifest format and versions: backups from a newer app/schema are refused
   * currency must be INR
   * SHA-256 of the database must match the manifest
   * the staged database passes `PRAGMA integrity_check` and `PRAGMA foreign_key_check`, and
     its `user_version` matches the manifest
2. A summary is shown (restaurant, backup date, bill count, source platform). Restore
   **replaces** all data — it is not a merge.
3. The owner re-enters their password (fresh approval).
4. A **pre-restore backup** of the current data is created.
5. The staged copy is adjusted:
   * queued/sending print jobs become **held** (never auto-printed after a restore)
   * **continuation restore** (same installation id): every sequence (receipt, refund, order,
     KOT) is set to `max(backup, current)` so numbers already issued after the backup are
     never reused
   * a different installation keeps the backup's identity and prefix, unless "use a new
     receipt prefix on this device" is ticked (recommended when the other device keeps billing)
   * a `backup.restored` audit event is written into the restored data
6. The database is closed, current files are renamed aside, the staged copy is moved in and
   reopened (migrations run if the backup is from an older schema). If anything fails the
   original files are moved back and reopened, and the error says the previous data was put back.
7. Everyone signs in again. Review held print jobs in Print jobs.

## Moving to another device

Back up on the old device → copy the file → restore on the new one. Android ↔ Windows works
(the SQLite format is portable). Then stop using the old device for billing, or give the new
device a new receipt prefix. There is no live sync between devices.

## Tests

`test/database/backup_restore_test.dart` covers: archive contents and manifest, inspection
summary, corrupt archive, tampered database (checksum), future schema, traversal entries,
permission checks, continuation restore (sequence continuity, held jobs, audit event, usable
afterwards), rollback on a failed reopen, stale approval, and a cross-installation restore with
a new prefix.
