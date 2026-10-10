import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/service_context.dart';

class StaffSummary {
  const StaffSummary({required this.id, required this.name, required this.role, required this.disabled});
  final String id;
  final String name;
  final StaffRole role;
  final bool disabled;

  static StaffSummary fromRow(StaffRow r) =>
      StaffSummary(id: r.id, name: r.name, role: StaffRole.parse(r.role), disabled: r.disabled);
}

/// Local PIN authentication, throttling, owner approvals and staff admin.
class AuthService {
  AuthService(this.ctx, {this.hasher = const PinHasher()});

  final ServiceContext ctx;
  final PinHasher hasher;

  AppDatabase get _db => ctx.db;

  /// Wrong PINs allowed before delays start.
  static const freeAttempts = 3;

  static Duration delayAfter(int failedAttempts) {
    if (failedAttempts < freeAttempts) return Duration.zero;
    final exp = min(failedAttempts - freeAttempts, 5);
    final seconds = min(30 * (1 << exp), 15 * 60);
    return Duration(seconds: seconds);
  }

  Stream<List<StaffSummary>> watchStaff({bool includeDisabled = false}) {
    final q = _db.select(_db.staff)
      ..orderBy([(s) => OrderingTerm(expression: s.role), (s) => OrderingTerm(expression: s.name)]);
    if (!includeDisabled) q.where((s) => s.disabled.equals(false));
    return q.watch().map((rows) => rows.map(StaffSummary.fromRow).toList());
  }

  Future<List<StaffSummary>> activeOwners() async {
    final rows = await (_db.select(
      _db.staff,
    )..where((s) => s.role.equals(StaffRole.owner.name) & s.disabled.equals(false))).get();
    return rows.map(StaffSummary.fromRow).toList();
  }

  Future<StaffRow> _staff(String id) async {
    final row = await (_db.select(_db.staff)..where((s) => s.id.equals(id))).getSingleOrNull();
    if (row == null) throw const NotFoundException('Staff member not found');
    return row;
  }

  /// Verifies [pin] for [staffId] with persistent throttling.
  Future<StaffRow> _checkPin(String staffId, String pin) async {
    final row = await _staff(staffId);
    if (row.disabled) throw const PermissionDeniedException('This account is disabled');
    final now = ctx.nowMs();
    if (row.lockedUntil != null && row.lockedUntil! > now) {
      final wait = Duration(milliseconds: row.lockedUntil! - now);
      throw LockedOutException('Too many wrong PINs. Try again in ${_human(wait)}.', wait);
    }
    final ok = await hasher.verify(pin, row.pinHash);
    if (ok) {
      if (row.failedAttempts != 0 || row.lockedUntil != null) {
        await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
          const StaffCompanion(failedAttempts: Value(0), lockedUntil: Value(null)),
        );
      }
      return row;
    }
    final failed = row.failedAttempts + 1;
    final delay = delayAfter(failed);
    await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
      StaffCompanion(
        failedAttempts: Value(failed),
        lockedUntil: Value(delay == Duration.zero ? null : now + delay.inMilliseconds),
      ),
    );
    await ctx.audit(null, 'auth.failed', entityType: 'staff', entityId: staffId, details: {'attempt': failed});
    if (delay > Duration.zero) {
      throw LockedOutException('Wrong PIN. Try again in ${_human(delay)}.', delay);
    }
    throw const ValidationException('Wrong PIN');
  }

  Future<Actor> login(String staffId, String pin) async {
    final row = await _checkPin(staffId, pin);
    final actor = Actor(staffId: row.id, name: row.name, role: StaffRole.parse(row.role));
    await ctx.audit(actor, 'auth.login', entityType: 'staff', entityId: row.id);
    return actor;
  }

  /// Owner enters their PIN to approve one sensitive action.
  Future<OwnerApproval> approveAsOwner(String ownerId, String pin) async {
    final row = await _checkPin(ownerId, pin);
    if (row.role != StaffRole.owner.name) {
      throw const PermissionDeniedException('Only an owner can approve this');
    }
    return OwnerApproval(ownerId: row.id, ownerName: row.name, issuedAt: ctx.now());
  }

  Future<String> createStaff(Actor actor, {required String name, required StaffRole role, required String pin}) async {
    actor.require(Permission.manageStaff);
    final n = requireText(name, 'Name', max: 60);
    PinHasher.validatePin(pin);
    final hash = await hasher.hash(pin);
    final id = ctx.ids.newId();
    final now = ctx.nowMs();
    await _db.transaction(() async {
      await _db
          .into(_db.staff)
          .insert(
            StaffCompanion.insert(id: id, name: n, role: role.name, pinHash: hash, createdAt: now, updatedAt: now),
          );
      await ctx.audit(
        actor,
        'staff.created',
        entityType: 'staff',
        entityId: id,
        details: {'name': n, 'role': role.name},
      );
    });
    return id;
  }

  Future<void> updateStaff(Actor actor, String staffId, {String? name, StaffRole? role, bool? disabled}) async {
    actor.require(Permission.manageStaff);
    await _db.transaction(() async {
      final before = await _staff(staffId);
      final newRole = role?.name ?? before.role;
      final newDisabled = disabled ?? before.disabled;
      final losingOwner =
          before.role == StaffRole.owner.name && !before.disabled && (newRole != StaffRole.owner.name || newDisabled);
      if (losingOwner && (await activeOwners()).length <= 1) {
        throw const ConflictException('Keep at least one active owner account');
      }
      await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
        StaffCompanion(
          name: name == null ? const Value.absent() : Value(requireText(name, 'Name', max: 60)),
          role: Value(newRole),
          disabled: Value(newDisabled),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await ctx.audit(
        actor,
        'staff.updated',
        entityType: 'staff',
        entityId: staffId,
        details: {
          'before': {'name': before.name, 'role': before.role, 'disabled': before.disabled},
          'after': {'name': name ?? before.name, 'role': newRole, 'disabled': newDisabled},
        },
      );
    });
  }

  /// Owner sets someone's PIN (and clears any lockout).
  Future<void> resetPin(Actor actor, String staffId, String newPin) async {
    actor.require(Permission.manageStaff);
    await _setPin(staffId, newPin);
    await ctx.audit(actor, 'staff.pin_reset', entityType: 'staff', entityId: staffId);
  }

  /// Anyone can change their own PIN by proving the current one.
  Future<void> changeOwnPin(Actor actor, String currentPin, String newPin) async {
    await _checkPin(actor.staffId, currentPin);
    await _setPin(actor.staffId, newPin);
    await ctx.audit(actor, 'staff.pin_changed', entityType: 'staff', entityId: actor.staffId);
  }

  Future<void> _setPin(String staffId, String newPin) async {
    PinHasher.validatePin(newPin);
    await _staff(staffId);
    final hash = await hasher.hash(newPin);
    await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
      StaffCompanion(
        pinHash: Value(hash),
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(ctx.nowMs()),
      ),
    );
  }

  /// Offline owner recovery with the one-time code shown at setup. Returns a
  /// fresh recovery code (the used one stops working).
  Future<String> resetOwnerPinWithRecoveryCode(String ownerId, String code, String newPin) async {
    final owner = await _staff(ownerId);
    if (owner.role != StaffRole.owner.name) {
      throw const ValidationException('Recovery codes can only reset an owner PIN');
    }
    PinHasher.validatePin(newPin);
    final now = ctx.nowMs();
    if (owner.lockedUntil != null && owner.lockedUntil! > now) {
      final wait = Duration(milliseconds: owner.lockedUntil! - now);
      throw LockedOutException('Too many attempts. Try again in ${_human(wait)}.', wait);
    }
    final candidates = await (_db.select(_db.ownerRecovery)..where((r) => r.usedAt.isNull())).get();
    final normalized = PinHasher.normalizeRecoveryCode(code);
    OwnerRecoveryRow? match;
    for (final c in candidates) {
      if (await hasher.verify(normalized, c.codeHash)) {
        match = c;
        break;
      }
    }
    if (match == null) {
      final failed = owner.failedAttempts + 1;
      final delay = delayAfter(failed);
      await (_db.update(_db.staff)..where((s) => s.id.equals(ownerId))).write(
        StaffCompanion(
          failedAttempts: Value(failed),
          lockedUntil: Value(delay == Duration.zero ? null : now + delay.inMilliseconds),
        ),
      );
      await ctx.audit(null, 'auth.recovery_failed', entityType: 'staff', entityId: ownerId);
      throw const ValidationException('That recovery code is not valid');
    }
    final newCode = PinHasher.newRecoveryCode();
    final newHash = await hasher.hash(PinHasher.normalizeRecoveryCode(newCode));
    final pinHash = await hasher.hash(newPin);
    final used = match;
    await _db.transaction(() async {
      await (_db.update(
        _db.ownerRecovery,
      )..where((r) => r.id.equals(used.id))).write(OwnerRecoveryCompanion(usedAt: Value(now)));
      await _db
          .into(_db.ownerRecovery)
          .insert(
            OwnerRecoveryCompanion.insert(
              id: ctx.ids.newId(),
              codeHash: newHash,
              createdBy: Value(ownerId),
              createdAt: now,
            ),
          );
      await (_db.update(_db.staff)..where((s) => s.id.equals(ownerId))).write(
        StaffCompanion(
          pinHash: Value(pinHash),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
          disabled: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await ctx.audit(null, 'auth.owner_pin_recovered', entityType: 'staff', entityId: ownerId);
    });
    return newCode;
  }

  /// Invalidates existing recovery codes and returns a new one.
  Future<String> regenerateRecoveryCode(Actor actor) async {
    if (!actor.isOwner) throw const PermissionDeniedException('Only an owner can create a recovery code');
    final code = PinHasher.newRecoveryCode();
    final hash = await hasher.hash(PinHasher.normalizeRecoveryCode(code));
    final now = ctx.nowMs();
    await _db.transaction(() async {
      await (_db.update(
        _db.ownerRecovery,
      )..where((r) => r.usedAt.isNull())).write(OwnerRecoveryCompanion(usedAt: Value(now)));
      await _db
          .into(_db.ownerRecovery)
          .insert(
            OwnerRecoveryCompanion.insert(
              id: ctx.ids.newId(),
              codeHash: hash,
              createdBy: Value(actor.staffId),
              createdAt: now,
            ),
          );
      await ctx.audit(actor, 'auth.recovery_code_regenerated');
    });
    return code;
  }

  static String _human(Duration d) {
    if (d.inSeconds < 60) return '${max(1, d.inSeconds)} s';
    final m = (d.inSeconds / 60).ceil();
    return '$m min';
  }
}
