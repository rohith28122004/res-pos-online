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
import '../features/setup/application/demo_seed.dart';
import '../features/setup/application/setup_service.dart';
import '../features/shifts/application/shift_service.dart';
import '../features/tables/application/table_service.dart';

/// Production and demo data live in separate SQLite files, so demo sales can
/// never appear in production reports.
enum AppMode { production, demo }

/// Locations inside the platform's application-data directory. The database
/// must stay on local storage — never a network share, OneDrive or Dropbox.
class AppPaths {
  AppPaths(this.root, this.backups);

  final Directory root;
  final Directory backups;

  File get modeFile => File(p.join(root.path, 'mode.json'));
  File get lockFile => File(p.join(root.path, 'cafedesk_online.lock'));
  Directory get work => Directory(p.join(root.path, 'work'));
  File databaseFile(AppMode mode) =>
      File(p.join(root.path, mode == AppMode.demo ? 'cafedesk_online_demo.sqlite' : 'cafedesk_online.sqlite'));

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

  Future<AppMode?> readMode() async {
    try {
      if (!await modeFile.exists()) return null;
      final j = jsonDecode(await modeFile.readAsString()) as Map<String, Object?>;
      if (j['mode'] == 'device') return null;
      return j['mode'] == 'demo' ? AppMode.demo : AppMode.production;
    } on Object {
      return null;
    }
  }

  /// True when this install is a waiter or kitchen device, not a POS.
  Future<bool> isDeviceMode() async {
    try {
      if (!await modeFile.exists()) return false;
      final j = jsonDecode(await modeFile.readAsString()) as Map<String, Object?>;
      return j['mode'] == 'device';
    } on Object {
      return false;
    }
  }

  Future<void> writeDeviceMode() async {
    final tmp = File('.tmp');
    await tmp.writeAsString(jsonEncode({'mode': 'device'}), flush: true);
    await tmp.rename(modeFile.path);
  }

  Future<void> clearMode() async {
    if (await modeFile.exists()) await modeFile.delete();
  }

  Future<void> writeMode(AppMode mode) async {
    final tmp = File('${modeFile.path}.tmp');
    await tmp.writeAsString(jsonEncode({'mode': mode.name}), flush: true);
    await tmp.rename(modeFile.path);
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

/// Owns the open database, the print queue and scheduled backups for one
/// mode. Restore and mode switches close it and build a fresh one.
class AppRuntime implements DatabaseHost {
  AppRuntime._(this.paths, this.mode, this._db, this.clock, this.secrets);

  final AppPaths paths;
  final AppMode mode;
  final Clock clock;

  /// OS secure storage for the host's private keys and cloud credential.
  final SecretStore secrets;
  AppDatabase _db;
  late Services services;

  /// LAN server + cloud connector for paired phones (POS host only).
  late HostConnectivity host;
  PrintQueue? _queue;
  Timer? _backupTimer;
  bool _backupRunning = false;

  /// Last scheduled-backup problem, shown in Settings (null = fine).
  String? lastBackupError;

  @override
  AppDatabase get database => _db;

  @override
  File get databaseFile => paths.databaseFile(mode);

  /// Wraps an already-open database (widget tests).
  @visibleForTesting
  static AppRuntime forTesting(AppPaths paths, AppMode mode, AppDatabase db, Clock clock) =>
      AppRuntime._(paths, mode, db, clock, MemorySecretStore()).._buildServices();

  static Future<AppRuntime> open(
    AppPaths paths,
    AppMode mode, {
    Clock clock = const SystemClock(),
    SecretStore? secrets,
  }) async {
    final file = paths.databaseFile(mode);
    final db = AppDatabase(openDatabaseFile(file));
    // Force open + migrations now so problems surface at startup.
    await db.customSelect('SELECT 1').get();
    final rt = AppRuntime._(paths, mode, db, clock, secrets ?? SecureSecretStore());
    rt._buildServices();
    if (mode == AppMode.demo) {
      final seeder = DemoSeeder(rt.services.ctx);
      if (!await rt.services.setup.isSetupComplete()) {
        await seeder.seed();
      } else {
        await seeder.upgradeLogins();
      }
    }
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
    await host.start();
  }

  Future<void> runScheduledBackup() async {
    if (_backupRunning || _databaseClosed || mode == AppMode.demo) return;
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
    await host.dispose();
    await _queue?.stop();
    _queue = null;
    await _db.close();
  }
}
