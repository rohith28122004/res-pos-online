import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/security/permissions.dart';
import 'package:cafedesk/core/security/pin_hasher.dart';
import 'package:cafedesk/features/auth/application/auth_service.dart';
import 'package:cafedesk/features/setup/application/setup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  late Harness h;
  setUp(() async => h = await Harness.create());
  tearDown(() => h.dispose());

  test('PINs are stored hashed with a salt, never in plain text', () async {
    final rows = await h.db.select(h.db.staff).get();
    for (final r in rows) {
      expect(r.pinHash, startsWith(r'$argon2id$'));
      expect(r.pinHash, isNot(contains(ownerPin)));
    }
    final a = await fastHasher.hash('2580');
    final b = await fastHasher.hash('2580');
    expect(a, isNot(b), reason: 'random salt');
    expect(await fastHasher.verify('2580', a), isTrue);
    expect(await fastHasher.verify('2581', a), isFalse);
  });

  test('weak PINs are rejected', () {
    expect(() => PinHasher.validatePin('1234'), throwsA(isA<ValidationException>()));
    expect(() => PinHasher.validatePin('1111'), throwsA(isA<ValidationException>()));
    expect(() => PinHasher.validatePin('12a4'), throwsA(isA<ValidationException>()));
    expect(() => PinHasher.validatePin('123'), throwsA(isA<ValidationException>()));
    PinHasher.validatePin('4826');
  });

  test('login works and wrong PINs are throttled persistently', () async {
    final actor = await h.auth.login(h.cashier.staffId, cashierPin);
    expect(actor.role, StaffRole.cashier);
    for (var i = 0; i < AuthService.freeAttempts - 1; i++) {
      await expectLater(h.auth.login(h.cashier.staffId, '0000'), throwsA(isA<ValidationException>()));
    }
    await expectLater(h.auth.login(h.cashier.staffId, '0000'), throwsA(isA<LockedOutException>()));
    // Even the right PIN waits until the delay passes.
    await expectLater(h.auth.login(h.cashier.staffId, cashierPin), throwsA(isA<LockedOutException>()));
    h.clock.advance(const Duration(seconds: 31));
    expect((await h.auth.login(h.cashier.staffId, cashierPin)).staffId, h.cashier.staffId);
    final row = await (h.db.select(h.db.staff)..where((s) => s.id.equals(h.cashier.staffId))).getSingle();
    expect(row.failedAttempts, 0);
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
    await expectLater(h.auth.approveAsOwner(h.cashier.staffId, cashierPin), throwsA(isA<PermissionDeniedException>()));
  });

  test('the last active owner cannot be disabled or demoted', () async {
    await expectLater(h.auth.updateStaff(h.owner, h.owner.staffId, disabled: true), throwsA(isA<ConflictException>()));
    await expectLater(
      h.auth.updateStaff(h.owner, h.owner.staffId, role: StaffRole.cashier),
      throwsA(isA<ConflictException>()),
    );
    final second = await h.auth.createStaff(h.owner, name: 'Second Owner', role: StaffRole.owner, pin: '8642');
    await h.auth.updateStaff(h.owner, h.owner.staffId, disabled: true);
    await expectLater(h.auth.login(h.owner.staffId, ownerPin), throwsA(isA<PermissionDeniedException>()));
    expect((await h.auth.activeOwners()).single.id, second);
  });

  test('only owners manage staff', () async {
    await expectLater(
      h.auth.createStaff(h.cashier, name: 'X', role: StaffRole.owner, pin: '8642'),
      throwsA(isA<PermissionDeniedException>()),
    );
  });

  test('offline owner recovery with the one-time code', () async {
    // Regenerating invalidates the setup code and returns a fresh one.
    final code = await h.auth.regenerateRecoveryCode(h.owner);
    await expectLater(
      h.auth.resetOwnerPinWithRecoveryCode(h.owner.staffId, 'WRONG-CODE-0000-0000', '9753'),
      throwsA(isA<ValidationException>()),
    );
    final next = await h.auth.resetOwnerPinWithRecoveryCode(h.owner.staffId, code.toLowerCase(), '9753');
    expect(next, isNot(code));
    expect((await h.auth.login(h.owner.staffId, '9753')).isOwner, isTrue);
    // A used code stops working.
    await expectLater(
      h.auth.resetOwnerPinWithRecoveryCode(h.owner.staffId, code, '8642'),
      throwsA(isA<AppException>()),
    );
    // Only owners can create codes.
    await expectLater(h.auth.regenerateRecoveryCode(h.cashier), throwsA(isA<PermissionDeniedException>()));
  });

  test('setup cannot run twice and has no default credentials', () async {
    await expectLater(
      SetupService(
        h.ctx,
        hasher: fastHasher,
      ).completeSetup(const SetupInput(restaurantName: 'X', ownerName: 'Y', ownerPin: '4826')),
      throwsA(isA<ConflictException>()),
    );
    expect(await h.count(h.db.staff), 3, reason: 'only the accounts the test created');
  });
}
