import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/printing/documents/print_documents.dart';
import '../../../core/printing/encoders/escpos.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../core/printing/queue/print_queue.dart';
import '../../../core/printing/transports/transport.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';

class PrinterProfileInput {
  const PrinterProfileInput({
    required this.name,
    required this.role,
    required this.paperWidthMm,
    required this.dotsWidth,
    required this.charsPerLine,
    required this.codePage,
    required this.renderMode,
    required this.cutter,
    required this.drawerPulse,
    required this.transport,
    required this.endpoint,
    this.port,
    this.timeoutMs = 8000,
    this.feedLines = 3,
    this.enabled = true,
  });

  /// Sensible defaults for a paper width.
  factory PrinterProfileInput.defaults({required int paperWidthMm, required TransportType transport}) =>
      PrinterProfileInput(
        name: '',
        role: PrinterRole.both,
        paperWidthMm: paperWidthMm,
        dotsWidth: paperWidthMm == 58 ? 384 : 576,
        charsPerLine: paperWidthMm == 58 ? 32 : 48,
        codePage: CodePage.cp437.code,
        renderMode: RenderMode.auto,
        cutter: paperWidthMm == 58 ? CutMode.none.code : CutMode.partial.code,
        drawerPulse: false,
        transport: transport,
        endpoint: '',
        port: transport == TransportType.tcp ? 9100 : null,
      );

  final String name;
  final String role;
  final int paperWidthMm;
  final int dotsWidth;
  final int charsPerLine;
  final String codePage;
  final String renderMode;
  final String cutter;
  final bool drawerPulse;
  final TransportType transport;
  final String endpoint;
  final int? port;
  final int timeoutMs;
  final int feedLines;
  final bool enabled;

  void validate() {
    requireText(name, 'Printer name', max: 40);
    if (![PrinterRole.receipt, PrinterRole.kot, PrinterRole.both].contains(role)) {
      throw const ValidationException('Choose what this printer prints');
    }
    if (paperWidthMm != 58 && paperWidthMm != 80) throw const ValidationException('Paper width must be 58 or 80 mm');
    if (dotsWidth < 200 || dotsWidth > 832 || dotsWidth % 8 != 0) {
      throw const ValidationException('Printable width must be 200–832 dots and a multiple of 8 (usually 384 or 576)');
    }
    if (charsPerLine < 24 || charsPerLine > 64) {
      throw const ValidationException('Characters per line must be between 24 and 64 (usually 32 or 48)');
    }
    if (![RenderMode.text, RenderMode.auto, RenderMode.raster].contains(renderMode)) {
      throw const ValidationException('Unknown print mode');
    }
    if (timeoutMs < 2000 || timeoutMs > 60000) throw const ValidationException('Timeout must be 2–60 seconds');
    if (feedLines < 0 || feedLines > 10) throw const ValidationException('Feed lines must be 0–10');
    final error = switch (transport) {
      TransportType.tcp => validateHost(endpoint) ?? validatePort(port),
      TransportType.bluetooth => validateBluetoothAddress(endpoint),
      TransportType.windowsRaw ||
      TransportType.windowsDriver => endpoint.trim().isEmpty ? 'Choose an installed Windows printer' : null,
    };
    if (error != null) throw ValidationException(error);
  }
}

class PrintJobView {
  const PrintJobView({required this.job, required this.printerName, required this.attempts});
  final PrintJobRow job;
  final String printerName;
  final List<PrintAttemptRow> attempts;
}

class PrintQueueCounts {
  const PrintQueueCounts({required this.pending, required this.attention});
  final int pending;
  final int attention;
}

class PrinterService {
  PrinterService(this.ctx) : _writer = PrintJobWriter(ctx);

  final ServiceContext ctx;
  final PrintJobWriter _writer;
  AppDatabase get _db => ctx.db;

  Stream<List<PrinterProfileRow>> watchProfiles() =>
      (_db.select(_db.printerProfiles)
            ..where((p) => p.archived.equals(false))
            ..orderBy([(p) => OrderingTerm(expression: p.name)]))
          .watch();

  Future<PrinterProfileRow> profile(String id) async {
    final p = await (_db.select(_db.printerProfiles)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (p == null) throw const NotFoundException('Printer not found');
    return p;
  }

  Future<String> saveProfile(Actor actor, PrinterProfileInput input, {String? id}) async {
    actor.require(Permission.managePrinters);
    input.validate();
    final now = ctx.nowMs();
    final pid = id ?? ctx.ids.newId();
    await _db.transaction(() async {
      final companion = PrinterProfilesCompanion(
        name: Value(input.name.trim()),
        role: Value(input.role),
        paperWidthMm: Value(input.paperWidthMm),
        dotsWidth: Value(input.dotsWidth),
        charsPerLine: Value(input.charsPerLine),
        codePage: Value(input.codePage),
        renderMode: Value(input.renderMode),
        cutter: Value(input.cutter),
        drawerPulse: Value(input.drawerPulse),
        transport: Value(input.transport.code),
        endpoint: Value(input.endpoint.trim()),
        port: Value(input.port),
        timeoutMs: Value(input.timeoutMs),
        feedLines: Value(input.feedLines),
        enabled: Value(input.enabled),
        updatedAt: Value(now),
      );
      if (id == null) {
        await _db.into(_db.printerProfiles).insert(companion.copyWith(id: Value(pid)));
      } else {
        await profile(id);
        await (_db.update(_db.printerProfiles)..where((p) => p.id.equals(id))).write(companion);
      }
      await ctx.audit(
        actor,
        id == null ? 'printer.created' : 'printer.updated',
        entityType: 'printer',
        entityId: pid,
        details: {
          'name': input.name.trim(),
          'role': input.role,
          'transport': input.transport.code,
          'paper': input.paperWidthMm,
          'drawerPulse': input.drawerPulse,
        },
      );
    });
    return pid;
  }

  /// Printers referenced by jobs are archived, never deleted.
  Future<void> archiveProfile(Actor actor, String id) async {
    actor.require(Permission.managePrinters);
    await _db.transaction(() async {
      await profile(id);
      await (_db.update(_db.printerProfiles)..where((p) => p.id.equals(id))).write(
        PrinterProfilesCompanion(
          archived: const Value(true),
          enabled: const Value(false),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await (_db.update(_db.printJobs)
            ..where((j) => j.printerProfileId.equals(id) & j.state.isIn([PrintJobState.queued, PrintJobState.held])))
          .write(PrintJobsCompanion(state: const Value(PrintJobState.cancelled), updatedAt: Value(ctx.nowMs())));
      await ctx.audit(actor, 'printer.archived', entityType: 'printer', entityId: id);
    });
  }

  Future<String> printTestPage(Actor actor, String printerId) async {
    actor.require(Permission.viewPrintQueue);
    final p = await profile(printerId);
    final calendar = await ctx.calendar();
    final doc = TestPageDocument(
      printerName: p.name,
      dateTime: calendar.formatLocal(ctx.now()),
      paperWidthMm: p.paperWidthMm,
    );
    return _db.transaction(() async {
      final id = await _writer.enqueueFor(
        printerId: printerId,
        documentType: DocumentType.test,
        payloadJson: doc.encode(),
        createdBy: actor.staffId,
      );
      await ctx.audit(actor, 'printer.test_page', entityType: 'printer', entityId: printerId);
      return id;
    });
  }

  /// Sample receipt and KOT with long names, modifiers and ₹, marked SAMPLE.
  Future<List<String>> printSamples(Actor actor, String printerId) async {
    actor.require(Permission.viewPrintQueue);
    final p = await profile(printerId);
    final calendar = await ctx.calendar();
    final settings = await ctx.settings();
    final now = calendar.formatLocal(ctx.now());
    final receipt = ReceiptDocument(
      title: 'RECEIPT',
      restaurantName: settings.name,
      headerLines: [settings.address],
      number: 'SAMPLE-000001',
      dateTime: now,
      infoLines: const ['Dine-in · T1 · Order #1', 'Cashier: Sample'],
      lines: const [
        ReceiptLineDoc(quantity: 2, name: 'Filter coffee', unitPrice: 4000, amount: 8000),
        ReceiptLineDoc(
          quantity: 1,
          name: 'Paneer tikka grilled sandwich with extra cheese and mint chutney',
          variant: 'Large',
          modifiers: ['+ Extra cheese', '+ No onion'],
          unitPrice: 22000,
          amount: 22000,
          discount: 2200,
        ),
      ],
      summary: const [
        AmountRow('Subtotal', 30000),
        AmountRow('Item discounts', -2200),
        AmountRow('CGST 2.5%', 695),
        AmountRow('SGST 2.5%', 695),
      ],
      total: 29190,
      payments: const [AmountRow('Cash', 29190), AmountRow('Cash received', 30000), AmountRow('Change', 810)],
      footerLines: const ['Sample print — not a bill', 'Price ₹ test: ₹291.90'],
      currencyCode: settings.currencyCode,
      copyLabel: 'SAMPLE',
    );
    final kot = KotDocument(
      ticketNo: 0,
      kind: 'order',
      orderRef: 'T1 · #1',
      orderTypeLabel: 'Dine-in',
      tableLabel: 'T1',
      dateTime: now,
      staffName: 'Sample',
      lines: const [
        KotLineDoc(quantity: 2, name: 'Filter coffee', note: 'Less sugar'),
        KotLineDoc(
          quantity: 1,
          name: 'Paneer tikka grilled sandwich with extra cheese',
          variant: 'Large',
          modifiers: ['Extra cheese'],
        ),
      ],
      currencyCode: settings.currencyCode,
      copyLabel: 'SAMPLE',
    );
    return _db.transaction(() async {
      final ids = <String>[];
      if (p.role != PrinterRole.kot) {
        ids.add(
          await _writer.enqueueFor(
            printerId: printerId,
            documentType: DocumentType.receipt,
            payloadJson: receipt.encode(),
            copyLabel: 'SAMPLE',
            createdBy: actor.staffId,
          ),
        );
      }
      if (p.role != PrinterRole.receipt) {
        ids.add(
          await _writer.enqueueFor(
            printerId: printerId,
            documentType: DocumentType.kot,
            payloadJson: kot.encode(),
            copyLabel: 'SAMPLE',
            createdBy: actor.staffId,
          ),
        );
      }
      await ctx.audit(actor, 'printer.samples', entityType: 'printer', entityId: printerId);
      return ids;
    });
  }

  // ---- Jobs --------------------------------------------------------------------

  Stream<PrintQueueCounts> watchCounts() async* {
    yield await counts();
    await for (final _ in _db.tableUpdates(TableUpdateQuery.onTable(_db.printJobs))) {
      yield await counts();
    }
  }

  Future<PrintQueueCounts> counts() async {
    final row = await _db
        .customSelect(
          'SELECT '
          "COALESCE(SUM(CASE WHEN state IN ('queued','sending') THEN 1 ELSE 0 END), 0) AS pending, "
          "COALESCE(SUM(CASE WHEN state IN ('failed','unknown','held') THEN 1 ELSE 0 END), 0) AS attention "
          'FROM print_jobs',
          readsFrom: {_db.printJobs},
        )
        .getSingle();
    return PrintQueueCounts(pending: row.read<int>('pending'), attention: row.read<int>('attention'));
  }

  Stream<List<PrintJobView>> watchJobs({bool attentionOnly = false, int limit = 100}) async* {
    yield await jobs(attentionOnly: attentionOnly, limit: limit);
    await for (final _ in _db.tableUpdates(TableUpdateQuery.onAllTables([_db.printJobs, _db.printAttempts]))) {
      yield await jobs(attentionOnly: attentionOnly, limit: limit);
    }
  }

  Future<List<PrintJobView>> jobs({bool attentionOnly = false, int limit = 100}) async {
    final q = _db.select(_db.printJobs)
      ..orderBy([(j) => OrderingTerm(expression: j.createdAt, mode: OrderingMode.desc)])
      ..limit(limit);
    if (attentionOnly) q.where((j) => j.state.isIn(PrintJobState.needsAttention));
    final list = await q.get();
    if (list.isEmpty) return const [];
    final names = {for (final p in await _db.select(_db.printerProfiles).get()) p.id: p.name};
    final attempts =
        await (_db.select(_db.printAttempts)
              ..where((a) => a.jobId.isIn(list.map((j) => j.id)))
              ..orderBy([(a) => OrderingTerm(expression: a.startedAt)]))
            .get();
    final byJob = <String, List<PrintAttemptRow>>{};
    for (final a in attempts) {
      byJob.putIfAbsent(a.jobId, () => []).add(a);
    }
    return [
      for (final j in list)
        PrintJobView(
          job: j,
          printerName: names[j.printerProfileId] ?? 'Removed printer',
          attempts: byJob[j.id] ?? const [],
        ),
    ];
  }

  Future<PrintJobRow> _job(String id) async {
    final j = await (_db.select(_db.printJobs)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (j == null) throw const NotFoundException('Print job not found');
    return j;
  }

  /// Explicit operator retry.
  /// * failed (definitely not sent) → resent as it was
  /// * unknown (may have printed) → resent marked REPRINT, only after the
  ///   operator has checked the printer and chosen to reprint
  /// * held (after a restore) → released as it was
  Future<void> retry(Actor actor, String jobId, {bool confirmedNotPrinted = false}) async {
    actor.require(Permission.viewPrintQueue);
    await _db.transaction(() async {
      final job = await _job(jobId);
      var payload = job.payloadJson;
      var label = job.copyLabel;
      switch (job.state) {
        case PrintJobState.failed:
        case PrintJobState.held:
          break;
        case PrintJobState.unknown:
          if (!confirmedNotPrinted) {
            throw const ConflictException('Check the printer first. Confirm it did not print before reprinting.');
          }
          final doc = decodeDocument(job.payloadJson);
          label = CopyLabel.reprint;
          payload = switch (doc) {
            final ReceiptDocument r => r.withCopyLabel(label).encode(),
            final KotDocument k => k.withCopyLabel(label).encode(),
            final TestPageDocument t => t.encode(),
            _ => payload,
          };
        default:
          throw ConflictException('A job that is "${PrintJobState.label(job.state)}" cannot be retried');
      }
      await (_db.update(_db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(
          state: const Value(PrintJobState.queued),
          payloadJson: Value(payload),
          copyLabel: Value(label),
          updatedAt: Value(ctx.nowMs()),
        ),
      );
      await ctx.audit(
        actor,
        'print.retry',
        entityType: 'print_job',
        entityId: jobId,
        details: {'from': job.state, 'label': label, 'document': job.documentType},
      );
    });
  }

  Future<int> retryAllFailed(Actor actor) async {
    actor.require(Permission.viewPrintQueue);
    final failed = await (_db.select(_db.printJobs)..where((j) => j.state.equals(PrintJobState.failed))).get();
    for (final j in failed) {
      await retry(actor, j.id);
    }
    return failed.length;
  }

  /// Operator checked the printer: the uncertain job did print.
  Future<void> confirmPrinted(Actor actor, String jobId) async {
    actor.require(Permission.viewPrintQueue);
    await _db.transaction(() async {
      final job = await _job(jobId);
      if (job.state != PrintJobState.unknown) throw const ConflictException('Only uncertain jobs need confirming');
      await (_db.update(_db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(state: const Value(PrintJobState.resolved), updatedAt: Value(ctx.nowMs())),
      );
      await ctx.audit(actor, 'print.confirmed_printed', entityType: 'print_job', entityId: jobId);
    });
  }

  Future<void> cancel(Actor actor, String jobId) async {
    actor.require(Permission.viewPrintQueue);
    await _db.transaction(() async {
      final job = await _job(jobId);
      if (![
        PrintJobState.queued,
        PrintJobState.failed,
        PrintJobState.unknown,
        PrintJobState.held,
      ].contains(job.state)) {
        throw ConflictException('A job that is "${PrintJobState.label(job.state)}" cannot be cancelled');
      }
      await (_db.update(_db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(state: const Value(PrintJobState.cancelled), updatedAt: Value(ctx.nowMs())),
      );
      await ctx.audit(actor, 'print.cancelled', entityType: 'print_job', entityId: jobId, details: {'from': job.state});
    });
  }
}
