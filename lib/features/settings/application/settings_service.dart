import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/money/money.dart';
import '../../../core/pricing/tax.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';

class BusinessDetailsInput {
  const BusinessDetailsInput({
    required this.name,
    required this.address,
    this.phone,
    this.taxRegistrationId,
    this.receiptHeader,
    required this.receiptFooter,
  });

  final String name;
  final String address;
  final String? phone;
  final String? taxRegistrationId;
  final String? receiptHeader;
  final String receiptFooter;
}

class PricingSettingsInput {
  const PricingSettingsInput({
    required this.cashierDiscountLimitBps,
    required this.serviceChargeBps,
    this.serviceChargeTaxProfileId,
    required this.deliveryChargeDefault,
    this.deliveryChargeTaxProfileId,
    required this.roundingUnit,
  });

  final int cashierDiscountLimitBps;
  final int serviceChargeBps;
  final String? serviceChargeTaxProfileId;
  final int deliveryChargeDefault;
  final String? deliveryChargeTaxProfileId;
  final int roundingUnit;
}

class OperationsSettingsInput {
  const OperationsSettingsInput({
    required this.timeZone,
    required this.cutoffMinutes,
    required this.lockTimeoutMinutes,
    required this.kotShowPrices,
    required this.autoPrintReceipt,
    required this.autoPrintKot,
  });

  final String timeZone;
  final int cutoffMinutes;
  final int lockTimeoutMinutes;
  final bool kotShowPrices;
  final bool autoPrintReceipt;
  final bool autoPrintKot;
}

class BackupSettingsInput {
  const BackupSettingsInput({this.directory, required this.intervalHours, required this.retention});
  final String? directory;
  final int intervalHours;
  final int retention;
}

class TaxProfileInput {
  const TaxProfileInput({
    required this.name,
    required this.mode,
    required this.rateBps,
    this.components = const [],
  });

  final String name;
  final TaxMode mode;
  final int rateBps;
  final List<TaxComponentRate> components;

  TaxSnapshot get snapshot => TaxSnapshot(mode: mode, rateBps: rateBps, components: components);
}

/// Allowed payable rounding units (minor units). 0 = off (the default).
const roundingUnits = [0, 50, 100, 500, 1000];

class SettingsService {
  SettingsService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  Stream<RestaurantSettingsRow?> watch() => _db.select(_db.restaurantSettings).watchSingleOrNull();

  Future<RestaurantSettingsRow> get() => ctx.settings();

  Future<void> _update(
    Actor actor,
    String action,
    RestaurantSettingsCompanion changes,
    Map<String, Object?> Function(RestaurantSettingsRow before) describe,
  ) async {
    actor.require(Permission.manageSettings);
    await _db.transaction(() async {
      final before = await ctx.settings();
      await _db
          .update(_db.restaurantSettings)
          .write(
            changes.copyWith(
              updatedAt: Value(ctx.nowMs()),
              version: Value(before.version + 1),
            ),
          );
      final after = await ctx.settings();
      await ctx.audit(
        actor,
        action,
        entityType: 'settings',
        details: {
          'before': describe(before),
          'after': describe(after),
        },
      );
    });
  }

  Future<void> updateBusinessDetails(Actor actor, BusinessDetailsInput input) => _update(
    actor,
    'settings.business',
    RestaurantSettingsCompanion(
      name: Value(requireText(input.name, 'Restaurant name')),
      address: Value(input.address.trim()),
      phone: Value(optionalText(input.phone, max: 40)),
      taxRegistrationId: Value(optionalText(input.taxRegistrationId, max: 40)),
      receiptHeader: Value(optionalText(input.receiptHeader, max: 200)),
      receiptFooter: Value(input.receiptFooter.trim()),
    ),
    (s) => {
      'name': s.name,
      'address': s.address,
      'phone': s.phone,
      'taxRegistrationId': s.taxRegistrationId,
      'receiptHeader': s.receiptHeader,
      'receiptFooter': s.receiptFooter,
    },
  );

  Future<void> updatePricing(Actor actor, PricingSettingsInput input) async {
    if (input.cashierDiscountLimitBps < 0 || input.cashierDiscountLimitBps > bpsDenominator) {
      throw const ValidationException('Discount limit must be between 0% and 100%');
    }
    if (input.serviceChargeBps < 0 || input.serviceChargeBps > 3000) {
      throw const ValidationException('Service charge must be between 0% and 30%');
    }
    if (input.deliveryChargeDefault < 0) {
      throw const ValidationException('Delivery charge cannot be negative');
    }
    if (!roundingUnits.contains(input.roundingUnit)) {
      throw const ValidationException('Unsupported rounding option');
    }
    for (final id in [input.serviceChargeTaxProfileId, input.deliveryChargeTaxProfileId]) {
      if (id != null) await _taxProfile(id);
    }
    await _update(
      actor,
      'settings.pricing',
      RestaurantSettingsCompanion(
        cashierDiscountLimitBps: Value(input.cashierDiscountLimitBps),
        serviceChargeBps: Value(input.serviceChargeBps),
        serviceChargeTaxProfileId: Value(input.serviceChargeTaxProfileId),
        deliveryChargeDefault: Value(input.deliveryChargeDefault),
        deliveryChargeTaxProfileId: Value(input.deliveryChargeTaxProfileId),
        roundingUnit: Value(input.roundingUnit),
      ),
      (s) => {
        'cashierDiscountLimitBps': s.cashierDiscountLimitBps,
        'serviceChargeBps': s.serviceChargeBps,
        'serviceChargeTaxProfileId': s.serviceChargeTaxProfileId,
        'deliveryChargeDefault': s.deliveryChargeDefault,
        'deliveryChargeTaxProfileId': s.deliveryChargeTaxProfileId,
        'roundingUnit': s.roundingUnit,
      },
    );
  }

  /// Changing the cutoff affects only records created afterwards; existing
  /// rows keep the business date they were stamped with.
  Future<void> updateOperations(Actor actor, OperationsSettingsInput input) async {
    if (!BusinessCalendar.isValidTimeZone(input.timeZone)) {
      throw ValidationException('Unknown time zone "${input.timeZone}"');
    }
    if (input.cutoffMinutes < 0 || input.cutoffMinutes >= 24 * 60) {
      throw const ValidationException('Business day cutoff must be between 00:00 and 23:59');
    }
    if (input.lockTimeoutMinutes < 1 || input.lockTimeoutMinutes > 240) {
      throw const ValidationException('Lock timeout must be between 1 and 240 minutes');
    }
    await _update(
      actor,
      'settings.operations',
      RestaurantSettingsCompanion(
        timeZone: Value(input.timeZone),
        cutoffMinutes: Value(input.cutoffMinutes),
        lockTimeoutMinutes: Value(input.lockTimeoutMinutes),
        kotShowPrices: Value(input.kotShowPrices),
        autoPrintReceipt: Value(input.autoPrintReceipt),
        autoPrintKot: Value(input.autoPrintKot),
      ),
      (s) => {
        'timeZone': s.timeZone,
        'cutoffMinutes': s.cutoffMinutes,
        'lockTimeoutMinutes': s.lockTimeoutMinutes,
        'kotShowPrices': s.kotShowPrices,
        'autoPrintReceipt': s.autoPrintReceipt,
        'autoPrintKot': s.autoPrintKot,
      },
    );
  }

  Future<void> updateBackup(Actor actor, BackupSettingsInput input) async {
    if (input.intervalHours < 1 || input.intervalHours > 24 * 7) {
      throw const ValidationException('Backup interval must be between 1 hour and 7 days');
    }
    if (input.retention < 1 || input.retention > 365) {
      throw const ValidationException('Keep between 1 and 365 backups');
    }
    await _update(
      actor,
      'settings.backup',
      RestaurantSettingsCompanion(
        backupDirectory: Value(optionalText(input.directory, max: 1000)),
        backupIntervalHours: Value(input.intervalHours),
        backupRetention: Value(input.retention),
      ),
      (s) => {'directory': s.backupDirectory, 'intervalHours': s.backupIntervalHours, 'retention': s.backupRetention},
    );
  }

  // ---- Tax profiles -------------------------------------------------------

  Stream<List<TaxProfileRow>> watchTaxProfiles({bool includeArchived = false}) {
    final q = _db.select(_db.taxProfiles)..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    return q.watch();
  }

  Future<List<TaxProfileRow>> taxProfiles({bool includeArchived = false}) {
    final q = _db.select(_db.taxProfiles)..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!includeArchived) q.where((t) => t.archived.equals(false));
    return q.get();
  }

  Future<TaxProfileRow> _taxProfile(String id) async {
    final row = await (_db.select(_db.taxProfiles)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) throw const NotFoundException('Tax profile not found');
    return row;
  }

  Future<String> createTaxProfile(Actor actor, TaxProfileInput input) async {
    actor.require(Permission.manageSettings);
    final name = requireText(input.name, 'Tax profile name', max: 40);
    input.snapshot.validate();
    final id = ctx.ids.newId();
    await _db.transaction(() async {
      await _db
          .into(_db.taxProfiles)
          .insert(
            TaxProfilesCompanion.insert(
              id: id,
              name: name,
              mode: input.mode.name,
              rateBps: input.rateBps,
              componentsJson: Value(TaxSnapshot.encodeComponents(input.components)),
              updatedAt: ctx.nowMs(),
            ),
          );
      await ctx.audit(
        actor,
        'tax_profile.created',
        entityType: 'tax_profile',
        entityId: id,
        details: {
          'name': name,
          'mode': input.mode.name,
          'rateBps': input.rateBps,
          'components': [for (final c in input.components) c.toJson()],
        },
      );
    });
    return id;
  }

  /// Edits apply to lines added from now on. Open order lines and bills keep
  /// the tax they captured.
  Future<void> updateTaxProfile(Actor actor, String id, TaxProfileInput input) async {
    actor.require(Permission.manageSettings);
    final name = requireText(input.name, 'Tax profile name', max: 40);
    input.snapshot.validate();
    await _db.transaction(() async {
      final before = await _taxProfile(id);
      await (_db.update(_db.taxProfiles)..where((t) => t.id.equals(id))).write(
        TaxProfilesCompanion(
          name: Value(name),
          mode: Value(input.mode.name),
          rateBps: Value(input.rateBps),
          componentsJson: Value(TaxSnapshot.encodeComponents(input.components)),
          version: Value(before.version + 1),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await ctx.audit(
        actor,
        'tax_profile.updated',
        entityType: 'tax_profile',
        entityId: id,
        details: {
          'before': {
            'name': before.name,
            'mode': before.mode,
            'rateBps': before.rateBps,
            'components': before.componentsJson,
          },
          'after': {
            'name': name,
            'mode': input.mode.name,
            'rateBps': input.rateBps,
            'components': TaxSnapshot.encodeComponents(input.components),
          },
        },
      );
    });
  }

  Future<void> setTaxProfileArchived(Actor actor, String id, bool archived) async {
    actor.require(Permission.manageSettings);
    await _db.transaction(() async {
      await _taxProfile(id);
      await (_db.update(_db.taxProfiles)..where((t) => t.id.equals(id))).write(
        TaxProfilesCompanion(archived: Value(archived), updatedAt: Value(ctx.nowMs())),
      );
      await ctx.audit(
        actor,
        archived ? 'tax_profile.archived' : 'tax_profile.restored',
        entityType: 'tax_profile',
        entityId: id,
      );
    });
  }

  /// Snapshot of a profile as it is right now (null id = no tax).
  Future<TaxSnapshot> snapshotFor(String? profileId) async {
    if (profileId == null) return TaxSnapshot.none;
    final p = await (_db.select(_db.taxProfiles)..where((t) => t.id.equals(profileId))).getSingleOrNull();
    if (p == null) return TaxSnapshot.none;
    return taxSnapshotOf(p);
  }
}

TaxSnapshot taxSnapshotOf(TaxProfileRow p) => TaxSnapshot(
  mode: TaxMode.parse(p.mode),
  rateBps: p.rateBps,
  components: TaxSnapshot.decodeComponents(p.componentsJson),
  profileId: p.id,
  profileName: p.name,
);
