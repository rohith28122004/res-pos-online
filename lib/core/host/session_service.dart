import 'package:drift/drift.dart';

import '../../features/auth/application/auth_service.dart';
import '../database/app_database.dart';
import '../errors/app_exception.dart';
import '../protocol/canonical_json.dart';
import '../protocol/protocol.dart';
import '../protocol/session_token.dart';
import '../security/permissions.dart';
import '../service_context.dart';
import 'command_dispatcher.dart';
import 'host_keys.dart';

/// Staff roles allowed to sign in on each kind of device.
const deviceStaffRoles = {
  DeviceRole.waiter: {StaffRole.owner, StaffRole.cashier, StaffRole.waiter},
  DeviceRole.kitchen: {StaffRole.owner, StaffRole.cashier, StaffRole.kitchen},
};

class SignedIn {
  const SignedIn({required this.token, required this.expiresAt, required this.actor});
  final String token;
  final int expiresAt;
  final Actor actor;
}

/// Device credentials and staff sessions on the POS host. Every LAN request
/// goes through [authenticateDevice] and (except pairing and sign-in)
/// [authenticateSession]; the actor always comes from the live database rows.
class HostSessions {
  HostSessions(this.ctx, {AuthService? auth}) : auth = auth ?? AuthService(ctx);

  final ServiceContext ctx;
  final AuthService auth;

  AppDatabase get _db => ctx.db;

  static const lifetime = Duration(hours: 12);
  static const _touchEvery = Duration(minutes: 1);

  /// Checks `X-CafeDesk-Device: cdd1.<deviceId>.<secret>`.
  Future<PairedDeviceRow> authenticateDevice(String? header) async {
    final parts = header?.trim().split('.');
    if (parts == null || parts.length != 3 || parts[0] != 'cdd1') {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This device is not paired with this POS');
    }
    final hash = sha256Hex(header!.trim());
    final row = await (_db.select(_db.pairedDevices)..where((d) => d.credentialHash.equals(hash))).getSingleOrNull();
    if (row == null || row.id != parts[1]) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This device is not paired with this POS');
    }
    if (row.revokedAt != null) {
      throw const ProtocolException(ErrorCode.deviceRevoked, 'This device was removed from the POS. Pair it again.');
    }
    final now = ctx.nowMs();
    if (row.lastSeenAt == null || now - row.lastSeenAt! > _touchEvery.inMilliseconds) {
      await (_db.update(
        _db.pairedDevices,
      )..where((d) => d.id.equals(row.id))).write(PairedDevicesCompanion(lastSeenAt: Value(now)));
    }
    return row;
  }

  /// Email + password sign-in for a paired device (the password arrived
  /// sealed and was opened by the host).
  Future<SignedIn> signIn(
    PairedDeviceRow device,
    String email,
    String password,
    HostIdentityRow identity,
    HostKeys keys,
  ) async {
    final Actor actor;
    try {
      actor = await auth.login(email, password);
    } on LockedOutException catch (e) {
      throw ProtocolException(
        ErrorCode.rateLimited,
        e.message,
        details: {'retryAfterMs': e.retryAfter.inMilliseconds},
      );
    } on PermissionDeniedException catch (e) {
      throw ProtocolException(ErrorCode.staffDisabled, e.message);
    } on ValidationException catch (e) {
      throw ProtocolException(ErrorCode.unauthenticated, e.message);
    }
    if (actor.mustChangePassword) {
      throw const ProtocolException(
        ErrorCode.forbidden,
        'Sign in on the POS once to choose your own password, then sign in here.',
      );
    }
    if (!(deviceStaffRoles[device.role] ?? const {}).contains(actor.role)) {
      throw ProtocolException(
        ErrorCode.forbidden,
        '${actor.role.label} accounts cannot sign in on a ${device.role} device',
      );
    }
    final now = ctx.now();
    final expires = now.add(lifetime);
    final sid = ctx.ids.newId();
    await _db
        .into(_db.staffSessions)
        .insert(
          StaffSessionsCompanion.insert(
            id: sid,
            staffId: actor.staffId,
            deviceId: device.id,
            createdAt: now.millisecondsSinceEpoch,
            expiresAt: expires.millisecondsSinceEpoch,
            lastSeenAt: Value(now.millisecondsSinceEpoch),
          ),
        );
    await ctx.audit(actor, 'device.sign_in', entityType: 'device', entityId: device.id);
    final token = await SessionToken.sign(
      SessionClaims(
        sessionId: sid,
        restaurantId: identity.restaurantId,
        deviceId: device.id,
        staffId: actor.staffId,
        name: actor.name,
        role: actor.role.name,
        hostEpoch: identity.hostEpoch,
        issuedAt: now.millisecondsSinceEpoch ~/ 1000,
        expiresAt: expires.millisecondsSinceEpoch ~/ 1000,
      ),
      keys.signingKey,
    );
    return SignedIn(token: token, expiresAt: expires.millisecondsSinceEpoch, actor: actor);
  }

  /// Verifies `Authorization: Bearer cds1…` for [device] against the live
  /// session and staff rows.
  Future<RemoteCaller> authenticateSession(
    PairedDeviceRow device,
    String? authorization,
    HostIdentityRow identity,
  ) async {
    final a = authorization?.trim() ?? '';
    if (!a.startsWith('Bearer ')) throw const ProtocolException(ErrorCode.unauthenticated, 'Sign in first');
    final claims = await SessionToken.verify(a.substring(7).trim(), b64urlDecode(identity.signingPublicKey));
    final now = ctx.nowMs();
    if (claims.restaurantId != identity.restaurantId || claims.deviceId != device.id) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This sign-in belongs to another device');
    }
    if (claims.expiresAt * 1000 <= now) {
      throw const ProtocolException(ErrorCode.sessionExpired, 'Your sign-in has expired. Sign in again.');
    }
    final session = await (_db.select(
      _db.staffSessions,
    )..where((s) => s.id.equals(claims.sessionId))).getSingleOrNull();
    if (session == null ||
        session.revokedAt != null ||
        session.expiresAt <= now ||
        session.deviceId != device.id ||
        session.staffId != claims.staffId) {
      throw const ProtocolException(ErrorCode.sessionExpired, 'Your sign-in has ended. Sign in again.');
    }
    final staff = await (_db.select(_db.staff)..where((s) => s.id.equals(claims.staffId))).getSingleOrNull();
    if (staff == null || staff.disabled) {
      throw const ProtocolException(ErrorCode.staffDisabled, 'This account is disabled');
    }
    final role = StaffRole.parse(staff.role);
    if (role.name != claims.role || !(deviceStaffRoles[device.role] ?? const {}).contains(role)) {
      throw const ProtocolException(ErrorCode.sessionExpired, 'Your account changed. Sign in again.');
    }
    if (session.lastSeenAt == null || now - session.lastSeenAt! > _touchEvery.inMilliseconds) {
      await (_db.update(
        _db.staffSessions,
      )..where((s) => s.id.equals(session.id))).write(StaffSessionsCompanion(lastSeenAt: Value(now)));
    }
    return RemoteCaller(
      deviceId: device.id,
      deviceRole: device.role,
      actor: Actor(staffId: staff.id, name: staff.name, role: role),
      sessionId: session.id,
    );
  }

  Future<void> signOut(RemoteCaller caller) async {
    final now = ctx.nowMs();
    await _db.transaction(() async {
      await (_db.update(_db.staffSessions)..where((s) => s.id.equals(caller.sessionId))).write(
        StaffSessionsCompanion(revokedAt: Value(now), revokedReason: const Value('signed out')),
      );
      await ctx.outbox.emit(
        type: EventType.sessionRevoked,
        aggregateType: 'staff_session',
        aggregateId: caller.sessionId,
        payload: {'sid': caller.sessionId, 'staffId': caller.actor.staffId, 'revokedAt': now},
      );
    });
  }

  /// Owner approval from a phone (sealed `approve` request).
  Future<OwnerApproval> approve(String email, String password) async {
    try {
      return await auth.approveByEmail(email, password);
    } on LockedOutException catch (e) {
      throw ProtocolException(ErrorCode.rateLimited, e.message, details: {'retryAfterMs': e.retryAfter.inMilliseconds});
    } on PermissionDeniedException catch (e) {
      throw ProtocolException(ErrorCode.forbidden, e.message);
    } on ValidationException catch (e) {
      throw ProtocolException(ErrorCode.unauthenticated, e.message);
    }
  }
}
