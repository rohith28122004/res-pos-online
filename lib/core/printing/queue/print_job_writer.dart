import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../service_context.dart';

abstract final class PrinterRole {
  static const receipt = 'receipt';
  static const kot = 'kot';
  static const both = 'both';

  static String label(String r) => switch (r) {
    receipt => 'Receipts',
    kot => 'Kitchen tickets',
    both => 'Receipts and kitchen tickets',
    _ => r,
  };
}

/// Print job lifecycle. `submitted` means the bytes reached the printer
/// connection or the Windows spooler — not that paper came out.
abstract final class PrintJobState {
  static const queued = 'queued';
  static const sending = 'sending';
  static const submitted = 'submitted';
  static const failed = 'failed';

  /// Interrupted or ambiguous: the operator must check the printer before
  /// any retry. Never resent automatically.
  static const unknown = 'unknown';

  /// Paused after a backup restore until someone reviews it.
  static const held = 'held';

  /// Operator confirmed it printed (after unknown) or dismissed it.
  static const resolved = 'resolved';
  static const cancelled = 'cancelled';

  static const needsAttention = [failed, unknown, held];
  static const pending = [queued, sending];

  static String label(String s) => switch (s) {
    queued => 'Waiting',
    sending => 'Sending',
    submitted => 'Sent to printer',
    failed => 'Failed — not sent',
    unknown => 'Unknown — check printer',
    held => 'Held for review',
    resolved => 'Resolved',
    cancelled => 'Cancelled',
    _ => s,
  };
}

/// Inserts durable print jobs. Call inside the business transaction (checkout,
/// KOT submission) so the job exists exactly when the bill/ticket does.
class PrintJobWriter {
  PrintJobWriter(this.ctx);
  final ServiceContext ctx;

  AppDatabase get _db => ctx.db;

  Future<List<PrinterProfileRow>> printersFor(String role) async {
    final rows =
        await (_db.select(_db.printerProfiles)
              ..where((p) => p.enabled.equals(true) & p.archived.equals(false))
              ..orderBy([(p) => OrderingTerm(expression: p.name)]))
            .get();
    return rows.where((p) => p.role == role || p.role == PrinterRole.both).toList();
  }

  /// One job per enabled printer serving [role]. Returns the job ids (empty
  /// when no printer is configured — billing never depends on a printer).
  Future<List<String>> enqueueForRole({
    required String role,
    required String documentType,
    required String payloadJson,
    String? documentRef,
    String? copyLabel,
    String? createdBy,
  }) async {
    final printers = await printersFor(role);
    final ids = <String>[];
    for (final p in printers) {
      ids.add(
        await enqueueFor(
          printerId: p.id,
          documentType: documentType,
          payloadJson: payloadJson,
          documentRef: documentRef,
          copyLabel: copyLabel,
          createdBy: createdBy,
        ),
      );
    }
    return ids;
  }

  Future<String> enqueueFor({
    required String printerId,
    required String documentType,
    required String payloadJson,
    String? documentRef,
    String? copyLabel,
    String? createdBy,
  }) async {
    final id = ctx.ids.newId();
    final now = ctx.nowMs();
    await _db
        .into(_db.printJobs)
        .insert(
          PrintJobsCompanion.insert(
            id: id,
            printerProfileId: printerId,
            documentType: documentType,
            documentRef: Value(documentRef),
            payloadJson: payloadJson,
            copyLabel: Value(copyLabel),
            state: PrintJobState.queued,
            createdBy: Value(createdBy),
            createdAt: now,
            updatedAt: now,
          ),
        );
    return id;
  }
}
