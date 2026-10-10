import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/app_info.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/security/pin_hasher.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';

class SetupInput {
  const SetupInput({
    required this.restaurantName,
    required this.ownerName,
    required this.ownerPin,
    this.address = '',
    this.phone,
    this.taxRegistrationId,
    this.currencyCode = 'INR',
    this.timeZone = 'Asia/Kolkata',
    this.cutoffMinutes = 240,
    this.receiptFooter = 'Thank you! Visit again.',
    this.receiptPrefix,
  });

  final String restaurantName;
  final String address;
  final String? phone;
  final String? taxRegistrationId;
  final String currencyCode;
  final String timeZone;
  final int cutoffMinutes;
  final String receiptFooter;
  final String ownerName;
  final String ownerPin;

  /// Shown before every receipt number; generated if empty.
  final String? receiptPrefix;
}

class SetupResult {
  const SetupResult({required this.owner, required this.recoveryCode, required this.receiptPrefix});
  final Actor owner;

  /// Shown once. Lets an owner reset their PIN on this installation.
  final String recoveryCode;
  final String receiptPrefix;
}

class SetupService {
  SetupService(this.ctx, {this.hasher = const PinHasher()});

  final ServiceContext ctx;
  final PinHasher hasher;

  AppDatabase get _db => ctx.db;

  Future<bool> isSetupComplete() async =>
      (await _db.select(_db.restaurantSettings).getSingleOrNull()) != null &&
      (await _db.select(_db.installation).getSingleOrNull()) != null;

  static String generateReceiptPrefix() {
    const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    final r = Random.secure();
    return List.generate(3, (_) => letters[r.nextInt(letters.length)]).join();
  }

  static String validateReceiptPrefix(String value) {
    final v = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{2,6}$').hasMatch(v)) {
      throw const ValidationException('Receipt prefix must be 2–6 letters or digits');
    }
    return v;
  }

  Future<SetupResult> completeSetup(SetupInput input, {bool isDemo = false}) async {
    if (await isSetupComplete()) {
      throw const ConflictException('This installation is already set up');
    }
    final name = requireText(input.restaurantName, 'Restaurant name');
    final ownerName = requireText(input.ownerName, 'Owner name', max: 60);
    PinHasher.validatePin(input.ownerPin);
    if (!BusinessCalendar.isValidTimeZone(input.timeZone)) {
      throw ValidationException('Unknown time zone "${input.timeZone}"');
    }
    if (input.cutoffMinutes < 0 || input.cutoffMinutes >= 24 * 60) {
      throw const ValidationException('Business day cutoff must be between 00:00 and 23:59');
    }
    if (input.currencyCode != 'INR') {
      throw const ValidationException('Only INR is supported in this version');
    }
    final prefix = (input.receiptPrefix == null || input.receiptPrefix!.trim().isEmpty)
        ? (isDemo ? 'DEMO' : generateReceiptPrefix())
        : validateReceiptPrefix(input.receiptPrefix!);

    final pinHash = await hasher.hash(input.ownerPin);
    final recoveryCode = PinHasher.newRecoveryCode();
    final recoveryHash = await hasher.hash(PinHasher.normalizeRecoveryCode(recoveryCode));
    final now = ctx.nowMs();
    final ownerId = ctx.ids.newId();

    await _db.transaction(() async {
      await _db
          .into(_db.installation)
          .insert(
            InstallationCompanion.insert(
              installationId: ctx.ids.newId(),
              receiptPrefix: prefix,
              isDemo: Value(isDemo),
              createdAt: now,
              createdByAppVersion: AppInfo.version,
            ),
          );
      await _db
          .into(_db.restaurantSettings)
          .insert(
            RestaurantSettingsCompanion.insert(
              name: name,
              address: Value(input.address.trim()),
              phone: Value(optionalText(input.phone, max: 40)),
              taxRegistrationId: Value(optionalText(input.taxRegistrationId, max: 40)),
              currencyCode: Value(input.currencyCode),
              timeZone: Value(input.timeZone),
              cutoffMinutes: Value(input.cutoffMinutes),
              receiptFooter: Value(input.receiptFooter.trim()),
              setupCompletedAt: now,
              updatedAt: now,
            ),
          );
      await _db
          .into(_db.staff)
          .insert(
            StaffCompanion.insert(
              id: ownerId,
              name: ownerName,
              role: StaffRole.owner.name,
              pinHash: pinHash,
              createdAt: now,
              updatedAt: now,
            ),
          );
      await _db
          .into(_db.ownerRecovery)
          .insert(
            OwnerRecoveryCompanion.insert(
              id: ctx.ids.newId(),
              codeHash: recoveryHash,
              createdBy: Value(ownerId),
              createdAt: now,
            ),
          );
      for (final seq in ['receipt', 'order', 'kot', 'refund']) {
        await _db.into(_db.sequences).insert(SequencesCompanion.insert(name: seq, nextValue: 1));
      }
      await ctx.audit(
        Actor(staffId: ownerId, name: ownerName, role: StaffRole.owner),
        'setup.completed',
        entityType: 'installation',
        details: {'restaurant': name, 'receiptPrefix': prefix, 'demo': isDemo},
      );
    });

    return SetupResult(
      owner: Actor(staffId: ownerId, name: ownerName, role: StaffRole.owner),
      recoveryCode: recoveryCode,
      receiptPrefix: prefix,
    );
  }
}
