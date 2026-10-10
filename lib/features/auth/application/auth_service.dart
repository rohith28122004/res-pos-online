import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/db_errors.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/password_hasher.dart';
import '../../../core/security/permissions.dart';
import '../../../core/protocol/protocol.dart';
import '../../../core/service_context.dart';

class StaffSummary {
  const StaffSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.disabled,
    this.email,
    this.hasPassword = false,
    this.mustChangePassword = false,
  });
  final String id;
  final String name;
  final StaffRole role;
  final bool disabled;
  final String? email;
  final bool hasPassword;
  final bool mustChangePassword;

  /// Has an email and a password, so it can sign in.
  bool get canSignIn => email != null && hasPassword;

  static StaffSummary fromRow(StaffRow r) => StaffSummary(
    id: r.id,
    name: r.name,
    role: StaffRole.parse(r.role),
    disabled: r.disabled,
    email: r.email,
    hasPassword: r.passwordHash != null,
    mustChangePassword: r.mustChangePassword,
  );
}

/// Local email + password sign-in, throttling, owner approvals and staff
/// accounts. Only an owner creates accounts; nobody signs themselves up.
class AuthService {
  AuthService(this.ctx, {this.hasher = const PasswordHasher()});

  final ServiceContext ctx;
  final PasswordHasher hasher;

  AppDatabase get _db => ctx.db;

  /// Wrong passwords allowed before delays start.
  static const freeAttempts = 3;

  static const _wrongLogin = 'Email or password is wrong';

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

  Future<void> _ensureEmailFree(String email, {String? exceptId}) async {
    final q = _db.select(_db.staff)..where((s) => s.email.equals(email));
    if (exceptId != null) q.where((s) => s.id.equals(exceptId).not());
    if (await q.getSingleOrNull() != null) {
      throw ConflictException('Another account already uses $email');
    }
  }

  /// Verifies [password] for [row] with persistent throttling.
  Future<void> _checkPassword(StaffRow row, String password, {required String wrong}) async {
    if (row.disabled) throw const PermissionDeniedException('This account is disabled');
    final now = ctx.nowMs();
    if (row.lockedUntil != null && row.lockedUntil! > now) {
      final wait = Duration(milliseconds: row.lockedUntil! - now);
      throw LockedOutException('Too many wrong passwords. Try again in ${_human(wait)}.', wait);
    }
    final hash = row.passwordHash;
    if (hash != null && await hasher.verify(password, hash)) {
      if (row.failedAttempts != 0 || row.lockedUntil != null) {
        await (_db.update(_db.staff)..where((s) => s.id.equals(row.id))).write(
          const StaffCompanion(failedAttempts: Value(0), lockedUntil: Value(null)),
        );
      }
      return;
    }
    final failed = row.failedAttempts + 1;
    final delay = delayAfter(failed);
    await (_db.update(_db.staff)..where((s) => s.id.equals(row.id))).write(
      StaffCompanion(
        failedAttempts: Value(failed),
        lockedUntil: Value(delay == Duration.zero ? null : now + delay.inMilliseconds),
      ),
    );
    await ctx.audit(null, 'auth.failed', entityType: 'staff', entityId: row.id, details: {'attempt': failed});
    if (delay > Duration.zero) {
      throw LockedOutException('$wrong. Try again in ${_human(delay)}.', delay);
    }
    throw ValidationException(wrong);
  }

  Future<Actor> login(String email, String password) async {
    final e = email.trim().toLowerCase();
    final row = e.isEmpty ? null : await (_db.select(_db.staff)..where((s) => s.email.equals(e))).getSingleOrNull();
    if (row == null) throw const ValidationException(_wrongLogin);
    if (row.passwordHash == null && !row.disabled) {
      throw const ValidationException(
        'This account has no password yet. An owner can set one in Staff; owners can use their recovery code.',
      );
    }
    await _checkPassword(row, password, wrong: _wrongLogin);
    final actor = Actor(
      staffId: row.id,
      name: row.name,
      role: StaffRole.parse(row.role),
      mustChangePassword: row.mustChangePassword,
    );
    await ctx.audit(actor, 'auth.login', entityType: 'staff', entityId: row.id);
    return actor;
  }

  /// Owner enters their password to approve one sensitive action.
  Future<OwnerApproval> approveAsOwner(String ownerId, String password) async {
    final row = await _staff(ownerId);
    if (row.role != StaffRole.owner.name) {
      throw const PermissionDeniedException('Only an owner can approve this');
    }
    await _checkPassword(row, password, wrong: 'Wrong password');
    return OwnerApproval(ownerId: row.id, ownerName: row.name, issuedAt: ctx.now());
  }

  /// Owner creates an account. By default the person must choose their own
  /// password at their first sign-in.
  Future<String> createStaff(
    Actor actor, {
    required String name,
    required String email,
    required StaffRole role,
    required String password,
    bool mustChangePassword = true,
  }) async {
    actor.require(Permission.manageStaff);
    final n = requireText(name, 'Name', max: 60);
    final e = PasswordHasher.normalizeEmail(email);
    PasswordHasher.validatePassword(password, email: e);
    final hash = await hasher.hash(password);
    final id = ctx.ids.newId();
    final now = ctx.nowMs();
    try {
      await _db.transaction(() async {
        await _ensureEmailFree(e);
        await _db
            .into(_db.staff)
            .insert(
              StaffCompanion.insert(
                id: id,
                name: n,
                role: role.name,
                email: Value(e),
                passwordHash: Value(hash),
                mustChangePassword: Value(mustChangePassword),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await ctx.audit(
          actor,
          'staff.created',
          entityType: 'staff',
          entityId: id,
          details: {'name': n, 'email': e, 'role': role.name},
        );
      });
    } on Object catch (err) {
      if (isUniqueViolation(err)) throw ConflictException('Another account already uses $e');
      rethrow;
    }
    return id;
  }

  Future<void> updateStaff(
    Actor actor,
    String staffId, {
    String? name,
    String? email,
    StaffRole? role,
    bool? disabled,
  }) async {
    actor.require(Permission.manageStaff);
    final newEmail = email == null ? null : PasswordHasher.normalizeEmail(email);
    try {
      await _db.transaction(() async {
        final before = await _staff(staffId);
        final newRole = role?.name ?? before.role;
        final newDisabled = disabled ?? before.disabled;
        final losingOwner =
            before.role == StaffRole.owner.name && !before.disabled && (newRole != StaffRole.owner.name || newDisabled);
        if (losingOwner && (await activeOwners()).length <= 1) {
          throw const ConflictException('Keep at least one active owner account');
        }
        if (newEmail != null) await _ensureEmailFree(newEmail, exceptId: staffId);
        await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
          StaffCompanion(
            name: name == null ? const Value.absent() : Value(requireText(name, 'Name', max: 60)),
            email: newEmail == null ? const Value.absent() : Value(newEmail),
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
            'before': {'name': before.name, 'email': before.email, 'role': before.role, 'disabled': before.disabled},
            'after': {
              'name': name ?? before.name,
              'email': newEmail ?? before.email,
              'role': newRole,
              'disabled': newDisabled,
            },
          },
        );
        if (newRole != before.role || newDisabled != before.disabled) {
          await ctx.outbox.emit(
            type: EventType.staffAccessChanged,
            aggregateType: 'staff',
            aggregateId: staffId,
            payload: {'staffId': staffId, 'role': newRole, 'disabled': newDisabled},
          );
          await revokeSessionsOf(staffId, newDisabled ? 'account disabled' : 'role changed');
        }
      });
    } on Object catch (err) {
      if (isUniqueViolation(err)) throw ConflictException('Another account already uses $newEmail');
      rethrow;
    }
  }

  /// Owner sets someone's password (and clears any lockout). They must choose
  /// their own at the next sign-in, unless the owner is resetting their own.
  Future<void> resetPassword(Actor actor, String staffId, String newPassword) async {
    actor.require(Permission.manageStaff);
    final row = await _staff(staffId);
    PasswordHasher.validatePassword(newPassword, email: row.email);
    await _db.transaction(() async {
      await _setPassword(staffId, newPassword, mustChange: staffId != actor.staffId);
      await ctx.audit(actor, 'staff.password_reset', entityType: 'staff', entityId: staffId);
      await revokeSessionsOf(staffId, 'password reset');
    });
  }

  /// Ends every live device session of [staffId] (paired phones must sign in
  /// again). Call inside a transaction.
  Future<void> revokeSessionsOf(String staffId, String reason) async {
    final live = await (_db.select(
      _db.staffSessions,
    )..where((s) => s.staffId.equals(staffId) & s.revokedAt.isNull())).get();
    final now = ctx.nowMs();
    for (final s in live) {
      await (_db.update(_db.staffSessions)..where((x) => x.id.equals(s.id))).write(
        StaffSessionsCompanion(revokedAt: Value(now), revokedReason: Value(reason)),
      );
      await ctx.outbox.emit(
        type: EventType.sessionRevoked,
        aggregateType: 'staff_session',
        aggregateId: s.id,
        payload: {'sid': s.id, 'staffId': staffId, 'revokedAt': now},
      );
    }
  }

  /// Anyone can change their own password by proving the current one.
  Future<void> changeOwnPassword(Actor actor, String currentPassword, String newPassword) async {
    final row = await _staff(actor.staffId);
    PasswordHasher.validatePassword(newPassword, email: row.email);
    if (newPassword == currentPassword) {
      throw const ValidationException('Choose a password different from the current one');
    }
    await _checkPassword(row, currentPassword, wrong: 'Current password is wrong');
    await _setPassword(actor.staffId, newPassword, mustChange: false);
    await ctx.audit(actor, 'staff.password_changed', entityType: 'staff', entityId: actor.staffId);
  }

  /// Right after signing in with a password the owner chose: the person picks
  /// their own. Only allowed while the account is flagged for it.
  Future<void> chooseOwnPassword(Actor actor, String newPassword) async {
    final row = await _staff(actor.staffId);
    if (row.disabled) throw const PermissionDeniedException('This account is disabled');
    if (!row.mustChangePassword) {
      throw const ConflictException('Your password was already changed. Use "Change my password" instead.');
    }
    PasswordHasher.validatePassword(newPassword, email: row.email);
    if (row.passwordHash != null && await hasher.verify(newPassword, row.passwordHash!)) {
      throw const ValidationException('Choose a password different from the one you were given');
    }
    await _setPassword(actor.staffId, newPassword, mustChange: false);
    await ctx.audit(actor, 'staff.password_changed', entityType: 'staff', entityId: actor.staffId);
  }

  Future<void> _setPassword(String staffId, String newPassword, {required bool mustChange}) async {
    final hash = await hasher.hash(newPassword);
    await (_db.update(_db.staff)..where((s) => s.id.equals(staffId))).write(
      StaffCompanion(
        passwordHash: Value(hash),
        mustChangePassword: Value(mustChange),
        pinHash: const Value(''),
        failedAttempts: const Value(0),
        lockedUntil: const Value(null),
        updatedAt: Value(ctx.nowMs()),
      ),
    );
  }

  /// Offline owner recovery with the one-time code shown at setup. Also gives
  /// an owner from before email sign-in their [email]. Returns a fresh
  /// recovery code (the used one stops working).
  Future<String> resetOwnerPasswordWithRecoveryCode(
    String ownerId,
    String code,
    String newPassword, {
    String? email,
  }) async {
    final owner = await _staff(ownerId);
    if (owner.role != StaffRole.owner.name) {
      throw const ValidationException('Recovery codes can only reset an owner password');
    }
    final newEmail = (email == null || email.trim().isEmpty) ? owner.email : PasswordHasher.normalizeEmail(email);
    if (newEmail == null) throw const ValidationException('Enter an email for this owner');
    PasswordHasher.validatePassword(newPassword, email: newEmail);
    await _ensureEmailFree(newEmail, exceptId: ownerId);
    final now = ctx.nowMs();
    if (owner.lockedUntil != null && owner.lockedUntil! > now) {
      final wait = Duration(milliseconds: owner.lockedUntil! - now);
      throw LockedOutException('Too many attempts. Try again in ${_human(wait)}.', wait);
    }
    final candidates = await (_db.select(_db.ownerRecovery)..where((r) => r.usedAt.isNull())).get();
    final normalized = PasswordHasher.normalizeRecoveryCode(code);
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
    final newCode = PasswordHasher.newRecoveryCode();
    final newHash = await hasher.hash(PasswordHasher.normalizeRecoveryCode(newCode));
    final passwordHash = await hasher.hash(newPassword);
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
          email: Value(newEmail),
          passwordHash: Value(passwordHash),
          mustChangePassword: const Value(false),
          pinHash: const Value(''),
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
          disabled: const Value(false),
          updatedAt: Value(now),
        ),
      );
      await ctx.audit(null, 'auth.owner_password_recovered', entityType: 'staff', entityId: ownerId);
    });
    return newCode;
  }

  /// Invalidates existing recovery codes and returns a new one.
  Future<String> regenerateRecoveryCode(Actor actor) async {
    if (!actor.isOwner) throw const PermissionDeniedException('Only an owner can create a recovery code');
    final code = PasswordHasher.newRecoveryCode();
    final hash = await hasher.hash(PasswordHasher.normalizeRecoveryCode(code));
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
