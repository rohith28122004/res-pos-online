/// Consistent backups and validated, recoverable restores.
///
/// Backups use SQLite's `VACUUM INTO`, which writes a transactionally
/// consistent copy of the live database (WAL included) without stopping the
/// app. Archives contain only `manifest.json` and `cafedesk.sqlite` — no lock
/// files, sockets or WAL files. Backups are NOT encrypted; anyone with the
/// file can read the sales data.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

import '../app_info.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../printing/queue/print_job_writer.dart';
import '../security/permissions.dart';
import '../service_context.dart';

const backupExtension = 'cdbackup';
const _manifestName = 'manifest.json';
const _dbName = 'cafedesk.sqlite';
const _maxArchiveBytes = 1024 * 1024 * 1024; // 1 GiB

class BackupManifest {
  const BackupManifest({
    required this.formatVersion,
    required this.appVersion,
    required this.schemaVersion,
    required this.createdAtUtc,
    required this.installationId,
    required this.receiptPrefix,
    required this.restaurantName,
    required this.currencyCode,
    required this.billCount,
    required this.sha256,
    required this.platform,
    required this.reason,
    required this.isDemo,
  });

  final int formatVersion;
  final String appVersion;
  final int schemaVersion;
  final DateTime createdAtUtc;
  final String installationId;
  final String receiptPrefix;
  final String restaurantName;
  final String currencyCode;
  final int billCount;
  final String sha256;
  final String platform;
  final String reason;
  final bool isDemo;

  Map<String, Object?> toJson() => {
    'format': 'cafedesk-backup',
    'formatVersion': formatVersion,
    'appVersion': appVersion,
    'schemaVersion': schemaVersion,
    'createdAtUtc': createdAtUtc.toIso8601String(),
    'installationId': installationId,
    'receiptPrefix': receiptPrefix,
    'restaurantName': restaurantName,
    'currencyCode': currencyCode,
    'billCount': billCount,
    'sha256': sha256,
    'platform': platform,
    'reason': reason,
    'isDemo': isDemo,
    'encrypted': false,
  };

  static BackupManifest fromJson(Map<String, Object?> j) {
    if (j['format'] != 'cafedesk-backup') throw const BackupException('This is not a CaféDesk backup');
    try {
      return BackupManifest(
        formatVersion: j['formatVersion']! as int,
        appVersion: j['appVersion']! as String,
        schemaVersion: j['schemaVersion']! as int,
        createdAtUtc: DateTime.parse(j['createdAtUtc']! as String).toUtc(),
        installationId: j['installationId']! as String,
        receiptPrefix: j['receiptPrefix']! as String,
        restaurantName: j['restaurantName']! as String,
        currencyCode: j['currencyCode']! as String,
        billCount: j['billCount']! as int,
        sha256: j['sha256']! as String,
        platform: (j['platform'] as String?) ?? 'unknown',
        reason: (j['reason'] as String?) ?? 'manual',
        isDemo: (j['isDemo'] as bool?) ?? false,
      );
    } on Object {
      throw const BackupException('The backup manifest is damaged');
    }
  }
}

class BackupFile {
  const BackupFile({required this.path, required this.manifest, required this.sizeBytes});
  final String path;
  final BackupManifest manifest;
  final int sizeBytes;
}

/// A backup that passed every check and is staged, ready to swap in.
class BackupInspection {
  const BackupInspection({
    required this.sourcePath,
    required this.manifest,
    required this.stagedDbPath,
    required this.billCount,
    required this.restaurantName,
    required this.sameInstallation,
    required this.pendingPrintJobs,
  });

  final String sourcePath;
  final BackupManifest manifest;
  final String stagedDbPath;
  final int billCount;
  final String restaurantName;

  /// True when the backup came from this installation (a continuation).
  final bool sameInstallation;
  final int pendingPrintJobs;
}

/// Owns the live database connection so restore can close, swap and reopen.
abstract class DatabaseHost {
  File get databaseFile;
  AppDatabase get database;
  Future<void> closeDatabase();
  Future<AppDatabase> reopenDatabase();
}

class BackupService {
  BackupService(this.ctx, {required this.databaseFile, required this.defaultBackupDir, required this.workDir});

  final ServiceContext ctx;
  final File databaseFile;
  final Directory defaultBackupDir;

  /// Scratch space for staging (inside the app data directory).
  final Directory workDir;

  AppDatabase get _db => ctx.db;

  Future<Directory> backupDirectory() async {
    final s = await ctx.settings();
    final dir = s.backupDirectory == null ? defaultBackupDir : Directory(s.backupDirectory!);
    await dir.create(recursive: true);
    return dir;
  }

  /// Creates a consistent backup archive. [actor] is null for scheduled runs.
  Future<BackupFile> createBackup({Actor? actor, String reason = 'manual', Directory? destination}) async {
    if (actor != null) actor.require(Permission.backup);
    final dir = destination ?? await backupDirectory();
    await dir.create(recursive: true);
    await workDir.create(recursive: true);
    final now = ctx.now();
    final stamp = now.toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    final snapshot = File(p.join(workDir.path, 'snapshot-$stamp-${ctx.ids.newId()}.sqlite'));
    try {
      await _db.customStatement('VACUUM INTO ?', [snapshot.path]);
      final meta = await _inIsolate(_readSnapshot, snapshot.path);
      final dbBytes = await snapshot.readAsBytes();
      final digest = sha256.convert(dbBytes).toString();
      final installation = await ctx.installation();
      final manifest = BackupManifest(
        formatVersion: AppInfo.backupFormatVersion,
        appVersion: AppInfo.version,
        schemaVersion: meta.schemaVersion,
        createdAtUtc: now,
        installationId: installation.installationId,
        receiptPrefix: installation.receiptPrefix,
        restaurantName: meta.restaurantName,
        currencyCode: meta.currencyCode,
        billCount: meta.billCount,
        sha256: digest,
        platform: Platform.operatingSystem,
        reason: reason,
        isDemo: installation.isDemo,
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile.bytes(_manifestName, utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest.toJson()))),
        )
        ..addFile(ArchiveFile.bytes(_dbName, dbBytes));
      final zipped = ZipEncoder().encodeBytes(archive);
      final safeName = installation.isDemo ? 'demo' : installation.receiptPrefix.toLowerCase();
      final target = File(p.join(dir.path, 'cafedesk-$safeName-$stamp-$reason.$backupExtension'));
      final partial = File('${target.path}.partial');
      await partial.writeAsBytes(zipped, flush: true);
      await partial.rename(target.path);

      if (destination == null) {
        await (_db.update(
          _db.restaurantSettings,
        )).write(RestaurantSettingsCompanion(lastBackupAt: Value(now.millisecondsSinceEpoch)));
        await _applyRetention(dir);
      }
      await ctx.audit(
        actor,
        'backup.created',
        details: {'reason': reason, 'file': p.basename(target.path), 'bills': meta.billCount},
      );
      return BackupFile(path: target.path, manifest: manifest, sizeBytes: zipped.length);
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  Future<void> _applyRetention(Directory dir) async {
    final keep = (await ctx.settings()).backupRetention;
    final files = await listBackups(dir: dir);
    final scheduled = files.where((f) => f.manifest.reason == 'scheduled').toList();
    for (final old in scheduled.skip(keep)) {
      try {
        await File(old.path).delete();
      } on FileSystemException {
        // A locked or already-removed file is not worth failing a backup for.
      }
    }
  }

  /// Backups in [dir] (default: configured directory), newest first.
  Future<List<BackupFile>> listBackups({Directory? dir}) async {
    final d = dir ?? await backupDirectory();
    if (!await d.exists()) return const [];
    final out = <BackupFile>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.$backupExtension')) continue;
      try {
        final bytes = await e.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes);
        final m = archive.findFile(_manifestName);
        if (m == null) continue;
        final manifest = BackupManifest.fromJson((jsonDecode(utf8.decode(m.content)) as Map).cast<String, Object?>());
        out.add(BackupFile(path: e.path, manifest: manifest, sizeBytes: bytes.length));
      } on Object {
        continue;
      }
    }
    out.sort((a, b) => b.manifest.createdAtUtc.compareTo(a.manifest.createdAtUtc));
    return out;
  }

  /// True if a scheduled backup is due (interval elapsed or never run).
  Future<bool> isBackupDue() async {
    final s = await ctx.settings();
    if (s.lastBackupAt == null) return true;
    final due = s.lastBackupAt! + Duration(hours: s.backupIntervalHours).inMilliseconds;
    return ctx.nowMs() >= due;
  }

  /// Validates an archive completely and stages its database for restore.
  /// Nothing about the live data changes here.
  Future<BackupInspection> inspect(Actor actor, Uint8List archiveBytes, {String sourcePath = ''}) async {
    actor.require(Permission.restore);
    if (archiveBytes.length > _maxArchiveBytes) throw const BackupException('The backup file is too large');
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    } on Object {
      throw const BackupException('The file is not a valid CaféDesk backup (cannot open the archive)');
    }
    for (final f in archive.files) {
      if (!isSafeArchiveEntry(f.name)) throw BackupException('The backup contains an unsafe path: "${f.name}"');
      if (f.isFile && f.name != _manifestName && f.name != _dbName) {
        throw BackupException('The backup contains an unexpected file: "${f.name}"');
      }
    }
    final mFile = archive.findFile(_manifestName);
    final dbFile = archive.findFile(_dbName);
    if (mFile == null || dbFile == null) throw const BackupException('The backup is incomplete');
    final BackupManifest manifest;
    try {
      manifest = BackupManifest.fromJson((jsonDecode(utf8.decode(mFile.content)) as Map).cast<String, Object?>());
    } on BackupException {
      rethrow;
    } on Object {
      throw const BackupException('The backup manifest is damaged');
    }
    if (manifest.formatVersion > AppInfo.backupFormatVersion) {
      throw const BackupException('This backup was made by a newer CaféDesk. Update the app first.');
    }
    if (manifest.schemaVersion > AppDatabase.latestSchemaVersion) {
      throw BackupException(
        'This backup uses database version ${manifest.schemaVersion}; this app supports up to '
        '${AppDatabase.latestSchemaVersion}. Update the app first.',
      );
    }
    if (manifest.currencyCode != 'INR') {
      throw BackupException('This backup uses ${manifest.currencyCode}, which this version does not support');
    }
    final dbBytes = Uint8List.fromList(dbFile.content);
    if (sha256.convert(dbBytes).toString() != manifest.sha256) {
      throw const BackupException('The backup is corrupted (checksum mismatch)');
    }
    await workDir.create(recursive: true);
    final staged = File(p.join(workDir.path, 'restore-${ctx.ids.newId()}.sqlite'));
    await staged.writeAsBytes(dbBytes, flush: true);
    try {
      final meta = await _inIsolate(_verifyStaged, staged.path);
      if (meta.schemaVersion != manifest.schemaVersion) {
        throw const BackupException('The backup database does not match its manifest');
      }
      final installation = await ctx.installation();
      return BackupInspection(
        sourcePath: sourcePath,
        manifest: manifest,
        stagedDbPath: staged.path,
        billCount: meta.billCount,
        restaurantName: meta.restaurantName,
        sameInstallation: meta.installationId == installation.installationId,
        pendingPrintJobs: meta.pendingPrintJobs,
      );
    } on Object {
      if (await staged.exists()) await staged.delete();
      rethrow;
    }
  }

  Future<void> discardInspection(BackupInspection inspection) async {
    final f = File(inspection.stagedDbPath);
    if (await f.exists()) await f.delete();
  }

  /// Replaces the live database with a staged backup.
  ///
  /// 1. owner + fresh password approval, 2. pre-restore backup of current data,
  /// 3. adjust the staged copy (hold print jobs, keep receipt numbers moving
  /// forward, optional new prefix), 4. close → swap → reopen, 5. roll back
  /// to the previous file if anything fails.
  Future<RestoreOutcome> restore(
    Actor actor,
    BackupInspection inspection, {
    required OwnerApproval approval,
    required DatabaseHost host,
    String? newReceiptPrefix,
  }) async {
    actor.require(Permission.restore);
    await ctx.verifyApproval(approval, 'restore a backup');
    final staged = File(inspection.stagedDbPath);
    if (!await staged.exists()) throw const BackupException('The staged backup is gone. Choose the file again.');

    final preRestore = await createBackup(actor: actor, reason: 'pre-restore');
    final live = await _liveCounters();
    final installation = await ctx.installation();
    // Small, fast edits on the staged file; restore is a modal operation.
    _prepareStaged(
      staged.path,
      liveSequences: inspection.sameInstallation ? live : const {},
      newPrefix: newReceiptPrefix,
      auditId: ctx.ids.newId(),
      nowMs: ctx.nowMs(),
      actorId: actor.staffId,
      actorName: actor.name,
      approvedBy: approval.ownerId,
      details: jsonEncode({
        'backupCreatedAt': inspection.manifest.createdAtUtc.toIso8601String(),
        'backupInstallationId': inspection.manifest.installationId,
        'previousInstallationId': installation.installationId,
        'preRestoreBackup': p.basename(preRestore.path),
        'newReceiptPrefix': newReceiptPrefix,
      }),
    );

    final dbPath = host.databaseFile.path;
    final aside = File('$dbPath.before-restore');
    await host.closeDatabase();
    final moved = <(File, File)>[];
    try {
      if (await aside.exists()) await aside.delete();
      for (final suffix in ['', '-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) {
          final dest = File('${aside.path}$suffix');
          if (await dest.exists()) await dest.delete();
          await f.rename(dest.path);
          moved.add((dest, f));
        }
      }
      await staged.copy(dbPath);
      final reopened = await host.reopenDatabase();
      // Opening runs migrations; prove the restored data is readable.
      await reopened.select(reopened.restaurantSettings).getSingle();
      await staged.delete();
      for (final (dest, _) in moved) {
        if (await dest.exists()) await dest.delete();
      }
      return RestoreOutcome(preRestoreBackupPath: preRestore.path, billCount: inspection.billCount);
    } on Object catch (e) {
      // Roll back to the untouched previous files.
      try {
        await host.closeDatabase();
      } on Object {
        // Already closed.
      }
      final broken = File(dbPath);
      if (await broken.exists()) await broken.delete();
      for (final suffix in ['-wal', '-shm']) {
        final f = File('$dbPath$suffix');
        if (await f.exists()) await f.delete();
      }
      for (final (dest, original) in moved) {
        await dest.rename(original.path);
      }
      await host.reopenDatabase();
      throw BackupException('Restore failed and your previous data was put back. ($e)');
    }
  }

  Future<Map<String, int>> _liveCounters() async {
    final rows = await _db.select(_db.sequences).get();
    return {for (final r in rows) r.name: r.nextValue};
  }
}

class RestoreOutcome {
  const RestoreOutcome({required this.preRestoreBackupPath, required this.billCount});
  final String preRestoreBackupPath;
  final int billCount;
}

/// Runs [fn] on a fresh isolate. A top-level helper so the closure captures
/// only [path] (never a service holding the live database connection).
Future<R> _inIsolate<R>(R Function(String) fn, String path) => Isolate.run(() => fn(path));

/// Rejects absolute paths, drive letters, backslashes and `..` segments.
bool isSafeArchiveEntry(String name) {
  if (name.isEmpty || name.length > 200) return false;
  if (name.startsWith('/') || name.startsWith('\\') || name.contains('\\')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(name)) return false;
  if (name.contains('\u0000')) return false;
  return !name.split('/').any((seg) => seg == '..' || seg == '.');
}

class _SnapshotMeta {
  const _SnapshotMeta({
    required this.schemaVersion,
    required this.billCount,
    required this.restaurantName,
    required this.currencyCode,
    required this.installationId,
    required this.pendingPrintJobs,
  });
  final int schemaVersion;
  final int billCount;
  final String restaurantName;
  final String currencyCode;
  final String installationId;
  final int pendingPrintJobs;
}

_SnapshotMeta _readSnapshot(String path) {
  final db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  try {
    return _meta(db);
  } finally {
    db.close();
  }
}

_SnapshotMeta _meta(sql.Database db) {
  final version = db.select('PRAGMA user_version').first.columnAt(0) as int;
  final bills = db.select('SELECT COUNT(*) FROM bills').first.columnAt(0) as int;
  final settings = db.select('SELECT name, currency_code FROM restaurant_settings LIMIT 1');
  final inst = db.select('SELECT installation_id FROM installation LIMIT 1');
  if (settings.isEmpty || inst.isEmpty) throw const BackupException('The backup has no restaurant setup');
  final pending =
      db
              .select("SELECT COUNT(*) FROM print_jobs WHERE state IN ('queued','sending','unknown','held')")
              .first
              .columnAt(0)
          as int;
  return _SnapshotMeta(
    schemaVersion: version,
    billCount: bills,
    restaurantName: settings.first['name'] as String,
    currencyCode: settings.first['currency_code'] as String,
    installationId: inst.first['installation_id'] as String,
    pendingPrintJobs: pending,
  );
}

_SnapshotMeta _verifyStaged(String path) {
  final sql.Database db;
  try {
    db = sql.sqlite3.open(path, mode: sql.OpenMode.readOnly);
  } on Object {
    throw const BackupException('The backup database cannot be opened');
  }
  try {
    final check = db.select('PRAGMA integrity_check');
    final ok = check.length == 1 && check.first.columnAt(0) == 'ok';
    if (!ok) throw const BackupException('The backup database failed its integrity check');
    final fk = db.select('PRAGMA foreign_key_check');
    if (fk.isNotEmpty) throw const BackupException('The backup database has broken references');
    return _meta(db);
  } on BackupException {
    rethrow;
  } on Object catch (e) {
    throw BackupException('The backup database is not usable ($e)');
  } finally {
    db.close();
  }
}

void _prepareStaged(
  String path, {
  required Map<String, int> liveSequences,
  required String? newPrefix,
  required String auditId,
  required int nowMs,
  required String actorId,
  required String actorName,
  required String approvedBy,
  required String details,
}) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute('BEGIN');
    // Historical jobs are never sent automatically after a restore.
    db.execute(
      "UPDATE print_jobs SET state = '${PrintJobState.held}', updated_at = ? WHERE state IN ('queued','sending')",
      [nowMs],
    );
    // Continuation restore: never reissue receipt/refund/order/KOT numbers
    // that this installation already used after the backup was taken.
    for (final e in liveSequences.entries) {
      db.execute('UPDATE sequences SET next_value = MAX(next_value, ?) WHERE name = ?', [e.value, e.key]);
    }
    if (newPrefix != null) {
      db.execute('UPDATE installation SET receipt_prefix = ?', [newPrefix]);
    }
    db.execute(
      'INSERT INTO audit_events (id, at, actor_id, actor_name, action, entity_type, entity_id, details_json, approved_by) '
      "VALUES (?, ?, ?, ?, 'backup.restored', 'installation', NULL, ?, ?)",
      [auditId, nowMs, actorId, actorName, details, approvedBy],
    );
    db.execute('COMMIT');
  } on Object {
    db.execute('ROLLBACK');
    rethrow;
  } finally {
    db.close();
  }
}

/// For tests and diagnostics: count rows in a table of a database file.
Future<int> countRows(AppDatabase db, String table) async {
  final r = await db
      .customSelect('SELECT COUNT(*) AS n FROM $table', variables: const <Variable<Object>>[])
      .getSingle();
  return r.read<int>('n');
}
