import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/printing/queue/print_job_writer.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/orders/application/order_service.dart';
import 'package:cafedesk/features/orders/domain/order_models.dart';
import 'package:cafedesk/features/settings/application/printer_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/harness.dart';

class FileHost implements DatabaseHost {
  FileHost(this.databaseFile) : _db = _open(databaseFile);
  @override
  final File databaseFile;
  AppDatabase? _db;
  bool failNextOpen = false;

  static AppDatabase _open(File f) => AppDatabase(NativeDatabase(f, setup: configureConnection));

  @override
  AppDatabase get database => _db!;

  @override
  Future<void> closeDatabase() async {
    await _db?.close();
    _db = null;
  }

  @override
  Future<AppDatabase> reopenDatabase() async {
    final db = _open(databaseFile);
    if (failNextOpen) {
      failNextOpen = false;
      await db.close();
      throw StateError('simulated failure while opening');
    }
    _db = db;
    await db.select(db.restaurantSettings).get();
    return db;
  }
}

void main() {
  late Directory tmp;
  late FileHost host;
  late Harness h;
  late String coffee;

  BackupService backups(ServiceContext ctx) => BackupService(
    ctx,
    databaseFile: host.databaseFile,
    defaultBackupDir: Directory(p.join(tmp.path, 'backups')),
    workDir: Directory(p.join(tmp.path, 'work')),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cafedesk_backup_test');
    host = FileHost(File(p.join(tmp.path, 'cafedesk.sqlite')));
    h = await Harness.create(database: host.database);
    final cat = await h.category('Cafe');
    coffee = await h.item(cat, 'Coffee', 10000);
    await h.openShift();
    await PrinterService(h.ctx).saveProfile(
      h.owner,
      const PrinterProfileInput(
        name: 'Counter',
        role: PrinterRole.receipt,
        paperWidthMm: 80,
        dotsWidth: 576,
        charsPerLine: 48,
        codePage: 'cp437',
        renderMode: 'auto',
        cutter: 'partial',
        drawerPulse: false,
        transport: TransportType.tcp,
        endpoint: '192.168.1.20',
        port: 9100,
      ),
    );
  });

  tearDown(() async {
    await host.closeDatabase();
    await tmp.delete(recursive: true);
  });

  Future<String> sell(ServiceContext ctx) async {
    final orders = OrderService(ctx);
    final id = await orders.createOrder(h.cashier, type: OrderType.takeaway);
    await orders.addItem(h.cashier, id, itemId: coffee);
    final r = await h.pay(id, [const TenderInput(method: PaymentMethod.cash, applied: 10000)]);
    return r.receiptNo;
  }

  test('committed carts and sales survive a restart (close + reopen the file)', () async {
    final receipt = await sell(h.ctx);
    final orders = OrderService(h.ctx);
    final open = await orders.createOrder(h.cashier, type: OrderType.takeaway);
    await orders.addItem(h.cashier, open, itemId: coffee, quantity: 3);
    await host.closeDatabase(); // like the app being killed after commit
    final db = await host.reopenDatabase();
    final ctx = ServiceContext(db: db, clock: h.clock);
    final after = await OrderService(ctx).openOrders();
    expect(after.single.order.id, open);
    expect(after.single.itemCount, 3);
    expect((await db.select(db.bills).get()).single.receiptNo, receipt);
    expect(await db.peekSequenceValue('receipt'), 2);
  });

  test('backup is a consistent archive with manifest and checksum', () async {
    await sell(h.ctx);
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    expect(b.path, endsWith('.$backupExtension'));
    expect(b.manifest.billCount, 1);
    expect(b.manifest.schemaVersion, AppDatabase.latestSchemaVersion);
    final archive = ZipDecoder().decodeBytes(await File(b.path).readAsBytes());
    expect(archive.files.map((f) => f.name).toSet(), {'manifest.json', 'cafedesk.sqlite'});
    final manifest = jsonDecode(utf8.decode(archive.findFile('manifest.json')!.content)) as Map;
    expect(manifest['encrypted'], false);
    final listed = await backups(h.ctx).listBackups();
    expect(listed.single.path, b.path);
    final settings = await h.ctx.settings();
    expect(settings.lastBackupAt, isNotNull);
  });

  test('inspection validates and summarises', () async {
    await sell(h.ctx);
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    final insp = await backups(h.ctx).inspect(h.owner, await File(b.path).readAsBytes());
    expect(insp.billCount, 1);
    expect(insp.restaurantName, 'Test Café');
    expect(insp.sameInstallation, isTrue);
    await backups(h.ctx).discardInspection(insp);
  });

  Uint8List rezip(Map<String, List<int>> files) {
    final a = Archive();
    files.forEach((name, bytes) => a.addFile(ArchiveFile.bytes(name, bytes)));
    return ZipEncoder().encodeBytes(a);
  }

  test('corrupt, tampered, future and unsafe backups are rejected', () async {
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    final bytes = await File(b.path).readAsBytes();
    final svc = backups(h.ctx);
    await expectLater(svc.inspect(h.owner, Uint8List.fromList(List.filled(100, 7))), throwsA(isA<BackupException>()));

    final archive = ZipDecoder().decodeBytes(bytes);
    final manifest = archive.findFile('manifest.json')!.content;
    final db = archive.findFile('cafedesk.sqlite')!.content;

    final tampered = Uint8List.fromList(db)..[db.length - 1] ^= 0xFF;
    await expectLater(
      svc.inspect(h.owner, rezip({'manifest.json': manifest, 'cafedesk.sqlite': tampered})),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('checksum'))),
    );

    final future = (jsonDecode(utf8.decode(manifest)) as Map<String, Object?>)..['schemaVersion'] = 999;
    await expectLater(
      svc.inspect(h.owner, rezip({'manifest.json': utf8.encode(jsonEncode(future)), 'cafedesk.sqlite': db})),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('Update the app'))),
    );

    await expectLater(
      svc.inspect(
        h.owner,
        rezip({
          'manifest.json': manifest,
          'cafedesk.sqlite': db,
          '../evil.dll': [1, 2, 3],
        }),
      ),
      throwsA(isA<BackupException>()),
    );
    expect(isSafeArchiveEntry('../x'), isFalse);
    expect(isSafeArchiveEntry('C:/x'), isFalse);
    expect(isSafeArchiveEntry('a\\b'), isFalse);
    expect(isSafeArchiveEntry('/etc/passwd'), isFalse);
    expect(isSafeArchiveEntry('manifest.json'), isTrue);

    await expectLater(svc.inspect(h.cashier, bytes), throwsA(isA<PermissionDeniedException>()));
  });

  test('restore swaps data, keeps receipt numbers moving forward and holds old print jobs', () async {
    final first = await sell(h.ctx); // TST-000001 (print job queued)
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    final later = await sell(h.ctx); // TST-000002 — not in the backup
    expect([first, later], ['TST-000001', 'TST-000002']);

    final insp = await backups(h.ctx).inspect(h.owner, await File(b.path).readAsBytes());
    final outcome = await backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host);
    expect(File(outcome.preRestoreBackupPath).existsSync(), isTrue);

    final db = host.database;
    final ctx = ServiceContext(db: db, clock: h.clock);
    expect((await db.select(db.bills).get()).map((b) => b.receiptNo), ['TST-000001']);
    // The number used after the backup is never reissued.
    expect(await db.peekSequenceValue('receipt'), 3);
    final jobs = await db.select(db.printJobs).get();
    expect(jobs.every((j) => j.state == PrintJobState.held), isTrue);
    final audit = await (db.select(db.auditEvents)..where((e) => e.action.equals('backup.restored'))).get();
    expect(audit, hasLength(1));
    // The restored database is fully usable.
    final orders = OrderService(ctx);
    final id = await orders.createOrder(h.cashier, type: OrderType.takeaway);
    expect(id, isNotEmpty);
  });

  test('a failure during restore rolls back to the previous data', () async {
    await sell(h.ctx);
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    await sell(h.ctx);
    final insp = await backups(h.ctx).inspect(h.owner, await File(b.path).readAsBytes());
    host.failNextOpen = true;
    await expectLater(
      backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host),
      throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('put back'))),
    );
    final db = host.database;
    expect((await db.select(db.bills).get()).length, 2);
  });

  test('restore requires an owner and a fresh PIN approval', () async {
    final b = await backups(h.ctx).createBackup(actor: h.owner);
    final insp = await backups(h.ctx).inspect(h.owner, await File(b.path).readAsBytes());
    final approval = await h.approval();
    await expectLater(
      backups(h.ctx).restore(h.cashier, insp, approval: approval, host: host),
      throwsA(isA<PermissionDeniedException>()),
    );
    h.clock.advance(const Duration(minutes: 10));
    await expectLater(
      backups(h.ctx).restore(h.owner, insp, approval: approval, host: host),
      throwsA(isA<ApprovalRequiredException>()),
    );
  });

  test('a backup from another installation restores with a new receipt prefix', () async {
    // Build a second, independent installation and back it up.
    final otherDir = await Directory.systemTemp.createTemp('cafedesk_other');
    final otherHost = FileHost(File(p.join(otherDir.path, 'other.sqlite')));
    final other = await Harness.create(database: otherHost.database);
    final otherBackup = await BackupService(
      other.ctx,
      databaseFile: otherHost.databaseFile,
      defaultBackupDir: Directory(p.join(otherDir.path, 'b')),
      workDir: Directory(p.join(otherDir.path, 'w')),
    ).createBackup(actor: other.owner);
    final bytes = await File(otherBackup.path).readAsBytes();
    await otherHost.closeDatabase();
    await otherDir.delete(recursive: true);

    final insp = await backups(h.ctx).inspect(h.owner, bytes);
    expect(insp.sameInstallation, isFalse);
    await backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host, newReceiptPrefix: 'NEW');
    final inst = await host.database.select(host.database.installation).getSingle();
    expect(inst.receiptPrefix, 'NEW');
  });
}
