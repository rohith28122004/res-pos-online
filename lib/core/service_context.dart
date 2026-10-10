import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database/app_database.dart';
import 'errors/app_exception.dart';
import 'money/money.dart';
import 'security/permissions.dart';
import 'time/business_time.dart';

/// Time-ordered UUIDs (v7) for primary keys.
class IdGenerator {
  IdGenerator();
  static const _uuid = Uuid();
  String newId() => _uuid.v7();
}

/// Shared dependencies for application services.
class ServiceContext {
  ServiceContext({required this.db, required this.clock, IdGenerator? ids}) : ids = ids ?? IdGenerator();

  final AppDatabase db;
  final Clock clock;
  final IdGenerator ids;

  DateTime now() => clock.nowUtc();
  int nowMs() => clock.nowUtc().millisecondsSinceEpoch;

  Future<RestaurantSettingsRow> settings() async {
    final row = await db.select(db.restaurantSettings).getSingleOrNull();
    if (row == null) throw const ConflictException('Restaurant setup has not been completed');
    return row;
  }

  Future<InstallationRow> installation() async {
    final row = await db.select(db.installation).getSingleOrNull();
    if (row == null) throw const ConflictException('Restaurant setup has not been completed');
    return row;
  }

  Future<BusinessCalendar> calendar() async {
    final s = await settings();
    return BusinessCalendar(timeZone: s.timeZone, cutoffMinutes: s.cutoffMinutes);
  }

  Future<CurrencyFormat> currency() async => CurrencyFormat.forCode((await settings()).currencyCode);

  Future<void> audit(
    Actor? actor,
    String action, {
    String? entityType,
    String? entityId,
    Map<String, Object?>? details,
    OwnerApproval? approval,
  }) => db.writeAudit(
    id: ids.newId(),
    at: now(),
    action: action,
    actorId: actor?.staffId,
    actorName: actor?.name,
    entityType: entityType,
    entityId: entityId,
    details: details,
    approvedBy: approval?.ownerId,
  );

  /// Throws unless [approval] is a fresh approval by an enabled owner.
  Future<void> verifyApproval(OwnerApproval? approval, String what) async {
    if (approval == null) {
      throw ApprovalRequiredException('Owner approval is required to $what.');
    }
    if (!approval.isFreshAt(now())) {
      throw ApprovalRequiredException('Owner approval has expired. Ask the owner to approve again to $what.');
    }
    final owner = await (db.select(db.staff)..where((s) => s.id.equals(approval.ownerId))).getSingleOrNull();
    if (owner == null || owner.disabled || owner.role != StaffRole.owner.name) {
      throw ApprovalRequiredException(
        'That approval is not from an active owner. Owner approval is required to $what.',
      );
    }
  }

  /// Approval is satisfied by an owner actor, or by an owner approval.
  Future<void> requireOwnerOrApproval(Actor actor, OwnerApproval? approval, String what) async {
    if (actor.isOwner) return;
    await verifyApproval(approval, what);
  }

  /// Idempotency: returns the result id previously stored for [key], if any.
  Future<String?> completedOperation(String key) async {
    final row = await (db.select(db.completedOperations)..where((o) => o.operationKey.equals(key))).getSingleOrNull();
    return row?.resultId;
  }

  Future<void> recordOperation(String key, String kind, String resultId) => db
      .into(db.completedOperations)
      .insert(
        CompletedOperationsCompanion.insert(
          operationKey: key,
          kind: kind,
          resultId: resultId,
          createdAt: nowMs(),
        ),
      );
}

String requireText(String? value, String field, {int max = 120}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) throw ValidationException('$field is required');
  if (v.length > max) throw ValidationException('$field must be at most $max characters');
  return v;
}

String? optionalText(String? value, {int max = 500}) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  if (v.length > max) throw ValidationException('Text must be at most $max characters');
  return v;
}

extension ValueOrAbsent<T extends Object> on T? {
  Value<T?> get asValue => Value(this);
}
