import 'dart:async';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';
import '../../errors/app_exception.dart';
import '../../service_context.dart';
import '../documents/layout.dart';
import '../documents/print_documents.dart';
import '../encoders/escpos.dart';
import '../encoders/raster_renderer.dart';
import '../transports/transport.dart';
import 'print_job_writer.dart';

typedef Rasterizer = Future<RasterDocument> Function(List<PrintOp> ops, int dotsWidth);

abstract final class RenderMode {
  /// Code-page text; refuse to print characters the code page lacks.
  static const text = 'text';

  /// Code-page text, switching to raster when a character is unsupported.
  static const auto = 'auto';

  /// Always rasterise (best for ₹ and non-Latin scripts; slower).
  static const raster = 'raster';

  static String label(String m) => switch (m) {
    text => 'Text only',
    auto => 'Text, image when needed',
    raster => 'Always image',
    _ => m,
  };
}

PrinterEndpoint endpointOf(PrinterProfileRow p) =>
    PrinterEndpoint(type: TransportType.parse(p.transport), address: p.endpoint, port: p.port);

/// Converts a persisted job into transport payload for its printer.
/// Pure layout/encoding — never calculates amounts.
class JobRenderer {
  JobRenderer({Rasterizer? rasterizer})
    : _rasterize = rasterizer ?? ((ops, width) => renderRaster(ops, dotsWidth: width));

  final Rasterizer _rasterize;

  Future<(PrintPayload, int)> render(PrintJobRow job, PrinterProfileRow profile) async {
    final doc = decodeDocument(job.payloadJson);
    final transport = TransportType.parse(profile.transport);
    final cutter = CutMode.parse(profile.cutter);
    final pulse = profile.drawerPulse && job.documentType == DocumentType.receipt && job.copyLabel == null;
    LayoutOptions options(String currency) => LayoutOptions(
      charsPerLine: profile.charsPerLine,
      currencyLabel: currency,
      feedLines: profile.feedLines,
      cut: cutter != CutMode.none,
      drawerPulse: pulse,
    );

    Future<(PrintPayload, int)> raster() async {
      final r = await _rasterize(layoutDocument(doc, options('₹')), profile.dotsWidth);
      if (transport == TransportType.windowsDriver) return (RasterPayload(r.bitmap), r.bitmap.data.length);
      final bytes = EscPosRasterEncoder(
        cutMode: cutter,
      ).encode(r.bitmap, feedLines: r.feedLines, cut: r.cut, drawerPulse: r.drawerPulse);
      return (BytesPayload(bytes), bytes.length);
    }

    if (transport == TransportType.windowsDriver || profile.renderMode == RenderMode.raster) return raster();
    final encoder = EscPosTextEncoder(
      codePage: CodePage.parse(profile.codePage),
      charsPerLine: profile.charsPerLine,
      cutMode: cutter,
    );
    try {
      final Uint8List bytes = encoder.encode(layoutDocument(doc, options('INR')));
      return (BytesPayload(bytes), bytes.length);
    } on UnsupportedCharactersError catch (e) {
      if (profile.renderMode == RenderMode.auto) return raster();
      throw PrintException(
        '${e.characters.join(' ')} cannot be printed in ${CodePage.parse(profile.codePage).label}. '
        'Set this printer to "Text, image when needed" or "Always image".',
      );
    }
  }
}

/// Durable, sequential-per-printer print queue.
///
/// A job is claimed (state `sending` + an attempt row) in its own committed
/// transaction before any byte is sent. If the app dies mid-send the job is
/// still `sending` at next launch and becomes `unknown`. Unknown jobs are
/// never resent automatically — staff check the printer and choose.
class PrintQueue {
  PrintQueue(this.ctx, {required this.transports, Rasterizer? rasterizer})
    : _renderer = JobRenderer(rasterizer: rasterizer);

  final ServiceContext ctx;
  final Map<TransportType, PrinterTransport> transports;
  final JobRenderer _renderer;
  final _busy = <String>{};
  StreamSubscription<Set<TableUpdate>>? _sub;
  Timer? _timer;
  bool _stopped = false;
  bool _draining = false;
  bool _drainAgain = false;

  AppDatabase get _db => ctx.db;

  /// Marks jobs interrupted by a crash/restart as unknown. Call before start.
  Future<int> recoverInterrupted() async {
    return _db.transaction(() async {
      final sending = await (_db.select(_db.printJobs)..where((j) => j.state.equals(PrintJobState.sending))).get();
      final now = ctx.nowMs();
      for (final j in sending) {
        await (_db.update(_db.printJobs)..where((x) => x.id.equals(j.id))).write(
          PrintJobsCompanion(
            state: const Value(PrintJobState.unknown),
            lastError: const Value('The app stopped while this was printing. Check the printer before reprinting.'),
            updatedAt: Value(now),
          ),
        );
        await (_db.update(_db.printAttempts)..where((a) => a.jobId.equals(j.id) & a.finishedAt.isNull())).write(
          PrintAttemptsCompanion(finishedAt: Value(now), outcome: const Value('interrupted')),
        );
      }
      if (sending.isNotEmpty) {
        await ctx.audit(null, 'print.interrupted', details: {'jobs': sending.length});
      }
      return sending.length;
    });
  }

  Future<void> start() async {
    _stopped = false;
    await recoverInterrupted();
    _sub = _db.tableUpdates(TableUpdateQuery.onTable(_db.printJobs)).listen((_) => kick());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => kick());
    kick();
  }

  Future<void> stop() async {
    _stopped = true;
    await _sub?.cancel();
    _timer?.cancel();
    _sub = null;
    _timer = null;
  }

  void kick() {
    if (_stopped) return;
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining) {
      _drainAgain = true;
      return;
    }
    _draining = true;
    try {
      do {
        _drainAgain = false;
        final queued =
            await (_db.select(_db.printJobs)
                  ..where((j) => j.state.equals(PrintJobState.queued))
                  ..orderBy([(j) => OrderingTerm(expression: j.createdAt)]))
                .get();
        for (final printerId in queued.map((j) => j.printerProfileId).toSet()) {
          if (_busy.add(printerId)) {
            unawaited(
              _runPrinter(printerId).whenComplete(() {
                _busy.remove(printerId);
              }),
            );
          }
        }
      } while (_drainAgain && !_stopped);
    } finally {
      _draining = false;
    }
  }

  Future<void> _runPrinter(String printerId) async {
    while (!_stopped) {
      final next =
          await (_db.select(_db.printJobs)
                ..where((j) => j.printerProfileId.equals(printerId) & j.state.equals(PrintJobState.queued))
                ..orderBy([(j) => OrderingTerm(expression: j.createdAt)])
                ..limit(1))
              .getSingleOrNull();
      if (next == null) return;
      await processJob(next.id);
    }
  }

  /// Claims and sends one job. Returns the final state, or null if the job
  /// was not in the queued state.
  Future<String?> processJob(String jobId) async {
    final attemptId = ctx.ids.newId();
    final claimed = await _db.transaction(() async {
      final job = await (_db.select(_db.printJobs)..where((j) => j.id.equals(jobId))).getSingleOrNull();
      if (job == null || job.state != PrintJobState.queued) return null;
      final now = ctx.nowMs();
      await (_db.update(_db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(
          state: const Value(PrintJobState.sending),
          attemptCount: Value(job.attemptCount + 1),
          updatedAt: Value(now),
        ),
      );
      await _db
          .into(_db.printAttempts)
          .insert(PrintAttemptsCompanion.insert(id: attemptId, jobId: jobId, startedAt: now));
      return job;
    });
    if (claimed == null) return null;

    final result = await _send(claimed);
    final byteCount = result.$2;

    final outcome = result.$1;
    final state = switch (outcome.outcome) {
      SendOutcome.submitted => PrintJobState.submitted,
      SendOutcome.failed => PrintJobState.failed,
      SendOutcome.unknown => PrintJobState.unknown,
    };
    await _db.transaction(() async {
      final now = ctx.nowMs();
      await (_db.update(_db.printJobs)..where((j) => j.id.equals(jobId))).write(
        PrintJobsCompanion(
          state: Value(state),
          lastError: Value(outcome.error),
          updatedAt: Value(now),
        ),
      );
      await (_db.update(_db.printAttempts)..where((a) => a.id.equals(attemptId))).write(
        PrintAttemptsCompanion(
          finishedAt: Value(now),
          outcome: Value(outcome.outcome.name),
          error: Value(outcome.error),
          byteCount: Value(byteCount),
        ),
      );
    });
    return state;
  }

  Future<(SendResult, int)> _send(PrintJobRow job) async {
    final profile = await (_db.select(
      _db.printerProfiles,
    )..where((p) => p.id.equals(job.printerProfileId))).getSingleOrNull();
    if (profile == null || !profile.enabled || profile.archived) {
      return (const SendResult.failed('This printer is disabled or was removed'), 0);
    }
    final type = TransportType.parse(profile.transport);
    final transport = transports[type];
    if (transport == null) return (SendResult.failed('${type.label} is not available on this device'), 0);

    final PrintPayload payload;
    final int byteCount;
    try {
      (payload, byteCount) = await _renderer.render(job, profile);
    } on AppException catch (e) {
      return (SendResult.failed(e.message), 0);
    } on Object catch (e) {
      return (SendResult.failed('Could not prepare the document: $e'), 0);
    }
    final timeout = Duration(milliseconds: profile.timeoutMs);
    try {
      final r = await transport
          .send(endpointOf(profile), payload, timeout: timeout, jobName: 'CafeDesk ${job.documentType}')
          .timeout(timeout * 4 + const Duration(seconds: 5));
      return (r, byteCount);
    } on TimeoutException {
      return (const SendResult.unknown('The printer did not respond in time'), byteCount);
    } on Object catch (e) {
      return (SendResult.unknown('Printing stopped unexpectedly: $e'), byteCount);
    }
  }
}
