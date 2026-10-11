import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/backup/backup_service.dart';
import '../core/database/app_database.dart';
import '../core/host/host_connectivity.dart';
import '../core/printing/queue/print_queue.dart';
import '../core/printing/transports/bluetooth_transport.dart';
import '../core/printing/transports/tcp_transport.dart';
import '../core/printing/transports/transport.dart';
import '../core/printing/transports/windows_spooler.dart';
import '../core/security/secret_store.dart';
import '../core/service_context.dart';
import '../core/time/business_time.dart';
import '../features/audit/application/audit_service.dart';
import '../features/auth/application/auth_service.dart';
import '../features/bills/application/bill_service.dart';
import '../features/checkout/application/checkout_service.dart';
import '../features/dashboard/application/export_service.dart';
import '../features/dashboard/application/report_service.dart';
import '../features/expenses/application/expense_service.dart';
import '../features/menu/application/menu_csv.dart';
import '../features/menu/application/menu_service.dart';
import '../features/orders/application/order_service.dart';
import '../features/refunds/application/refund_service.dart';
import '../features/settings/application/printer_service.dart';
import '../features/settings/application/settings_service.dart';
import '../features/setup/application/setup_service.dart';
import '../features/shifts/application/shift_service.dart';
import '../features/tables/application/table_service.dart';

/// Locations inside the platform's application-data directory. The database
/// must stay on local storage — never a network share, OneDrive or Dropbox.
class AppPaths {
  AppPaths(this.root, this.backups);

  final Directory root;
  final Directory backups;

  File get modeFile => File(p.join(root.path, 'mode.json'));
  File get lockFile => File(p.join(root.path, 'cafedesk_online.lock'));
  Directory get work => Directory(p.join(root.path, 'work'));

  /// The POS database (this install is the café's till).
  File get databaseFile => File(p.join(root.path, 'cafedesk_online.sqlite'));

  /// Waiter / kitchen phone data (pairing, drafts, queue, cache).
  File get deviceDatabaseFile => File(p.join(root.path, 'cafedesk_online_device.sqlite'));

  static Future<AppPaths> resolve() async {
    final support = await getApplicationSupportDirectory();
    final root = Directory(p.join(support.path, 'data'));
    await root.create(recursive: true);
    Directory backups;
    if (Platform.isAndroid) {
      // App-specific external storage is reachable over USB file transfer.
      final ext = await getExternalStorageDirectory();
      backups = Directory(p.join((ext ?? support).path, 'backups'));
    } else {
      backups = Directory(p.join(support.path, 'backups'));
    }
    await backups.create(recursive: true);
    return AppPaths(root, backups);
  }

  /// What this install is: `production` (the POS), `device` (waiter phone or
  /// kitchen display), `demo` (removed sample café, cleaned up at start) or
  /// null (not chosen yet).
  Future<String?> readMode() async {
    try {
      if (!await modeFile.exists()) return null;
      final j = jsonDecode(await modeFile.readAsString()) as Map<String, Object?>;
      return j['mode'] as String?;
    } on Object {
      return null;
    }
  }

  /// True when this install is a waiter or kitchen device, not a POS.
  Future<bool> isDeviceMode() async => await readMode() == 'device';

  Future<void> writeDeviceMode() => _writeMode('device');

  Future<void> writePosMode() => _writeMode('production');

  Future<void> _writeMode(String mode) async {
    final tmp = File('${modeFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({'mode': mode}), flush: true);
    await tmp.rename(modeFile.path);
  }

  Future<void> clearMode() async {
    if (await modeFile.exists()) await modeFile.delete();
  }

  /// Deletes the sample database of the removed demo café, with its built-in
  /// sign-ins. The real POS database is never touched.
  Future<void> deleteOldDemo() async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      final f = File(p.join(root.path, 'cafedesk_online_demo.sqlite$suffix'));
      if (await f.exists()) await f.delete();
    }
  }
}

/// One running app per data directory (Windows can start a second copy).
class InstanceLock {
  InstanceLock._(this._file);
  final RandomAccessFile _file;

  static Future<InstanceLock?> acquire(File lockFile) async {
    try {
      final raf = await lockFile.open(mode: FileMode.write);
      try {
        await raf.lock(FileLock.exclusive);
      } on FileSystemException {
        await raf.close();
        return null;
      }
      await raf.writeString('$pid\n');
      await raf.flush();
      return InstanceLock._(raf);
    } on FileSystemException {
      return null;
    }
  }

  Future<void> release() async {
    try {
      await _file.unlock();
    } on FileSystemException {
      // Already released.
    }
    await _file.close();
  }
}

/// All application services built on the current database connection.
class Services {
  Services(this.ctx, {required this.backupService});

  final ServiceContext ctx;
  final BackupService backupService;

  late final setup = SetupService(ctx);
  late final auth = AuthService(ctx);
  late final settings = SettingsService(ctx);
  late final menu = MenuService(ctx);
  late final menuCsv = MenuCsvService(ctx);
  late final tables = TableService(ctx);
  late final orders = OrderService(ctx);
  late final checkout = CheckoutService(ctx);
  late final bills = BillService(ctx);
  late final refunds = RefundService(ctx);
  late final shifts = ShiftService(ctx);
  late final expenses = ExpenseService(ctx);
  late final reports = ReportService(ctx);
  late final exports = ExportService(ctx);
  late final printers = PrinterService(ctx);
  late final audit = AuditService(ctx);
}

Map<TransportType, PrinterTransport> platformTransports() => {
  TransportType.tcp: const TcpTransport(),
  if (Platform.isAndroid) TransportType.bluetooth: const BluetoothTransport(),
  if (Platform.isWindows) TransportType.windowsRaw: const WindowsSpoolerTransport(),
  if (Platform.isWindows) TransportType.windowsDriver: const WindowsSpoolerTransport(),
};

/// Owns the open POS database, the print queue and scheduled backups.
/// Restore closes it and builds a fresh one.
class AppRuntime implements DatabaseHost {
  AppRuntime._(this.paths, this._db, this.clock, this.secrets);

  final AppPaths paths;
  final Clock clock;

  /// OS secure storage for the host's private keys and cloud credential.
  final SecretStore secrets;
  AppDatabase _db;
  late Services services;

  /// LAN server + cloud connector for paired phones (POS host only).
  late HostConnectivity host;
  PrintQueue? _queue;
  Timer? _backupTimer;
  Timer? _pruneTimer;
  bool _backupRunning = false;

  /// Last scheduled-backup problem, shown in Settings (null = fine).
  String? lastBackupError;

  @override
  AppDatabase get database => _db;

  @override
  File get databaseFile => paths.databaseFile;

  /// Wraps an already-open database (widget tests).
  @visibleForTesting
  static AppRuntime forTesting(AppPaths paths, AppDatabase db, Clock clock) =>
      AppRuntime._(paths, db, clock, MemorySecretStore()).._buildServices();

  static Future<AppRuntime> open(AppPaths paths, {Clock clock = const SystemClock(), SecretStore? secrets}) async {
    final db = AppDatabase(openDatabaseFile(paths.databaseFile));
    // Force open + migrations now so problems surface at startup.
    await db.customSelect('SELECT 1').get();
    final rt = AppRuntime._(paths, db, clock, secrets ?? SecureSecretStore());
    rt._buildServices();
    return rt;
  }

  void _buildServices() {
    final ctx = ServiceContext(db: _db, clock: clock);
    services = Services(
      ctx,
      backupService: BackupService(
        ctx,
        databaseFile: databaseFile,
        defaultBackupDir: paths.backups,
        workDir: paths.work,
      ),
    );
    host = HostConnectivity(services.ctx, secrets);
  }

  /// Starts background work once setup is complete.
  Future<void> startBackground() async {
    if (_queue == null) {
      _queue = PrintQueue(services.ctx, transports: platformTransports());
      await _queue!.start();
    }
    _backupTimer ??= Timer.periodic(const Duration(minutes: 15), (_) => unawaited(runScheduledBackup()));
    // Catch-up backup shortly after launch.
    unawaited(Future<void>.delayed(const Duration(seconds: 20), runScheduledBackup));
    _pruneTimer ??= Timer.periodic(const Duration(hours: 6), (_) => unawaited(pruneOutbox()));
    unawaited(Future<void>.delayed(const Duration(minutes: 1), pruneOutbox));
    await host.start();
  }

  /// Drops device/cloud events nothing needs any more (HostOutbox.prune).
  Future<void> pruneOutbox() async {
    if (_databaseClosed) return;
    try {
      await services.ctx.outbox.prune();
    } on Object {
      // Pruning is housekeeping; it is retried on the next run.
    }
  }

  Future<void> runScheduledBackup() async {
    if (_backupRunning || _databaseClosed) return;
    _backupRunning = true;
    try {
      if (!await services.setup.isSetupComplete()) return;
      if (await services.backupService.isBackupDue()) {
        await services.backupService.createBackup(reason: 'scheduled');
      }
      lastBackupError = null;
    } on Object catch (e) {
      lastBackupError = e.toString();
    } finally {
      _backupRunning = false;
    }
  }

  void kickPrintQueue() => _queue?.kick();

  /// True while a restore has the database closed (no scheduled backups).
  bool _databaseClosed = false;

  @override
  Future<void> closeDatabase() async {
    _databaseClosed = true;
    await host.stop();
    await _queue?.stop();
    _queue = null;
    await _db.close();
  }

  @override
  Future<AppDatabase> reopenDatabase() async {
    _db = AppDatabase(openDatabaseFile(databaseFile));
    await _db.customSelect('SELECT 1').get();
    _buildServices();
    _databaseClosed = false;
    return _db;
  }

  Future<void> dispose() async {
    _backupTimer?.cancel();
    _backupTimer = null;
    _pruneTimer?.cancel();
    _pruneTimer = null;
    await host.dispose();
    await _queue?.stop();
    _queue = null;
    await _db.close();
  }
}
