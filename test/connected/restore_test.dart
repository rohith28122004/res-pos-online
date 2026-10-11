import 'dart:convert';
import 'dart:io';

import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/host/command_dispatcher.dart';
import 'package:cafedesk/core/host/host_connectivity.dart';
import 'package:cafedesk/core/host/host_identity.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/devices/application/device_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/file_host.dart';
import '../support/connected.dart';
import '../support/harness.dart';

/// Restoring a backup on a POS that serves phones and a cloud (spec §6):
/// new epoch, nothing old reconnects by itself, and the cloud re-send.
void main() {
  late Directory tmp;
  late FileHost host;
  late Harness h;
  late MemorySecretStore secrets;
  late String coffee;

  BackupService backups(ServiceContext ctx) => BackupService(
    ctx,
    databaseFile: host.databaseFile,
    defaultBackupDir: Directory(p.join(tmp.path, 'backups')),
    workDir: Directory(p.join(tmp.path, 'work')),
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cafedesk_restore_connected');
    host = FileHost(File(p.join(tmp.path, 'cafedesk.sqlite')));
    h = await Harness.create(database: host.database);
    secrets = MemorySecretStore();
    coffee = await h.item(await h.category('Cafe'), 'Coffee', 10000);
    await h.openShift();
  });

  tearDown(() async {
    await host.closeDatabase();
    await tmp.delete(recursive: true);
  });

  Future<String> sell() async => (await h.pay(await h.orderWith({coffee: 1}), [
    const TenderInput(method: PaymentMethod.upi, applied: 10000),
  ])).billId;

  /// A real host identity (keys in [secrets]) with phones on and a cloud.
  Future<void> connect() async {
    final service = HostIdentityService(h.ctx, secrets);
    await service.ensure(h.owner);
    await service.setLan(h.owner, enabled: true, port: 47999);
    await (h.db.update(h.db.hostIdentity)).write(
      HostIdentityCompanion(cloudUrl: const Value('https://cloud.test'), cloudEnrolledAt: Value(h.ctx.nowMs())),
    );
  }

  Future<HostIdentityRow> identity(AppDatabase db) => db.select(db.hostIdentity).getSingle();

  test('restore starts a new epoch, keeps this PC\'s pairings and waits for the owner to reconnect', () async {
    await connect();
    final kept = await pairDeviceRow(h, DeviceRole.waiter, id: 'phone-kept');
    await pairDeviceRow(h, DeviceRole.kitchen, id: 'phone-removed-later');
    await h.db
        .into(h.db.staffSessions)
        .insert(
          StaffSessionsCompanion.insert(
            id: 'session-1',
            staffId: h.cashier.staffId,
            deviceId: kept,
            createdAt: h.ctx.nowMs(),
            expiresAt: h.ctx.nowMs() + 3600000,
          ),
        );
    final billA = await sell();
    final backup = await backups(h.ctx).createBackup(actor: h.owner);

    // After the backup: a phone is removed, another paired, another sale.
    await DeviceService(h.ctx).revoke(h.owner, 'phone-removed-later');
    await pairDeviceRow(h, DeviceRole.waiter, id: 'phone-new');
    final billB = await sell();
    final liveNextEvent = await h.db.peekSequenceValue('event');

    final insp = await backups(h.ctx).inspect(h.owner, await File(backup.path).readAsBytes());
    await backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host);

    final db = host.database;
    final ctx = ServiceContext(db: db, clock: h.clock);
    final id = await identity(db);
    expect(id.hostEpoch, 2);
    expect(id.reconcileRequired, isTrue);
    expect(id.epochStartSequence, liveNextEvent, reason: 'the new epoch starts after every number used');
    expect(id.restaurantId, isNotEmpty);
    expect(id.cloudUrl, 'https://cloud.test');

    final devices = {for (final d in await db.select(db.pairedDevices).get()) d.id: d};
    expect(devices['phone-kept']!.revokedAt, isNull);
    expect(devices['phone-removed-later']!.revokedAt, isNotNull, reason: 'a removed phone is not brought back');
    expect(devices['phone-new']!.revokedAt, isNull, reason: 'pairings of this PC survive the restore');
    final sessions = await db.select(db.staffSessions).get();
    expect(sessions.every((s) => s.revokedAt != null), isTrue, reason: 'everyone signs in again');
    expect((await db.select(db.bills).get()).map((b) => b.id), [billA]);

    // Phones and the cloud stay off until the owner reconnects.
    final connectivity = HostConnectivity(ctx, secrets);
    await connectivity.start();
    expect(connectivity.lanRunning, isFalse);
    expect(connectivity.cloud, isNull);
    expect(connectivity.lanError, contains('restored'));
    await connectivity.dispose();

    // Reconnect: everything is re-sent in epoch 2, then the restore marker.
    await HostIdentityService(ctx, secrets).reconnectAfterRestore(h.owner);
    expect((await identity(db)).reconcileRequired, isFalse);
    final epoch2 =
        await (db.select(db.hostEvents)
              ..where((e) => e.hostEpoch.equals(2))
              ..orderBy([(e) => OrderingTerm(expression: e.sequence)]))
            .get();
    expect(epoch2.first.sequence, greaterThanOrEqualTo(liveNextEvent));
    final bills = epoch2.where((e) => e.type == EventType.billFinalized).map((e) => e.aggregateId).toSet();
    expect(bills, {billA}, reason: 'bill B is not in the restored POS, so it is not re-sent');
    expect(bills, isNot(contains(billB)));
    expect(epoch2.last.type, EventType.hostRestored);
    final marker = (jsonDecode(epoch2.last.eventJson) as Map)['payload'] as Map;
    expect(marker, {'epoch': 2, 'previousEpoch': 1});
    final audit = await (db.select(db.auditEvents)..where((a) => a.action.like('connected.re%'))).get();
    expect(audit.map((a) => a.action), contains('connected.reconnected_after_restore'));

    await expectLater(
      HostIdentityService(ctx, secrets).reconnectAfterRestore(h.owner),
      throwsA(isA<ConflictException>()),
    );
  });

  test('reconnecting without the keys on this PC asks for a reset instead', () async {
    await connect();
    final backup = await backups(h.ctx).createBackup(actor: h.owner);
    final insp = await backups(h.ctx).inspect(h.owner, await File(backup.path).readAsBytes());
    await backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host);
    final ctx = ServiceContext(db: host.database, clock: h.clock);
    // Another PC: the keys are not in its secure storage.
    await expectLater(
      HostIdentityService(ctx, MemorySecretStore()).reconnectAfterRestore(h.owner),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', contains('Reset device connections'))),
    );
    final service = HostIdentityService(ctx, MemorySecretStore());
    await service.resetConnections(h.owner);
    final id = await identity(host.database);
    expect(id.reconcileRequired, isFalse);
    expect(id.cloudUrl, isNull);
  });

  test('a POS that never used phones stays a standalone till after a restore', () async {
    await sell();
    final backup = await backups(h.ctx).createBackup(actor: h.owner);
    final insp = await backups(h.ctx).inspect(h.owner, await File(backup.path).readAsBytes());
    await backups(h.ctx).restore(h.owner, insp, approval: await h.approval(), host: host);
    expect(await host.database.select(host.database.hostIdentity).get(), isEmpty);
  });

  test('pruning keeps a week of events and never drops what the cloud has not received', () async {
    await connect();
    await sell();
    final all = await events(h);
    expect(all, isNotEmpty);
    // Half of them acknowledged by the cloud.
    final acked = all.take(all.length ~/ 2).map((e) => e.sequence).toList();
    await (h.db.update(h.db.hostEvents)..where((e) => e.sequence.isIn(acked))).write(
      HostEventsCompanion(cloudAckedAt: Value(h.ctx.nowMs())),
    );
    expect(await h.ctx.outbox.prune(), 0, reason: 'nothing is a week old yet');

    h.clock.advance(const Duration(days: 8));
    expect(await h.ctx.outbox.prune(), acked.length);
    final left = await events(h);
    expect(left.every((e) => e.cloudAckedAt == null), isTrue);
    expect(left, hasLength(all.length - acked.length));

    // Without a cloud, old events are simply dropped; numbers are never reused.
    await (h.db.update(h.db.hostIdentity)).write(const HostIdentityCompanion(cloudUrl: Value(null)));
    final before = await h.ctx.outbox.latestSequence();
    expect(await h.ctx.outbox.prune(), left.length);
    await sell();
    expect((await events(h)).first.sequence, greaterThan(before));
  });
}
