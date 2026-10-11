import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/host/command_dispatcher.dart';
import 'package:cafedesk/core/host/host_api.dart';
import 'package:cafedesk/core/host/host_identity.dart';
import 'package:cafedesk/core/host/host_keys.dart';
import 'package:cafedesk/core/host/lan_server.dart';
import 'package:cafedesk/core/network/lan_client.dart';
import 'package:cafedesk/core/protocol/canonical_json.dart';
import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/sync/client_database.dart';
import 'package:cafedesk/core/sync/device_sync.dart';
import 'package:cafedesk/features/devices/application/device_service.dart';
import 'package:cafedesk/features/tables/application/table_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../support/connected.dart';
import '../support/harness.dart';

/// End-to-end over real TLS sockets on this machine: the POS host's LAN server
/// and phones running the device sync engine. (Automated; not a physical
/// device or Wi-Fi test.)
void main() {
  late Harness h;
  late MemorySecretStore hostSecrets;
  late LanServer server;
  late String coffee;
  late String t1;
  late Actor waiter;
  final phones = <DeviceSync>[];

  setUp(() async {
    h = await Harness.create();
    hostSecrets = MemorySecretStore();
    final identityService = HostIdentityService(h.ctx, hostSecrets);
    final (_, keys) = await identityService.ensure(h.owner);
    server = LanServer(HostApi(ctx: h.ctx, keys: keys, dispatcher: CommandDispatcher(h.ctx)));
    await server.start(port: 0, address: InternetAddress.loopbackIPv4);
    await identityService.setLan(h.owner, enabled: true, port: server.port);
    final cat = await h.category('Coffee');
    coffee = await h.item(cat, 'Filter coffee', 4000);
    t1 = await TableService(h.ctx).createTable(h.owner, name: 'T1');
    waiter = await addStaff(h, 'Wendy Waiter', StaffRole.waiter);
  });

  tearDown(() async {
    for (final p in phones) {
      await p.dispose();
      await p.db.close();
    }
    phones.clear();
    await server.stop();
    await h.dispose();
  });

  Future<String> invite(String role) async {
    final identity = (await HostIdentityService(h.ctx, hostSecrets).current())!;
    final inv = await DeviceService(h.ctx).createInvite(
      h.owner,
      role: role,
      deviceName: '$role phone',
      identity: identity,
      addresses: ['127.0.0.1'],
    );
    return inv.payload;
  }

  DeviceSync newPhone() {
    final p = DeviceSync(db: openInMemoryClientDatabase(), secrets: MemorySecretStore(), clock: h.clock);
    phones.add(p);
    return p;
  }

  Future<DeviceSync> pairedPhone(String role, {String? email, String? password}) async {
    final p = newPhone();
    await p.pair(await invite(role), deviceName: '$role phone');
    if (email != null) await p.signIn(email, password!);
    return p;
  }

  Future<T> eventually<T>(Future<T?> Function() probe, {Duration timeout = const Duration(seconds: 10)}) async {
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      final v = await probe();
      if (v != null) return v;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('condition not met within $timeout');
  }

  test('pairing is single-use and expires; the device credential is stored only as a hash', () async {
    final payload = await invite(DeviceRole.waiter);
    final a = newPhone();
    final link = await a.pair(payload, deviceName: 'Front phone');
    expect(link.role, DeviceRole.waiter);
    final row = await (h.db.select(h.db.pairedDevices)..where((d) => d.id.equals(link.deviceId))).getSingle();
    final credential = (a.secrets as MemorySecretStore).values.values.single;
    expect(row.credentialHash, sha256Hex(credential));
    expect(row.credentialHash, isNot(contains(credential.split('.').last)));

    final b = newPhone();
    await expectLater(b.pair(payload, deviceName: 'Copycat'), throwsA(isA<ConflictException>()));

    final late = await invite(DeviceRole.waiter);
    h.clock.advance(const Duration(minutes: 11));
    await expectLater(newPhone().pair(late, deviceName: 'Late'), throwsA(isA<ValidationException>()));
  });

  test('a waiter signs in with a sealed password, places an order, and sees it accepted', () async {
    final phone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    expect((await phone.session())!.role, StaffRole.waiter.name);
    await phone.refresh();
    final menu = await (phone.db.select(phone.db.cacheEntries)..where((c) => c.key.equals('menu'))).getSingle();
    expect(menu.json, contains('Filter coffee'));

    final id = await phone.enqueue(
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'dine_in',
        'tableId': t1,
        'lines': [line(coffee, 4000, quantity: 2)],
        'sendToKitchen': true,
      },
      summary: 'T1: 2 items',
    );
    await phone.deliverNow();
    final cmd = await eventually(() async {
      final c = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
      return c.state == CommandState.accepted ? c : null;
    });
    expect(cmd.lastRoute, 'lan');
    expect(await h.count(h.db.orders), 1);
    expect(await h.count(h.db.kitchenTickets), 1);
    // The accepted order reaches the phone's cache through the event stream.
    await eventually(() async {
      final rows = await (phone.db.select(phone.db.cacheEntries)..where((c) => c.kind.equals('order'))).get();
      return rows.isNotEmpty ? rows : null;
    });
    final order = await h.db.select(h.db.orders).getSingle();
    expect(order.createdByName, 'Wendy Waiter');
  });

  test('wrong password, wrong role for the device, and accounts that must change password are refused', () async {
    final phone = await pairedPhone(DeviceRole.waiter);
    await expectLater(phone.signIn('wendy.waiter@test.cafe', 'nope-nope'), throwsA(isA<ConflictException>()));
    await expectLater(phone.signIn('ken@test.cafe', 'kitchen-pass-1'), throwsA(isA<ConflictException>()));
    await h.auth.createStaff(
      h.owner,
      name: 'New',
      email: 'new@test.cafe',
      role: StaffRole.waiter,
      password: 'start-pass',
    );
    await expectLater(phone.signIn('new@test.cafe', 'start-pass'), throwsA(isA<ConflictException>()));
    expect(await phone.session(), isNull);
  });

  test('every route needs the device credential and a valid host-signed session', () async {
    final phone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    final link = (await phone.link())!;
    final credential = (phone.secrets as MemorySecretStore).values.entries
        .firstWhere((e) => e.key.endsWith('credential'))
        .value;
    final token = (phone.secrets as MemorySecretStore).values.entries
        .firstWhere((e) => e.key.endsWith('session'))
        .value;
    final client = LanClient(addresses: ['127.0.0.1'], port: server.port!, certSha256: link.certSha256);
    addTearDown(client.close);
    Future<String> code(Map<String, String> headers) async {
      try {
        await client.request('GET', '/v1/snapshot', headers: headers);
        return 'ok';
      } on ProtocolException catch (e) {
        return e.code;
      }
    }

    expect(await code({}), ErrorCode.unauthenticated);
    expect(await code({'x-cafedesk-device': credential}), ErrorCode.unauthenticated, reason: 'no session');
    expect(await code({'x-cafedesk-device': credential, 'authorization': 'Bearer $token'}), 'ok');
    // Forged claims (role changed to owner) break the signature.
    final parts = token.split('.');
    final claims = (jsonDecode(utf8.decode(b64urlDecode(parts[1]))) as Map).cast<String, Object?>();
    final forged = 'cds1.${b64url(utf8.encode(canonicalJson({...claims, 'role': 'owner'})))}.${parts[2]}';
    expect(await code({'x-cafedesk-device': credential, 'authorization': 'Bearer $forged'}), ErrorCode.unauthenticated);
    // A wrong secret for a real device id.
    final fake = 'cdd1.${link.deviceId}.${DeviceService.randomSecret()}';
    expect(await code({'x-cafedesk-device': fake, 'authorization': 'Bearer $token'}), ErrorCode.unauthenticated);
    // Another device's credential with this device's token.
    final other = await pairedPhone(DeviceRole.waiter);
    final otherCredential = (other.secrets as MemorySecretStore).values.values.single;
    expect(
      await code({'x-cafedesk-device': otherCredential, 'authorization': 'Bearer $token'}),
      ErrorCode.unauthenticated,
    );
    // Disabling the account ends the session at once.
    await h.auth.updateStaff(h.owner, waiter.staffId, disabled: true);
    expect(await code({'x-cafedesk-device': credential, 'authorization': 'Bearer $token'}), ErrorCode.sessionExpired);
    // Revoking the device ends everything for it.
    await DeviceService(h.ctx).revoke(h.owner, link.deviceId);
    expect(await code({'x-cafedesk-device': credential, 'authorization': 'Bearer $token'}), ErrorCode.deviceRevoked);
  });

  test('a phone refuses a server whose certificate is not the paired one', () async {
    final phone = await pairedPhone(DeviceRole.waiter);
    final link = (await phone.link())!;
    // Another "POS" on the network with its own certificate.
    final impostorKeys = await HostKeys.generate('impostor-0000', MemorySecretStore());
    final impostor = await HttpServer.bindSecure(
      InternetAddress.loopbackIPv4,
      0,
      SecurityContext()
        ..useCertificateChainBytes(utf8.encode(impostorKeys.tlsCertPem))
        ..usePrivateKeyBytes(utf8.encode(impostorKeys.tlsKeyPem)),
    );
    addTearDown(() => impostor.close(force: true));
    impostor.listen((r) {
      r.response.write('{"ok":true}');
      unawaited(r.response.close());
    });
    final client = LanClient(addresses: ['127.0.0.1'], port: impostor.port, certSha256: link.certSha256);
    addTearDown(client.close);
    await expectLater(
      client.request('GET', '/v1/health'),
      throwsA(isA<ProtocolException>().having((e) => e.code, 'code', wrongCertificate)),
    );
  });

  test('pairing and sign-in are rate limited per address', () async {
    final phone = await pairedPhone(DeviceRole.waiter);
    for (var i = 0; i < 5; i++) {
      await expectLater(phone.signIn('wendy.waiter@test.cafe', 'wrong-$i-pass'), throwsA(isA<ConflictException>()));
    }
    await expectLater(
      phone.signIn('wendy.waiter@test.cafe', 'password-Wendy Waiter'),
      throwsA(isA<ConflictException>().having((e) => e.message, 'message', contains('Too many'))),
    );
  });

  test('kitchen board gets new tickets live, alarms once, and status changes need the current revision', () async {
    final kitchen = await pairedPhone(DeviceRole.kitchen, email: 'ken@test.cafe', password: 'kitchen-pass-1');
    final alarms = <Map<String, Object?>>[];
    final sub = kitchen.alarms.listen(alarms.add);
    addTearDown(sub.cancel);
    var socketChanges = 0;
    server.onSocketsChanged = () => socketChanges++;
    await kitchen.start();
    await eventually(() async => kitchen.currentStatus.live ? true : null);
    // The POS status chip counts live devices and is told when it changes.
    expect(server.connectedSockets, 1);
    expect(socketChanges, greaterThanOrEqualTo(1));

    final waiterPhone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    await waiterPhone.enqueue(
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
      summary: 'Takeaway: 1 item',
    );
    await waiterPhone.deliverNow();
    final ticket = await eventually(() async {
      final rows = await (kitchen.db.select(kitchen.db.cacheEntries)..where((c) => c.kind.equals('ticket'))).get();
      return rows.isEmpty ? null : (jsonDecode(rows.single.json) as Map).cast<String, Object?>();
    });
    await eventually(() async => alarms.length == 1 ? true : null);

    // Reconnecting replays nothing new and sounds nothing again.
    await kitchen.stop();
    await eventually(() async => server.connectedSockets == 0 ? true : null);
    expect(socketChanges, greaterThanOrEqualTo(2));
    await kitchen.start();
    await eventually(() async => kitchen.currentStatus.live ? true : null);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(alarms, hasLength(1));

    final ticketId = ticket['ticketId']! as String;
    final ok = await kitchen.enqueue(
      action: CommandAction.ticketSetStatus,
      aggregateId: ticketId,
      expectedRevision: ticket['revision']! as int,
      payload: {'status': 'preparing'},
      summary: 'Preparing',
    );
    await kitchen.deliverNow();
    await eventually(() async {
      final c = await (kitchen.db.select(kitchen.db.pendingCommands)..where((x) => x.commandId.equals(ok))).getSingle();
      return c.state == CommandState.accepted ? c : null;
    });
    // A second, stale update from the same old revision is refused.
    final stale = await kitchen.enqueue(
      action: CommandAction.ticketSetStatus,
      aggregateId: ticketId,
      expectedRevision: ticket['revision']! as int,
      payload: {'status': 'ready'},
      summary: 'Ready',
    );
    await kitchen.deliverNow();
    final staleRow = await eventually(() async {
      final c = await (kitchen.db.select(
        kitchen.db.pendingCommands,
      )..where((x) => x.commandId.equals(stale))).getSingle();
      return c.state == CommandState.rejected ? c : null;
    });
    expect(staleRow.errorCode, ErrorCode.staleRevision);
    final row = await (h.db.select(h.db.kitchenTickets)..where((t) => t.id.equals(ticketId))).getSingle();
    expect(row.status, 'preparing');
  });

  test('a lost response is resolved by looking up the result, not by repeating the order', () async {
    final phone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    final id = await phone.enqueue(
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
      summary: 'Takeaway',
    );
    // Simulate: the POS committed it, but the phone never saw the answer.
    final row = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
    final link = (await phone.link())!;
    final session = (await phone.session())!;
    await CommandDispatcher(h.ctx).handle(
      caller(
        link.deviceId,
        DeviceRole.waiter,
        Actor(staffId: session.staffId, name: session.name, role: StaffRole.waiter),
      ),
      jsonDecode(row.bodyJson),
    );
    await (phone.db.update(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).write(
      const PendingCommandsCompanion(attempts: Value(1)),
    );
    await phone.deliverNow();
    final done = await eventually(() async {
      final c = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
      return c.state == CommandState.accepted ? c : null;
    });
    expect(done.resultJson, isNotNull);
    expect(await h.count(h.db.orders), 1, reason: 'not placed twice');
    expect(await h.count(h.db.kitchenTickets), 1);
  });

  test('an unsent command older than 30 minutes is held for review, not sent', () async {
    final phone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    await server.stop();
    final id = await phone.enqueue(
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
      summary: 'Takeaway',
    );
    await phone.deliverNow();
    var row = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
    expect(row.state, CommandState.queued, reason: 'saved on the phone, POS unreachable');
    h.clock.advance(const Duration(minutes: 31));
    final keys = await HostIdentityService(h.ctx, hostSecrets).ensure(h.owner);
    server = LanServer(HostApi(ctx: h.ctx, keys: keys.$2, dispatcher: CommandDispatcher(h.ctx)));
    await server.start(
      port: (await HostIdentityService(h.ctx, hostSecrets).current())!.lanPort,
      address: InternetAddress.loopbackIPv4,
    );
    await (phone.db.update(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).write(
      const PendingCommandsCompanion(nextAttemptAt: Value(0)),
    );
    await phone.deliverNow();
    row = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
    expect(row.state, CommandState.needsReview);
    expect(await h.count(h.db.orders), 0);
  });

  test('signing out keeps a person\'s unsent commands for them only', () async {
    final phone = await pairedPhone(
      DeviceRole.waiter,
      email: 'wendy.waiter@test.cafe',
      password: 'password-Wendy Waiter',
    );
    await server.stop();
    final id = await phone.enqueue(
      action: CommandAction.orderPlace,
      payload: {
        'orderType': 'takeaway',
        'lines': [line(coffee, 4000)],
        'sendToKitchen': true,
      },
      summary: 'Takeaway',
    );
    // The first attempt finds the POS down; the order stays saved on the phone.
    await phone.deliverNow();
    expect(
      (await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle()).state,
      CommandState.queued,
    );
    await phone.signOut();
    final keys = await HostIdentityService(h.ctx, hostSecrets).ensure(h.owner);
    server = LanServer(HostApi(ctx: h.ctx, keys: keys.$2, dispatcher: CommandDispatcher(h.ctx)));
    await server.start(
      port: (await HostIdentityService(h.ctx, hostSecrets).current())!.lanPort,
      address: InternetAddress.loopbackIPv4,
    );
    await addStaff(h, 'Will Waiter', StaffRole.waiter);
    await phone.signIn('will.waiter@test.cafe', 'password-Will Waiter');
    await (phone.db.update(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).write(
      const PendingCommandsCompanion(nextAttemptAt: Value(0)),
    );
    await phone.deliverNow();
    final row = await (phone.db.select(phone.db.pendingCommands)..where((x) => x.commandId.equals(id))).getSingle();
    expect(row.state, CommandState.queued, reason: "Wendy's order is not sent under Will's account");
    expect(await h.count(h.db.orders), 0);
  });
}
