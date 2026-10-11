import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../protocol/canonical_json.dart';
import '../protocol/protocol.dart';
import '../security/permissions.dart';
import '../security/secret_store.dart';
import '../service_context.dart';
import 'host_keys.dart';

/// The POS host's identity for connected devices: restaurant ID, host device
/// ID, epoch, certificate and keys. Created once, when the owner first turns
/// on connected mode.
class HostIdentityService {
  HostIdentityService(this.ctx, this.secrets);

  final ServiceContext ctx;
  final SecretStore secrets;

  AppDatabase get _db => ctx.db;

  Future<HostIdentityRow?> current() => _db.select(_db.hostIdentity).getSingleOrNull();

  /// Returns the identity and its keys, creating both on first use.
  Future<(HostIdentityRow, HostKeys)> ensure(Actor actor) async {
    actor.require(Permission.manageDevices);
    final existing = await current();
    if (existing != null) {
      final keys = await HostKeys.load(existing.hostDeviceId, existing.tlsCertPem, secrets);
      if (keys == null) {
        throw const ConflictException(
          'This POS has connection settings but its security keys are missing (for example after restoring a '
          'backup on another computer). Reset device connections to continue.',
        );
      }
      return (existing, keys);
    }
    final hostDeviceId = ctx.ids.newId();
    final keys = await HostKeys.generate(hostDeviceId, secrets);
    final now = ctx.nowMs();
    await _db.transaction(() async {
      await _db
          .into(_db.hostIdentity)
          .insert(
            HostIdentityCompanion.insert(
              singleton: const Value(1),
              restaurantId: ctx.ids.newId(),
              hostDeviceId: hostDeviceId,
              hostEpoch: 1,
              epochStartSequence: 1,
              epochStartedAt: now,
              tlsCertPem: keys.tlsCertPem,
              tlsCertSha256: keys.tlsCertSha256,
              signingPublicKey: _b64(keys.signingPublicKey),
              sealPublicKey: _b64(keys.sealPublicKey),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await ctx.audit(actor, 'connected.host_created', entityType: 'host', entityId: hostDeviceId);
    });
    return ((await current())!, keys);
  }

  /// Keys for an existing identity, or null if they are missing.
  Future<HostKeys?> keys(HostIdentityRow row) => HostKeys.load(row.hostDeviceId, row.tlsCertPem, secrets);

  Future<void> setLan(Actor actor, {required bool enabled, int? port}) async {
    actor.require(Permission.manageDevices);
    if (port != null && (port < 1024 || port > 65535)) {
      throw const ValidationException('Port must be between 1024 and 65535');
    }
    await (_db.update(_db.hostIdentity)..where((h) => h.singleton.equals(1))).write(
      HostIdentityCompanion(
        lanEnabled: Value(enabled),
        lanPort: port == null ? const Value.absent() : Value(port),
        updatedAt: Value(ctx.nowMs()),
      ),
    );
    await ctx.audit(actor, enabled ? 'connected.lan_on' : 'connected.lan_off', details: {'port': ?port});
  }

  /// New certificate and keys; every paired device must be paired again (its
  /// pinned certificate no longer matches) and the cloud connection must be
  /// set up again. Used when the keys are missing or the owner wants a clean
  /// start.
  Future<HostKeys> resetConnections(Actor actor) async {
    actor.require(Permission.manageDevices);
    final row = await current();
    if (row == null) throw const ConflictException('Connected mode has not been set up');
    await HostKeys.forget(row.hostDeviceId, secrets);
    final keys = await HostKeys.generate(row.hostDeviceId, secrets);
    final now = ctx.nowMs();
    await _db.transaction(() async {
      await (_db.update(_db.hostIdentity)..where((h) => h.singleton.equals(1))).write(
        HostIdentityCompanion(
          tlsCertPem: Value(keys.tlsCertPem),
          tlsCertSha256: Value(keys.tlsCertSha256),
          signingPublicKey: Value(_b64(keys.signingPublicKey)),
          sealPublicKey: Value(_b64(keys.sealPublicKey)),
          cloudUrl: const Value(null),
          cloudEnrolledAt: const Value(null),
          updatedAt: Value(now),
        ),
      );
      final devices = await (_db.select(_db.pairedDevices)..where((d) => d.revokedAt.isNull())).get();
      for (final d in devices) {
        await (_db.update(_db.pairedDevices)..where((x) => x.id.equals(d.id))).write(
          PairedDevicesCompanion(revokedAt: Value(now), revokedBy: Value(actor.staffId)),
        );
        await ctx.outbox.emit(
          type: EventType.deviceRevoked,
          aggregateType: 'device',
          aggregateId: d.id,
          payload: {'deviceId': d.id, 'revokedAt': now},
        );
      }
      final sessions = await (_db.select(_db.staffSessions)..where((s) => s.revokedAt.isNull())).get();
      for (final s in sessions) {
        await (_db.update(_db.staffSessions)..where((x) => x.id.equals(s.id))).write(
          StaffSessionsCompanion(revokedAt: Value(now), revokedReason: const Value('connections reset')),
        );
        await ctx.outbox.emit(
          type: EventType.sessionRevoked,
          aggregateType: 'staff_session',
          aggregateId: s.id,
          payload: {'sid': s.id, 'staffId': s.staffId, 'revokedAt': now},
        );
      }
      await (_db.update(_db.pairingCodes)..where((c) => c.usedAt.isNull() & c.cancelledAt.isNull())).write(
        PairingCodesCompanion(cancelledAt: Value(now)),
      );
      await ctx.audit(actor, 'connected.reset', details: {'devicesRevoked': devices.length});
    });
    return keys;
  }

  static String _b64(List<int> bytes) => b64url(bytes);
}
