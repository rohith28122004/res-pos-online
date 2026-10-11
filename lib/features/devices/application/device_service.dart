import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/host/command_dispatcher.dart';
import '../../../core/protocol/canonical_json.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';

/// What a phone needs to find and trust the POS: shown as a QR code (and as
/// text to copy) when the owner pairs a device.
class PairingInvite {
  const PairingInvite({
    required this.code,
    required this.role,
    required this.deviceName,
    required this.expiresAt,
    required this.payload,
  });

  final String code;
  final String role;
  final String deviceName;
  final int expiresAt;

  /// `cdpair1.<b64url(json)>`.
  final String payload;
}

/// Decoded pairing payload, used by the device.
class PairingPayload {
  const PairingPayload({
    required this.restaurantId,
    required this.restaurantName,
    required this.hostDeviceId,
    required this.addresses,
    required this.port,
    required this.certSha256,
    required this.code,
    required this.role,
    required this.expiresAt,
  });

  final String restaurantId;
  final String restaurantName;
  final String hostDeviceId;
  final List<String> addresses;
  final int port;
  final String certSha256;
  final String code;
  final String role;
  final int expiresAt;

  static const prefix = 'cdpair1.';

  String encode() =>
      prefix +
      b64url(
        utf8.encode(
          jsonEncode({
            'v': 1,
            'rid': restaurantId,
            'name': restaurantName,
            'hid': hostDeviceId,
            'addrs': addresses,
            'port': port,
            'fp': certSha256,
            'code': code,
            'role': role,
            'exp': expiresAt,
          }),
        ),
      );

  static PairingPayload parse(String text) {
    final t = text.trim();
    if (!t.startsWith(prefix)) throw const ValidationException('That is not a CaféDesk Online pairing code');
    try {
      final j = (jsonDecode(utf8.decode(b64urlDecode(t.substring(prefix.length)))) as Map).cast<String, Object?>();
      if (j['v'] != 1) throw const FormatException();
      final addrs = (j['addrs']! as List).cast<String>();
      final fp = j['fp']! as String;
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(fp) || addrs.isEmpty) throw const FormatException();
      return PairingPayload(
        restaurantId: j['rid']! as String,
        restaurantName: j['name']! as String,
        hostDeviceId: j['hid']! as String,
        addresses: addrs,
        port: j['port']! as int,
        certSha256: fp,
        code: j['code']! as String,
        role: j['role']! as String,
        expiresAt: j['exp']! as int,
      );
    } on ValidationException {
      rethrow;
    } on Object {
      throw const ValidationException('That pairing code is damaged. Show a new one on the POS.');
    }
  }
}

/// What the host returns to a device that redeemed a pairing code.
class PairingResult {
  const PairingResult({required this.deviceId, required this.credential, required this.role});
  final String deviceId;

  /// `cdd1.<deviceId>.<secret>` — returned once, stored only on the device.
  final String credential;
  final String role;
}

/// Pairing codes, paired devices and revocation, on the POS host.
class DeviceService {
  DeviceService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  static const pairingValidity = Duration(minutes: 10);
  static final _random = Random.secure();

  static String randomSecret([int bytes = 32]) => b64url(List<int>.generate(bytes, (_) => _random.nextInt(256)));

  static String credentialHash(String credential) => sha256Hex(credential);

  Stream<List<PairedDeviceRow>> watchDevices() =>
      (_db.select(_db.pairedDevices)..orderBy([
            (d) => OrderingTerm(expression: d.revokedAt.isNull(), mode: OrderingMode.desc),
            (d) => OrderingTerm(expression: d.createdAt, mode: OrderingMode.desc),
          ]))
          .watch();

  /// The host's IPv4 addresses on local networks (what phones connect to).
  static Future<List<String>> lanAddresses() async {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    return [
      for (final i in interfaces)
        for (final a in i.addresses)
          if (!a.isLoopback && !a.isLinkLocal) a.address,
    ];
  }

  /// Owner creates a single-use pairing code for one device and role.
  Future<PairingInvite> createInvite(
    Actor actor, {
    required String role,
    required String deviceName,
    required HostIdentityRow identity,
    required List<String> addresses,
  }) async {
    actor.require(Permission.manageDevices);
    if (!DeviceRole.all.contains(role)) throw const ValidationException('Choose waiter or kitchen');
    if (role == DeviceRole.kitchen && !(await ctx.settings()).kitchenEnabled) {
      throw const ConflictException(
        'The kitchen is switched off. Turn it on in Settings before adding a kitchen display.',
      );
    }
    final name = requireText(deviceName, 'Device name', max: 40);
    if (addresses.isEmpty) {
      throw const ConflictException('This PC is not connected to a network. Connect it to the café Wi-Fi first.');
    }
    final code = randomSecret(18);
    final now = ctx.nowMs();
    final expiresAt = now + pairingValidity.inMilliseconds;
    final settings = await ctx.settings();
    await _db.transaction(() async {
      await _db
          .into(_db.pairingCodes)
          .insert(
            PairingCodesCompanion.insert(
              id: ctx.ids.newId(),
              codeHash: sha256Hex(code),
              role: role,
              deviceName: name,
              createdBy: actor.staffId,
              createdAt: now,
              expiresAt: expiresAt,
            ),
          );
      await ctx.audit(actor, 'device.pairing_code_created', details: {'role': role, 'name': name});
    });
    final payload = PairingPayload(
      restaurantId: identity.restaurantId,
      restaurantName: settings.name,
      hostDeviceId: identity.hostDeviceId,
      addresses: addresses,
      port: identity.lanPort,
      certSha256: identity.tlsCertSha256,
      code: code,
      role: role,
      expiresAt: expiresAt,
    );
    return PairingInvite(code: code, role: role, deviceName: name, expiresAt: expiresAt, payload: payload.encode());
  }

  /// A device redeems a pairing code. Single use, before it expires. The
  /// device gets a fresh credential; only its hash is kept here.
  Future<PairingResult> redeem({
    required String code,
    required String deviceName,
    String? platform,
    String? appVersion,
  }) async {
    final hashOfCode = sha256Hex(code);
    final now = ctx.nowMs();
    return _db.transaction(() async {
      final row = await (_db.select(_db.pairingCodes)..where((c) => c.codeHash.equals(hashOfCode))).getSingleOrNull();
      if (row == null || row.cancelledAt != null) {
        throw const ProtocolException(ErrorCode.unauthenticated, 'That pairing code is not valid');
      }
      if (row.usedAt != null) {
        throw const ProtocolException(ErrorCode.unauthenticated, 'That pairing code was already used');
      }
      if (row.expiresAt <= now) {
        throw const ProtocolException(ErrorCode.unauthenticated, 'That pairing code has expired. Show a new one.');
      }
      final deviceId = ctx.ids.newId();
      final credential = 'cdd1.$deviceId.${randomSecret()}';
      final name = optionalText(deviceName, max: 40) ?? row.deviceName;
      final staff = await (_db.select(_db.staff)..where((s) => s.id.equals(row.createdBy))).getSingle();
      await _db
          .into(_db.pairedDevices)
          .insert(
            PairedDevicesCompanion.insert(
              id: deviceId,
              role: row.role,
              name: name,
              platform: Value(optionalText(platform, max: 40)),
              appVersion: Value(optionalText(appVersion, max: 40)),
              credentialHash: credentialHash(credential),
              createdAt: now,
              pairedBy: row.createdBy,
              pairedByName: staff.name,
              lastSeenAt: Value(now),
            ),
          );
      await (_db.update(_db.pairingCodes)..where((c) => c.id.equals(row.id))).write(
        PairingCodesCompanion(usedAt: Value(now), usedByDeviceId: Value(deviceId)),
      );
      await ctx.outbox.emit(
        type: EventType.devicePaired,
        aggregateType: 'device',
        aggregateId: deviceId,
        payload: {
          'deviceId': deviceId,
          'role': row.role,
          'name': name,
          'credentialHash': credentialHash(credential),
          'pairedAt': now,
        },
      );
      await ctx.audit(
        null,
        'device.paired',
        entityType: 'device',
        entityId: deviceId,
        details: {'role': row.role, 'name': name, 'pairedBy': staff.name},
      );
      return PairingResult(deviceId: deviceId, credential: credential, role: row.role);
    });
  }

  Future<void> cancelOpenInvites(Actor actor) async {
    actor.require(Permission.manageDevices);
    await (_db.update(_db.pairingCodes)..where((c) => c.usedAt.isNull() & c.cancelledAt.isNull())).write(
      PairingCodesCompanion(cancelledAt: Value(ctx.nowMs())),
    );
  }

  /// Revokes a device at once on this host (its sessions end too). The cloud
  /// learns about it when the event is uploaded.
  Future<void> revoke(Actor actor, String deviceId) async {
    actor.require(Permission.manageDevices);
    await _db.transaction(() async {
      final d = await (_db.select(_db.pairedDevices)..where((x) => x.id.equals(deviceId))).getSingleOrNull();
      if (d == null) throw const NotFoundException('Device not found');
      if (d.revokedAt != null) return;
      final now = ctx.nowMs();
      await (_db.update(_db.pairedDevices)..where((x) => x.id.equals(deviceId))).write(
        PairedDevicesCompanion(revokedAt: Value(now), revokedBy: Value(actor.staffId)),
      );
      final sessions = await (_db.select(
        _db.staffSessions,
      )..where((s) => s.deviceId.equals(deviceId) & s.revokedAt.isNull())).get();
      for (final s in sessions) {
        await (_db.update(_db.staffSessions)..where((x) => x.id.equals(s.id))).write(
          StaffSessionsCompanion(revokedAt: Value(now), revokedReason: const Value('device revoked')),
        );
        await ctx.outbox.emit(
          type: EventType.sessionRevoked,
          aggregateType: 'staff_session',
          aggregateId: s.id,
          payload: {'sid': s.id, 'staffId': s.staffId, 'revokedAt': now},
        );
      }
      await ctx.outbox.emit(
        type: EventType.deviceRevoked,
        aggregateType: 'device',
        aggregateId: deviceId,
        payload: {'deviceId': deviceId, 'revokedAt': now},
      );
      await ctx.audit(actor, 'device.revoked', entityType: 'device', entityId: deviceId, details: {'name': d.name});
    });
  }

  Future<void> rename(Actor actor, String deviceId, String name) async {
    actor.require(Permission.manageDevices);
    final n = requireText(name, 'Device name', max: 40);
    final count = await (_db.update(
      _db.pairedDevices,
    )..where((d) => d.id.equals(deviceId))).write(PairedDevicesCompanion(name: Value(n)));
    if (count == 0) throw const NotFoundException('Device not found');
  }
}
