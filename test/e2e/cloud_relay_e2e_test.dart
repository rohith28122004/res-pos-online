@Tags(['cloud-e2e'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cafedesk/core/backup/backup_service.dart';
import 'package:cafedesk/core/host/cloud_connector.dart';
import 'package:cafedesk/core/host/command_dispatcher.dart';
import 'package:cafedesk/core/host/host_api.dart';
import 'package:cafedesk/core/host/host_identity.dart';
import 'package:cafedesk/core/host/host_keys.dart';
import 'package:cafedesk/core/host/lan_server.dart';
import 'package:cafedesk/core/network/lan_client.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/service_context.dart';
import 'package:cafedesk/core/sync/client_database.dart';
import 'package:cafedesk/core/sync/cloud_route.dart';
import 'package:cafedesk/core/sync/device_sync.dart';
import 'package:cafedesk/core/sync/host_route.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/dashboard/application/report_service.dart';
import 'package:cafedesk/features/devices/application/device_service.dart';
import 'package:cafedesk/features/expenses/application/expense_service.dart';
import 'package:cafedesk/features/refunds/application/refund_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/connected.dart';
import '../support/file_host.dart';
import '../support/harness.dart';

/// Cross-language end-to-end test: the Dart POS host and phones against the
/// REAL cloud Worker (Durable Object, D1, R2) running locally under
/// `wrangler dev`. Opt-in because it starts Node/workerd:
///
///   flutter test --dart-define=CAFEDESK_CLOUD_E2E=true test/e2e
///
/// Uses the cloud's local Miniflare state in `cloud/.wrangler/` (git-ignored).
/// Nothing touches a Cloudflare account.
const _enabled = bool.fromEnvironment('CAFEDESK_CLOUD_E2E');
const _port = 8799;

void main() {
  late Process wrangler;
  final cloudUrl = 'http://127.0.0.1:$_port';
  final cloudDir = Directory('cloud').absolute.path;
  final node = Platform.isWindows ? 'node.exe' : 'node';

  Future<String> issueEnrollmentCode() async {
    final r = await Process.run(node, [
      'scripts/issue-enrollment-code.mjs',
      '--label',
      'E2E',
    ], workingDirectory: cloudDir);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    final m = RegExp(r'^\s+([0-9A-Z]{4}(?:-[0-9A-Z]{4})+)\s*$', multiLine: true).firstMatch(r.stdout as String);
    expect(m, isNotNull, reason: 'no code in: ${r.stdout}');
    return m!.group(1)!;
  }

  setUpAll(() async {
    if (!_enabled) return;
    wrangler = await Process.start(
      node,
      ['node_modules/wrangler/bin/wrangler.js', 'dev', '--port', '$_port', '--ip', '127.0.0.1'],
      workingDirectory: cloudDir,
      environment: {'CI': '1', 'WRANGLER_SEND_METRICS': 'false'},
    );
    unawaited(wrangler.stdout.drain<void>());
    unawaited(wrangler.stderr.drain<void>());
    final http = HttpClient();
    final deadline = DateTime.now().add(const Duration(minutes: 10));
    while (true) {
      try {
        final req = await http.getUrl(Uri.parse('$cloudUrl/v1/health'));
        final res = await req.close();
        await res.drain<void>();
        if (res.statusCode == 200) break;
      } on Object {
        // Not up yet.
      }
      if (DateTime.now().isAfter(deadline)) fail('wrangler dev did not start within 10 minutes');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    http.close();
  });

  tearDownAll(() async {
    if (!_enabled) return;
    wrangler.kill();
    await wrangler.exitCode.timeout(const Duration(seconds: 20), onTimeout: () => -1);
  });

  test(
    'LAN down: orders go through the cloud relay to the same POS, exactly once; reports match the POS',
    () async {
      // Real time: the cloud checks session expiry against its own clock.
      final h = await Harness.create(start: DateTime.now().toUtc());
      addTearDown(h.dispose);
      final hostSecrets = MemorySecretStore();
      final identityService = HostIdentityService(h.ctx, hostSecrets);
      final (_, keys) = await identityService.ensure(h.owner);
      final api = HostApi(ctx: h.ctx, keys: keys, dispatcher: CommandDispatcher(h.ctx));
      var lan = LanServer(api);
      await lan.start(port: 0, address: InternetAddress.loopbackIPv4);
      await identityService.setLan(h.owner, enabled: true, port: lan.port);
      final cat = await h.category('Coffee');
      final coffee = await h.item(cat, 'Filter coffee', 4000);
      await addKotPrinter(h);
      final waiter = await addStaff(h, 'Wendy Waiter', StaffRole.waiter);
      await h.openShift();

      final cloud = CloudConnector(api: api, secrets: hostSecrets);
      addTearDown(cloud.dispose);
      await cloud.enroll(h.owner, cloudUrl: cloudUrl, enrollmentCode: await issueEnrollmentCode());
      await cloud.start();

      final identity = (await identityService.current())!;
      final invite = await DeviceService(h.ctx).createInvite(
        h.owner,
        role: DeviceRole.waiter,
        deviceName: 'Waiter phone',
        identity: identity,
        addresses: ['127.0.0.1'],
      );
      final phone = DeviceSync(
        db: openInMemoryClientDatabase(),
        secrets: MemorySecretStore(),
        clock: h.clock,
        cloudRouteFactory: (l) => CloudRoute(Uri.parse(l.cloudUrl!)),
      );
      addTearDown(() async {
        await phone.dispose();
        await phone.db.close();
      });
      final link = await phone.pair(invite.payload, deviceName: 'Waiter phone');
      expect(link.cloudUrl, cloudUrl);
      await phone.signIn('wendy.waiter@test.cafe', 'password-Wendy Waiter');
      // The cloud learns about the device (and later revocations) from events.
      await cloud.uploadNow();

      // --- The café LAN path fails. -------------------------------------------------
      await lan.stop();
      Future<PendingCommandRow> settled(String id, Set<String> states) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (DateTime.now().isBefore(end)) {
          await phone.deliverNow();
          final c = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
          if (states.contains(c.state)) return c;
          await (phone.db.update(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).write(
            const PendingCommandsCompanion(nextAttemptAt: Value(0)),
          );
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
        final c = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
        final s = cloud.currentStatus;
        fail(
          'command $id did not reach $states: state=${c.state} route=${c.lastRoute} mailbox=${c.mailboxState} '
          'error=${c.errorCode} ${c.errorMessage} attempts=${c.attempts} | phone route=${phone.currentStatus.route} '
          'problem=${phone.currentStatus.problem} | cloud socket=${s.socketConnected} acked=${s.ackedThrough} '
          'pending=${s.pendingEvents} error=${s.lastError}',
        );
      }

      final first = await phone.enqueue(
        action: CommandAction.orderPlace,
        payload: {
          'orderType': 'takeaway',
          'lines': [line(coffee, 4000, quantity: 2)],
          'sendToKitchen': true,
        },
        summary: 'Takeaway: 2',
      );
      final accepted = await settled(first, {CommandState.accepted});
      expect(accepted.lastRoute, 'cloud', reason: 'LAN is down');
      expect(await h.count(h.db.orders), 1);
      expect(await h.count(h.db.kitchenTickets), 1);
      expect(await h.count(h.db.printJobs), 1);

      // --- The same command again over the LAN once it is back: no duplicate. -------
      lan = LanServer(api);
      await lan.start(port: 0, address: InternetAddress.loopbackIPv4);
      // A fresh port: talk to it directly with the pinned LAN route.
      final body = (jsonDecode(accepted.bodyJson) as Map).cast<String, Object?>();
      final credential = (phone.secrets as MemorySecretStore).values.entries
          .firstWhere((e) => e.key.endsWith('credential'))
          .value;
      final token = (phone.secrets as MemorySecretStore).values.entries
          .firstWhere((e) => e.key.endsWith('session'))
          .value;
      final lanRoute = LanRoute(LanClient(addresses: ['127.0.0.1'], port: lan.port!, certSha256: link.certSha256));
      final again = await lanRoute.send(body, RouteAuth(deviceCredential: credential, sessionToken: token));
      expect(
        again.result!.toJson(),
        CommandResult.fromJson(jsonDecode(accepted.resultJson!) as Map<String, Object?>).toJson(),
      );
      expect(await h.count(h.db.orders), 1);
      expect(await h.count(h.db.kitchenTickets), 1);
      expect(await h.count(h.db.printJobs), 1);
      lanRoute.close();
      await lan.stop();

      // --- POS offline from the cloud: the relay only queues; nothing is accepted. ---
      await cloud.stop();
      final second = await phone.enqueue(
        action: CommandAction.orderPlace,
        payload: {
          'orderType': 'takeaway',
          'lines': [line(coffee, 4000)],
          'sendToKitchen': true,
        },
        summary: 'Takeaway: 1',
      );
      final relayed = await settled(second, {CommandState.relayed, CommandState.queued});
      expect(relayed.state, isNot(CommandState.accepted));
      expect(await h.count(h.db.orders), 1, reason: 'host offline: no false acceptance');
      // The POS comes back: the relay delivers the queued command once.
      await cloud.start();
      await settled(second, {CommandState.accepted});
      expect(await h.count(h.db.orders), 2);

      // --- Sign-in through the relay (password sealed to the POS). -------------------
      await phone.signOut();
      await phone.signIn('wendy.waiter@test.cafe', 'password-Wendy Waiter');
      expect((await phone.session())!.staffId, waiter.staffId);

      // --- Cloud reports reconcile with the POS dashboard. ----------------------------
      final orders = await h.db.select(h.db.orders).get();
      final bill = await h.pay(orders.first.id, [const TenderInput(method: PaymentMethod.cash, applied: 8000)]);
      await h.pay(orders.last.id, [const TenderInput(method: PaymentMethod.upi, applied: 4000)]);
      final state = await RefundService(h.ctx).refundableState(bill.billId);
      await RefundService(h.ctx).issueRefund(
        h.owner,
        RefundRequest(
          billId: bill.billId,
          operationId: 'e2e-refund',
          lineQuantities: {state.lines.single.line.id: 1},
          reason: 'spilled',
        ),
      );
      await ExpenseService(h.ctx).addExpense(h.cashier, category: 'Milk', amount: 1500, paidFromDrawer: true);
      await cloud.uploadNow();
      expect(cloud.currentStatus.lastError, isNull);
      final calendar = await h.ctx.calendar();
      final today = calendar.businessDateOf(h.ctx.now());
      final range = BusinessDateRange(today, today.addDays(1));
      final local = await ReportService(h.ctx).dashboard(h.owner, range);
      final hostCredential = (await HostKeys.readCloudCredential(identity.hostDeviceId, hostSecrets))!;
      final http = HttpClient();
      addTearDown(http.close);
      final req = await http.getUrl(
        Uri.parse('$cloudUrl/v1/reports/summary?from=${range.start.key}&to=${range.endExclusive.key}'),
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $hostCredential');
      final res = await req.close();
      final report = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, Object?>;
      expect(res.statusCode, 200, reason: '$report');
      final cards = (report['cards']! as Map).cast<String, Object?>();
      expect(cards['completedBills'], local.billCount);
      expect(cards['billsTotal'], local.billsTotal);
      expect(cards['refundsTotal'], local.refundsTotal);
      expect(cards['netBilledValue'], local.netBilledValue);
      expect(cards['netItemSales'], local.netItemSales);
      expect(cards['taxesCollected'], local.taxCollected);
      expect(cards['expenses'], local.expensesTotal);
      expect(cards['netCashMovement'], local.netCashMovement);
      expect((cards['receiptsByMethod']! as Map)['upi'], local.receiptsByMethod['upi']);
      final freshness = (report['freshness']! as Map).cast<String, Object?>();
      expect(freshness['ackedThrough'], isNotNull, reason: 'the cloud report says how current it is');
    },
    skip: _enabled ? null : 'set --dart-define=CAFEDESK_CLOUD_E2E=true to run against wrangler dev',
    timeout: const Timeout(Duration(minutes: 15)),
  );

  test(
    'after a backup restore and reconnect, cloud reports match the restored POS (later sales leave them)',
    () async {
      final tmp = await Directory.systemTemp.createTemp('cafedesk_e2e_restore');
      addTearDown(() => tmp.delete(recursive: true));
      final file = FileHost(File(p.join(tmp.path, 'cafedesk.sqlite')));
      addTearDown(file.closeDatabase);
      final h = await Harness.create(start: DateTime.now().toUtc(), database: file.database);
      final secrets = MemorySecretStore();
      final (identity, keys) = await HostIdentityService(h.ctx, secrets).ensure(h.owner);
      final coffee = await h.item(await h.category('Coffee'), 'Filter coffee', 4000);
      await h.openShift();
      var cloud = CloudConnector(
        api: HostApi(ctx: h.ctx, keys: keys, dispatcher: CommandDispatcher(h.ctx)),
        secrets: secrets,
      );
      await cloud.enroll(h.owner, cloudUrl: cloudUrl, enrollmentCode: await issueEnrollmentCode());
      final hostCredential = (await HostKeys.readCloudCredential(identity.hostDeviceId, secrets))!;
      final today = (await h.ctx.calendar()).businessDateOf(h.ctx.now());
      final range = BusinessDateRange(today, today.addDays(1));
      final http = HttpClient();
      addTearDown(http.close);
      Future<Map<String, Object?>> cloudCards() async {
        final req = await http.getUrl(
          Uri.parse('$cloudUrl/v1/reports/summary?from=${range.start.key}&to=${range.endExclusive.key}'),
        );
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $hostCredential');
        final res = await req.close();
        final body = jsonDecode(await utf8.decoder.bind(res).join()) as Map<String, Object?>;
        expect(res.statusCode, 200, reason: '$body');
        return (body['cards']! as Map).cast<String, Object?>();
      }

      // Bill A, the backup, then bill B — the cloud has both.
      await h.pay(await h.orderWith({coffee: 1}), [const TenderInput(method: PaymentMethod.cash, applied: 4000)]);
      await cloud.uploadNow();
      final backups = BackupService(
        h.ctx,
        databaseFile: file.databaseFile,
        defaultBackupDir: Directory(p.join(tmp.path, 'backups')),
        workDir: Directory(p.join(tmp.path, 'work')),
      );
      final backup = await backups.createBackup(actor: h.owner);
      await h.pay(await h.orderWith({coffee: 2}), [const TenderInput(method: PaymentMethod.upi, applied: 8000)]);
      await cloud.uploadNow();
      expect(cloud.currentStatus.lastError, isNull);
      expect((await cloudCards())['completedBills'], 2);
      await cloud.dispose();

      // Restore the backup (bill B is gone), then the owner reconnects.
      final inspection = await backups.inspect(h.owner, await File(backup.path).readAsBytes());
      await backups.restore(h.owner, inspection, approval: await h.approval(), host: file);
      final ctx = ServiceContext(db: file.database, clock: h.clock);
      await HostIdentityService(ctx, secrets).reconnectAfterRestore(h.owner);
      cloud = CloudConnector(
        api: HostApi(ctx: ctx, keys: keys, dispatcher: CommandDispatcher(ctx)),
        secrets: secrets,
      );
      addTearDown(cloud.dispose);
      await cloud.uploadNow();
      expect(cloud.currentStatus.lastError, isNull);
      expect(cloud.currentStatus.pendingEvents, 0);

      final local = await ReportService(ctx).dashboard(h.owner, range);
      final cards = await cloudCards();
      expect(local.billCount, 1);
      expect(cards['completedBills'], local.billCount);
      expect(cards['billsTotal'], local.billsTotal);
      expect((cards['receiptsByMethod']! as Map)['upi'] ?? 0, 0, reason: 'bill B (UPI) is not in the restored POS');
    },
    skip: _enabled ? null : 'set --dart-define=CAFEDESK_CLOUD_E2E=true to run against wrangler dev',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
