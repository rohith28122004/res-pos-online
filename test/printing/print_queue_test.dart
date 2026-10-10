import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cafedesk/core/errors/app_exception.dart';
import 'package:cafedesk/core/printing/documents/layout.dart';
import 'package:cafedesk/core/printing/documents/print_documents.dart';
import 'package:cafedesk/core/printing/encoders/escpos.dart';
import 'package:cafedesk/core/printing/encoders/raster_renderer.dart';
import 'package:cafedesk/core/printing/queue/print_job_writer.dart';
import 'package:cafedesk/core/printing/queue/print_queue.dart';
import 'package:cafedesk/core/printing/transports/tcp_transport.dart';
import 'package:cafedesk/core/printing/transports/transport.dart';
import 'package:cafedesk/features/bills/domain/payment_method.dart';
import 'package:cafedesk/features/settings/application/printer_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Scriptable fake: validates queue logic only — never physical printing.
class FakeTransport implements PrinterTransport {
  final outcomes = <SendResult>[];
  final sent = <PrintPayload>[];
  Completer<void>? gate;

  @override
  Future<SendResult> send(
    PrinterEndpoint endpoint,
    PrintPayload payload, {
    required Duration timeout,
    required String jobName,
  }) async {
    sent.add(payload);
    if (gate != null) await gate!.future;
    return outcomes.isEmpty ? const SendResult.submitted() : outcomes.removeAt(0);
  }

  @override
  Future<SendResult> testConnection(PrinterEndpoint endpoint, {required Duration timeout}) async =>
      const SendResult.submitted();
}

Future<RasterDocument> fakeRaster(List<PrintOp> ops, int width) async => RasterDocument(
  bitmap: MonoBitmap(width: 8, height: 1, data: Uint8List.fromList([0x80])),
  feedLines: 3,
  cut: true,
  drawerPulse: false,
);

void main() {
  late Harness h;
  late FakeTransport fake;
  late PrintQueue queue;
  late PrinterService printers;
  late String printerId;
  late String coffee;

  setUp(() async {
    h = await Harness.create();
    fake = FakeTransport();
    queue = PrintQueue(h.ctx, transports: {TransportType.tcp: fake}, rasterizer: fakeRaster);
    printers = PrinterService(h.ctx);
    final d = PrinterProfileInput.defaults(paperWidthMm: 58, transport: TransportType.tcp);
    printerId = await printers.saveProfile(
      h.owner,
      PrinterProfileInput(
        name: 'Counter',
        role: PrinterRole.both,
        paperWidthMm: 58,
        dotsWidth: d.dotsWidth,
        charsPerLine: d.charsPerLine,
        codePage: d.codePage,
        renderMode: RenderMode.text,
        cutter: d.cutter,
        drawerPulse: false,
        transport: TransportType.tcp,
        endpoint: '192.168.1.40',
        port: 9100,
      ),
    );
    final cat = await h.category('Cafe');
    coffee = await h.item(cat, 'Coffee', 10000);
    await h.openShift();
  });
  tearDown(() => h.dispose());

  Future<String> billAndJob() async {
    final order = await h.orderWith({coffee: 1});
    final r = await h.pay(order, [const TenderInput(method: PaymentMethod.cash, applied: 10000)]);
    return r.printJobIds.single;
  }

  Future<String> state(String jobId) async =>
      (await (h.db.select(h.db.printJobs)..where((j) => j.id.equals(jobId))).getSingle()).state;

  test('job is persisted before sending and submitted after a successful write', () async {
    final job = await billAndJob();
    expect(await state(job), PrintJobState.queued);
    expect(await queue.processJob(job), PrintJobState.submitted);
    expect(fake.sent.single, isA<BytesPayload>());
    final attempts = await (h.db.select(h.db.printAttempts)..where((a) => a.jobId.equals(job))).get();
    expect(attempts.single.outcome, 'submitted');
    expect(attempts.single.byteCount, greaterThan(0));
  });

  test('a print failure never touches the bill', () async {
    final job = await billAndJob();
    fake.outcomes.add(const SendResult.failed('Could not connect'));
    expect(await queue.processJob(job), PrintJobState.failed);
    expect(await h.count(h.db.bills), 1);
    // Failed (definitely not sent) can be retried as the original.
    await printers.retry(h.cashier, job);
    expect(await queue.processJob(job), PrintJobState.submitted);
  });

  test('uncertain outcomes are never resent without an explicit decision', () async {
    final job = await billAndJob();
    fake.outcomes.add(const SendResult.unknown('Connection lost while sending'));
    expect(await queue.processJob(job), PrintJobState.unknown);
    // The worker ignores it.
    expect(await queue.processJob(job), isNull);
    expect(fake.sent.length, 1);
    await expectLater(printers.retry(h.cashier, job), throwsA(isA<ConflictException>()));
    await printers.retry(h.cashier, job, confirmedNotPrinted: true);
    final row = await (h.db.select(h.db.printJobs)..where((j) => j.id.equals(job))).getSingle();
    expect(row.copyLabel, CopyLabel.reprint);
    expect(row.payloadJson, contains('REPRINT'));
    expect(await queue.processJob(job), PrintJobState.submitted);
  });

  test('operator can confirm an uncertain job printed', () async {
    final job = await billAndJob();
    fake.outcomes.add(const SendResult.unknown('timeout'));
    await queue.processJob(job);
    await printers.confirmPrinted(h.cashier, job);
    expect(await state(job), PrintJobState.resolved);
  });

  test('an app crash mid-send turns the job into unknown at next start', () async {
    final job = await billAndJob();
    fake.gate = Completer<void>();
    final inFlight = queue.processJob(job);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(await state(job), PrintJobState.sending);
    // Simulate restart: a new queue recovers before the old send finishes.
    final recovered = await PrintQueue(h.ctx, transports: {TransportType.tcp: fake}).recoverInterrupted();
    expect(recovered, 1);
    expect(await state(job), PrintJobState.unknown);
    final attempt = await (h.db.select(h.db.printAttempts)..where((a) => a.jobId.equals(job))).getSingle();
    expect(attempt.outcome, 'interrupted');
    fake.gate!.complete();
    await inFlight;
  });

  test('unprintable characters in text-only mode fail clearly instead of printing ?', () async {
    final id = await printers.printSamples(h.owner, printerId);
    // The sample contains ₹ (transliterated) only, so text mode works…
    expect(await queue.processJob(id.first), PrintJobState.submitted);
    // …but a Tamil item name cannot be printed in a code page.
    final cat = await h.category('Tamil');
    final tamil = await h.item(cat, 'காபி', 3000);
    final order = await h.orderWith({tamil: 1});
    final r = await h.pay(order, [const TenderInput(method: PaymentMethod.cash, applied: 3000)]);
    expect(await queue.processJob(r.printJobIds.single), PrintJobState.failed);
    final row = await (h.db.select(h.db.printJobs)..where((j) => j.id.equals(r.printJobIds.single))).getSingle();
    expect(row.lastError, contains('cannot be printed'));
  });

  test('auto mode switches to raster for unsupported scripts', () async {
    final p = await printers.profile(printerId);
    await printers.saveProfile(
      h.owner,
      PrinterProfileInput(
        name: p.name,
        role: p.role,
        paperWidthMm: p.paperWidthMm,
        dotsWidth: p.dotsWidth,
        charsPerLine: p.charsPerLine,
        codePage: p.codePage,
        renderMode: RenderMode.auto,
        cutter: p.cutter,
        drawerPulse: false,
        transport: TransportType.tcp,
        endpoint: p.endpoint,
        port: p.port,
      ),
      id: printerId,
    );
    final cat = await h.category('Tamil');
    final tamil = await h.item(cat, 'காபி', 3000);
    final order = await h.orderWith({tamil: 1});
    final r = await h.pay(order, [const TenderInput(method: PaymentMethod.cash, applied: 3000)]);
    expect(await queue.processJob(r.printJobIds.single), PrintJobState.submitted);
    final bytes = (fake.sent.last as BytesPayload).bytes;
    expect(bytes.sublist(2, 5), [0x1D, 0x76, 0x30], reason: 'raster command');
  });

  test('jobs for one printer go out in order, one at a time', () async {
    final a = await billAndJob();
    final b = await billAndJob();
    await queue.start();
    for (var i = 0; i < 50 && (await state(b)) != PrintJobState.submitted; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await queue.stop();
    expect(await state(a), PrintJobState.submitted);
    expect(await state(b), PrintJobState.submitted);
    final attemptsA = await (h.db.select(h.db.printAttempts)..where((x) => x.jobId.equals(a))).getSingle();
    final attemptsB = await (h.db.select(h.db.printAttempts)..where((x) => x.jobId.equals(b))).getSingle();
    expect(attemptsA.finishedAt! <= attemptsB.startedAt, isTrue);
  });

  test('disabled printer: job fails without sending', () async {
    final job = await billAndJob();
    await printers.archiveProfile(h.owner, printerId);
    expect(await state(job), PrintJobState.cancelled);
    expect(fake.sent, isEmpty);
  });

  group('real TCP transport against a local socket', () {
    test('submitted when the printer accepts bytes', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final received = <int>[];
      final done = Completer<void>();
      server.listen((s) => s.listen(received.addAll, onDone: done.complete));
      final r = await const TcpTransport().send(
        PrinterEndpoint(type: TransportType.tcp, address: '127.0.0.1', port: server.port),
        BytesPayload(Uint8List.fromList([0x1B, 0x40, 0x41])),
        timeout: const Duration(seconds: 2),
        jobName: 't',
      );
      await done.future.timeout(const Duration(seconds: 2));
      await server.close();
      expect(r.outcome, SendOutcome.submitted);
      expect(received, [0x1B, 0x40, 0x41]);
    });

    test('failed (safe to retry) when nothing is listening', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = server.port;
      await server.close();
      final r = await const TcpTransport().send(
        PrinterEndpoint(type: TransportType.tcp, address: '127.0.0.1', port: port),
        BytesPayload(Uint8List.fromList([0x41])),
        timeout: const Duration(seconds: 2),
        jobName: 't',
      );
      expect(r.outcome, SendOutcome.failed);
    });

    test('endpoint validation', () {
      expect(validateHost('192.168.1.300'), isNotNull);
      expect(validateHost('printer.local'), isNull);
      expect(validateHost('bad host'), isNotNull);
      expect(validatePort(0), isNotNull);
      expect(validatePort(9100), isNull);
      expect(validateBluetoothAddress('00:11:22:33:44:55'), isNull);
      expect(validateBluetoothAddress('nope'), isNotNull);
    });
  });
}
