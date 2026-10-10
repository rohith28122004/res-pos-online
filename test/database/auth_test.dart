import 'package:cafedesk/core/database/app_database.dart';
import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/security/password_hasher.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/features/auth/application/auth_service.dart';
import 'package:cafedesk/features/setup/application/setup_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  Future<StaffRow> row(String id) => (h.db.select(h.db.staff)..where((s) => s.id.equals(id))).getSingle();

  test('passwords are stored hashed with a salt, never in plain text', () async {
    final rows = await h.db.select(h.db.staff).get();
    for (final r in rows) {
      expect(r.passwordHash, startsWith(r'$argon2id$'));
      expect(r.passwordHash, isNot(contains(ownerPassword)));
      expect(r.pinHash, isEmpty, reason: 'no PINs since schema 3');
    }
    final a = await fastHasher.hash('owner-pass-1');
    final b = await fastHasher.hash('owner-pass-1');
    expect(a, isNot(b), reason: 'random salt');
    expect(await fastHasher.verify('owner-pass-1', a), isTrue);
    expect(await fastHasher.verify('owner-pass-2', a), isFalse);
  });

  test('weak passwords and bad emails are rejected', () {
    expect(() => PasswordHasher.validatePassword('short1'), throwsA(isA<ValidationException>()));
    expect(() => PasswordHasher.validatePassword('aaaaaaaaaa'), throwsA(isA<ValidationException>()));
    expect(() => PasswordHasher.validatePassword('        '), throwsA(isA<ValidationException>()));
    expect(() => PasswordHasher.validatePassword('x' * 129 + 'y'), throwsA(isA<ValidationException>()));
    expect(
      () => PasswordHasher.validatePassword('Asha@Cafe.in', email: 'asha@cafe.in'),
      throwsA(isA<ValidationException>()),
    );
    PasswordHasher.validatePassword('tea-and-toast');
    expect(PasswordHasher.normalizeEmail('  Asha@Cafe.IN '), 'asha@cafe.in');
    for (final bad in ['', 'asha', 'asha@', '@cafe.in', 'asha@cafe', 'a sha@cafe.in']) {
      expect(() => PasswordHasher.normalizeEmail(bad), throwsA(isA<ValidationException>()), reason: bad);
    }
  });

  test('sign in with email and password; wrong passwords are throttled persistently', () async {
    final actor = await h.auth.login('  CARA@test.cafe ', cashierPassword);
    expect(actor.staffId, h.cashier.staffId);
    expect(actor.role, StaffRole.cashier);
    expect(actor.mustChangePassword, isFalse);
    for (var i = 0; i < AuthService.freeAttempts - 1; i++) {
      await expectLater(h.auth.login(cashierEmail, 'wrong-password'), throwsA(isA<ValidationException>()));
    }
    await expectLater(h.auth.login(cashierEmail, 'wrong-password'), throwsA(isA<LockedOutException>()));
    // Even the right password waits until the delay passes.
    await expectLater(h.auth.login(cashierEmail, cashierPassword), throwsA(isA<LockedOutException>()));
    h.clock.advance(const Duration(seconds: 31));
    expect((await h.auth.login(cashierEmail, cashierPassword)).staffId, h.cashier.staffId);
    expect((await row(h.cashier.staffId)).failedAttempts, 0);
  });

  test('an unknown email gets the same message as a wrong password', () async {
    Future<String> message(Future<Object?> f) async {
      try {
        await f;
      } on ValidationException catch (e) {
        return e.message;
      }
      fail('expected a ValidationException');
    }

    final unknown = await message(h.auth.login('nobody@test.cafe', cashierPassword));
    final wrong = await message(h.auth.login(cashierEmail, 'not-the-password'));
    expect(unknown, wrong);
  });

  test('delays grow and are capped', () {
    expect(AuthService.delayAfter(2), Duration.zero);
    expect(AuthService.delayAfter(3), const Duration(seconds: 30));
    expect(AuthService.delayAfter(4), const Duration(seconds: 60));
    expect(AuthService.delayAfter(50), const Duration(minutes: 15));
  });

  test('owner approvals expire and must come from an active owner', () async {
    final approval = await h.approval();
    await h.ctx.verifyApproval(approval, 'test');
    h.clock.advance(const Duration(minutes: 6));
    await expectLater(h.ctx.verifyApproval(approval, 'test'), throwsA(isA<ApprovalRequiredException>()));
    await expectLater(
      h.auth.approveAsOwner(h.cashier.staffId, cashierPassword),
      throwsA(isA<PermissionDeniedException>()),
    );
    await expectLater(h.auth.approveAsOwner(h.owner.staffId, 'wrong-password'), throwsA(isA<ValidationException>()));
  });

  test('owner creates an account; the person must choose their own password first', () async {
    final id = await h.auth.createStaff(
      h.owner,
      name: 'Asha',
      email: 'Asha@Test.Cafe',
      role: StaffRole.cashier,
      password: 'starting-pass',
    );
    final first = await h.auth.login('asha@test.cafe', 'starting-pass');
    expect(first.staffId, id);
    expect(first.mustChangePassword, isTrue);
    // The new password must differ from the one the owner chose.
    await expectLater(h.auth.chooseOwnPassword(first, 'starting-pass'), throwsA(isA<ValidationException>()));
    await h.auth.chooseOwnPassword(first, 'my-own-secret');
    // Only once: afterwards the current password is required.
    await expectLater(h.auth.chooseOwnPassword(first, 'another-secret'), throwsA(isA<ConflictException>()));
    await expectLater(h.auth.login('asha@test.cafe', 'starting-pass'), throwsA(isA<ValidationException>()));
    final again = await h.auth.login('asha@test.cafe', 'my-own-secret');
    expect(again.mustChangePassword, isFalse);
    // Disabled after signing in: cannot set a password any more.
    final bo = await h.auth.createStaff(
      h.owner,
      name: 'Bo',
      email: 'bo@test.cafe',
      role: StaffRole.kitchen,
      password: 'starting-pass',
    );
    final boActor = await h.auth.login('bo@test.cafe', 'starting-pass');
    await h.auth.updateStaff(h.owner, bo, disabled: true);
    await expectLater(h.auth.chooseOwnPassword(boActor, 'bo-own-secret'), throwsA(isA<PermissionDeniedException>()));
  });

  test('emails are unique, case-insensitively', () async {
    await expectLater(
      h.auth.createStaff(h.owner, name: 'X', email: 'CARA@test.cafe', role: StaffRole.cashier, password: 'pass-word-1'),
      throwsA(isA<ConflictException>()),
    );
    await expectLater(
      h.auth.updateStaff(h.owner, h.kitchen.staffId, email: cashierEmail),
      throwsA(isA<ConflictException>()),
    );
    await h.auth.updateStaff(h.owner, h.kitchen.staffId, email: 'Kitchen@Test.Cafe');
    expect((await row(h.kitchen.staffId)).email, 'kitchen@test.cafe');
  });

  test('owner resets a password: lockout cleared, change required; own reset is not', () async {
    for (var i = 0; i < AuthService.freeAttempts; i++) {
      await expectLater(h.auth.login(cashierEmail, 'wrong-password'), throwsA(isA<AppException>()));
    }
    await h.auth.resetPassword(h.owner, h.cashier.staffId, 'temp-pass-99');
    final cashier = await h.auth.login(cashierEmail, 'temp-pass-99');
    expect(cashier.mustChangePassword, isTrue);
    await h.auth.resetPassword(h.owner, h.owner.staffId, 'owner-pass-2');
    expect((await h.auth.login(ownerEmail, 'owner-pass-2')).mustChangePassword, isFalse);
    await expectLater(
      h.auth.resetPassword(h.cashier, h.owner.staffId, 'hijack-pass'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('change own password needs the current one', () async {
    await expectLater(
      h.auth.changeOwnPassword(h.cashier, 'wrong-password', 'new-pass-123'),
      throwsA(isA<ValidationException>()),
    );
    await h.auth.changeOwnPassword(h.cashier, cashierPassword, 'new-pass-123');
    expect((await h.auth.login(cashierEmail, 'new-pass-123')).staffId, h.cashier.staffId);
  });

  test('the last active owner cannot be disabled or demoted', () async {
    await expectLater(h.auth.updateStaff(h.owner, h.owner.staffId, disabled: true), throwsA(isA<ConflictException>()));
    await expectLater(
      h.auth.updateStaff(h.owner, h.owner.staffId, role: StaffRole.cashier),
      throwsA(isA<ConflictException>()),
    );
    final second = await h.auth.createStaff(
      h.owner,
      name: 'Second Owner',
      email: 'second@test.cafe',
      role: StaffRole.owner,
      password: 'second-pass',
    );
    await h.auth.updateStaff(h.owner, h.owner.staffId, disabled: true);
    await expectLater(h.auth.login(ownerEmail, ownerPassword), throwsA(isA<PermissionDeniedException>()));
    expect((await h.auth.activeOwners()).single.id, second);
  });

  test('only owners create accounts', () async {
    await expectLater(
      h.auth.createStaff(h.cashier, name: 'X', email: 'x@test.cafe', role: StaffRole.owner, password: 'pass-word-1'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('offline owner recovery with the one-time code', () async {
    // Regenerating invalidates the setup code and returns a fresh one.
    final code = await h.auth.regenerateRecoveryCode(h.owner);
    await expectLater(
      h.auth.resetOwnerPasswordWithRecoveryCode(h.owner.staffId, 'WRONG-CODE-0000-0000', 'recovered-1'),
      throwsA(isA<ValidationException>()),
    );
    final next = await h.auth.resetOwnerPasswordWithRecoveryCode(h.owner.staffId, code.toLowerCase(), 'recovered-1');
    expect(next, isNot(code));
    expect((await h.auth.login(ownerEmail, 'recovered-1')).isOwner, isTrue);
    // A used code stops working.
    await expectLater(
      h.auth.resetOwnerPasswordWithRecoveryCode(h.owner.staffId, code, 'recovered-2'),
      throwsA(isA<AppException>()),
    );
    // Only owners can create codes.
    await expectLater(h.auth.regenerateRecoveryCode(h.cashier), throwsA(isA<PermissionDeniedException>()));
  });

  test('an owner from before email sign-in gets an email through recovery', () async {
    // Simulate a schema-2 account: PIN only, no email or password.
    await (h.db.update(h.db.staff)..where((s) => s.id.equals(h.owner.staffId))).write(
      const StaffCompanion(email: Value(null), passwordHash: Value(null), pinHash: Value(r'$argon2id$old')),
    );
    await expectLater(h.auth.login(ownerEmail, ownerPassword), throwsA(isA<ValidationException>()));
    final code = await h.auth.regenerateRecoveryCode(h.owner);
    await expectLater(
      h.auth.resetOwnerPasswordWithRecoveryCode(h.owner.staffId, code, 'recovered-1'),
      throwsA(isA<ValidationException>()),
      reason: 'an email is needed',
    );
    await h.auth.resetOwnerPasswordWithRecoveryCode(h.owner.staffId, code, 'recovered-1', email: 'Olivia@New.Cafe');
    expect((await h.auth.login('olivia@new.cafe', 'recovered-1')).isOwner, isTrue);
    expect((await row(h.owner.staffId)).pinHash, isEmpty);
  });

  test('setup cannot run twice and has no default credentials', () async {
    await expectLater(
      SetupService(h.ctx, hasher: fastHasher).completeSetup(
        const SetupInput(restaurantName: 'X', ownerName: 'Y', ownerEmail: 'y@test.cafe', ownerPassword: 'pass-word-1'),
      ),
      throwsA(isA<ConflictException>()),
    );
    expect(await h.count(h.db.staff), 3, reason: 'only the accounts the test created');
  });
}
