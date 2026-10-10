import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';

class AuditService {
  AuditService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  /// Newest first. [actionPrefix] filters e.g. "refund." or "settings.".
  Future<List<AuditEventRow>> events(Actor actor, {String? actionPrefix, int? beforeMs, int limit = 200}) {
    actor.require(Permission.viewAudit);
    final q = _db.select(_db.auditEvents)
      ..orderBy([(e) => OrderingTerm(expression: e.at, mode: OrderingMode.desc)])
      ..limit(limit);
    q.where((e) {
      Expression<bool> c = const Constant(true);
      if (actionPrefix != null && actionPrefix.isNotEmpty) c = c & e.action.like('$actionPrefix%');
      if (beforeMs != null) c = c & e.at.isSmallerThanValue(beforeMs);
      return c;
    });
    return q.get();
  }
}
