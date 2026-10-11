import 'dart:convert';

import 'package:cafedesk/core/protocol/protocol.dart';
import 'package:cafedesk/core/security/secret_store.dart';
import 'package:cafedesk/core/sync/client_database.dart';
import 'package:cafedesk/core/sync/device_sync.dart';
import 'package:cafedesk/core/time/business_time.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

/// Replay rules on the phone (docs/PROTOCOL.md §5.3), without a network: the
/// cursor only moves forward, old and duplicate events are ignored, and a page
/// is applied in sequence order whatever order it arrived in.
void main() {
  late ClientDatabase db;
  late DeviceSync sync;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = openInMemoryClientDatabase();
    sync = DeviceSync(db: db, secrets: MemorySecretStore(), clock: FixedClock(DateTime.utc(2026, 10, 11, 6)));
    await db
        .into(db.clientLink)
        .insert(
          ClientLinkCompanion.insert(
            singleton: const Value(1),
            deviceId: 'kitchen-1',
            role: 'kitchen',
            deviceName: 'Kitchen tablet',
            restaurantId: 'r1',
            restaurantName: 'Test Café',
            hostDeviceId: 'h1',
            hostEpoch: 1,
            hostAddressesJson: '["127.0.0.1"]',
            hostPort: 47821,
            certSha256: '0' * 64,
            signingPublicKey: 'x',
            sealPublicKey: 'y',
            pairedAt: 0,
            cursorEpoch: const Value(1),
            cursorSequence: const Value(10),
          ),
        );
  });

  tearDown(() async {
    await sync.dispose();
    await db.close();
  });

  Map<String, Object?> ticketEvent(int seq, String ticketId, String status, {int epoch = 1}) => {
    'hostEpoch': epoch,
    'sequence': seq,
    'type': EventType.ticketUpdated,
    'payload': {'ticketId': ticketId, 'ticketNo': seq, 'status': status, 'revision': seq, 'lines': const []},
  };

  Future<Map<String, String>> tickets() async => {
    for (final r in await (db.select(db.cacheEntries)..where((c) => c.kind.equals('ticket'))).get())
      r.key: (jsonDecode(r.json) as Map)['status']! as String,
  };

  Future<int> cursor() async => (await db.select(db.clientLink).getSingle()).cursorSequence;

  test('out-of-order, duplicate and old events are applied once, in sequence order', () async {
    final alarms = <Map<String, Object?>>[];
    final sub = sync.alarms.listen(alarms.add);
    addTearDown(sub.cancel);
    final page = [
      ticketEvent(14, 'k1', 'preparing'),
      ticketEvent(12, 'k1', 'pending'),
      ticketEvent(12, 'k1', 'pending'), // delivered twice
      ticketEvent(13, 'k2', 'pending'),
      ticketEvent(9, 'k9', 'pending'), // at or before the cursor: already applied
    ];
    expect(await sync.applyEvents(1, page, 16), isTrue);
    expect(await tickets(), {'ticket:k1': 'preparing', 'ticket:k2': 'pending'});
    expect(await cursor(), 16, reason: 'through = 16 also covers cloud-only sequences');
    await pumpEventQueue();
    expect(alarms.map((t) => t['ticketId']), ['k1', 'k2'], reason: 'one alarm per new ticket');

    // The same page again (a reconnect replay) changes nothing and sounds nothing.
    expect(await sync.applyEvents(1, page, 16), isTrue);
    await pumpEventQueue();
    expect(alarms, hasLength(2));
    expect(await tickets(), {'ticket:k1': 'preparing', 'ticket:k2': 'pending'});

    // A late, older page cannot move the cursor back or undo a newer state.
    expect(await sync.applyEvents(1, [ticketEvent(12, 'k1', 'pending')], 12), isTrue);
    expect(await cursor(), 16);
    expect((await tickets())['ticket:k1'], 'preparing');
  });

  test('a page from another host epoch is not applied: the phone needs a snapshot', () async {
    expect(await sync.applyEvents(2, [ticketEvent(20, 'k1', 'pending', epoch: 2)], 20), isFalse);
    expect(await tickets(), isEmpty);
    expect(await cursor(), 10);
  });
}
