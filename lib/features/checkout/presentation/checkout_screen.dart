import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/printing/queue/print_job_writer.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/lock_screen.dart';
import '../../bills/domain/payment_method.dart';
import '../../bills/presentation/bill_detail_screen.dart';
import '../../orders/domain/order_models.dart';
import '../../shifts/presentation/shift_screen.dart';
import '../application/checkout_service.dart';

class _TenderRow {
  _TenderRow(this.method, {String applied = '', String received = ''})
    : applied = TextEditingController(text: applied),
      received = TextEditingController(text: received);
  PaymentMethod method;
  final TextEditingController applied;
  final TextEditingController received;

  void dispose() {
    applied.dispose();
    received.dispose();
  }
}

/// Manual payment recording. Selecting UPI or card does not verify anything
/// with a bank — staff confirm they received the money.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key, required this.orderId});
  final String orderId;
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  /// One id for this payment attempt: double taps and retries reuse it, so
  /// the order can only ever be billed once.
  late final String _operationId = ref.read(servicesProvider).ctx.ids.newId();
  late final Stream<OrderDetail> _order = ref.read(servicesProvider).orders.watchOrder(widget.orderId);
  final _rows = <_TenderRow>[];
  bool _split = false;
  bool _confirmed = false;
  bool _busy = false;
  PaymentMethod _single = PaymentMethod.cash;
  final _cashReceived = TextEditingController();

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _cashReceived.dispose();
    super.dispose();
  }

  List<TenderInput>? _tenders(int total) {
    if (!_split) {
      if (_single == PaymentMethod.cash) {
        final received = tryParseMoney(_cashReceived.text) ?? total;
        return [TenderInput(method: PaymentMethod.cash, applied: total, tendered: received)];
      }
      return [TenderInput(method: _single, applied: total)];
    }
    final out = <TenderInput>[];
    for (final r in _rows) {
      final applied = tryParseMoney(r.applied.text);
      if (applied == null || applied == 0) continue;
      final received = r.method == PaymentMethod.cash ? (tryParseMoney(r.received.text) ?? applied) : applied;
      out.add(TenderInput(method: r.method, applied: applied, tendered: received));
    }
    return out;
  }

  Future<void> _finalize(OrderDetail detail) async {
    final total = detail.pricing!.total;
    final tenders = _tenders(total)!;
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    if (await services.shifts.currentShift() == null) {
      if (!mounted) return;
      final opened = await showOpenShiftDialog(context, ref);
      if (opened != true || !mounted) return;
    }
    setState(() => _busy = true);
    FinalizeResult? result;
    try {
      result = await services.checkout.finalize(
        actor,
        FinalizeRequest(
          orderId: widget.orderId,
          operationId: _operationId,
          tenders: tenders,
          paymentConfirmed: _confirmed,
        ),
      );
    } on ApprovalRequiredException catch (e) {
      if (mounted) {
        final approval = await requestOwnerApproval(context, ref, purpose: e.message);
        if (approval != null && mounted) {
          result = await guard(
            context,
            () => services.checkout.finalize(
              actor,
              FinalizeRequest(
                orderId: widget.orderId,
                operationId: _operationId,
                tenders: tenders,
                paymentConfirmed: _confirmed,
                approval: approval,
              ),
            ),
          );
        }
      }
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (result != null && mounted) {
      await Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute<void>(builder: (_) => BillSavedScreen(result: result!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamView<OrderDetail>(
      stream: _order,
      builder: (context, detail) {
        final pricing = detail.pricing;
        if (pricing == null) {
          return Scaffold(
            appBar: AppBar(),
            body: ErrorView(error: detail.pricingError ?? 'Pricing error'),
          );
        }
        final total = pricing.total;
        final tenders = _tenders(total) ?? const [];
        final applied = tenders.fold<int>(0, (a, t) => a + t.applied);
        final change = tenders.fold<int>(0, (a, t) => a + (t.change > 0 ? t.change : 0));
        final remaining = total - applied;
        final cashShort = tenders.any((t) => t.tendered < t.applied);
        final valid = total == 0 || (remaining == 0 && !cashShort && _confirmed && tenders.isNotEmpty);
        final t = Theme.of(context).textTheme;

        return Scaffold(
          appBar: AppBar(title: Text('Payment · ${detail.reference}')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Amount due', style: t.titleMedium),
                          Text(formatMoney(total), style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700)),
                          if (pricing.taxTotal > 0)
                            Text('includes ${formatMoney(pricing.taxTotal)} tax', style: t.bodySmall),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (total > 0) ...[
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Single payment')),
                        ButtonSegment(value: true, label: Text('Split payment')),
                      ],
                      selected: {_split},
                      onSelectionChanged: (s) => setState(() {
                        _split = s.first;
                        if (_split && _rows.isEmpty) {
                          _rows.add(_TenderRow(PaymentMethod.cash, applied: money.plain(total)));
                        }
                      }),
                    ),
                    const SizedBox(height: 16),
                    if (!_split) ...[
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final m in PaymentMethod.values)
                            ChoiceChip(
                              label: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(m.label, style: const TextStyle(fontSize: 16)),
                              ),
                              selected: _single == m,
                              onSelected: (_) => setState(() => _single = m),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_single == PaymentMethod.cash) ...[
                        MoneyField(
                          controller: _cashReceived,
                          label: 'Cash received (leave empty for exact)',
                          autofocus: true,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final quick in _quickCash(total))
                              ActionChip(
                                label: Text(formatMoney(quick)),
                                onPressed: () => setState(() => _cashReceived.text = money.plain(quick)),
                              ),
                          ],
                        ),
                      ],
                    ] else ...[
                      for (final r in _rows) _splitRow(r),
                      TextButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('Add payment'),
                        onPressed: () => setState(
                          () => _rows.add(
                            _TenderRow(PaymentMethod.upi, applied: remaining > 0 ? money.plain(remaining) : ''),
                          ),
                        ),
                      ),
                      MoneyRow(
                        'Still to pay',
                        remaining < 0 ? 0 : remaining,
                        bold: true,
                        color: remaining == 0 ? AppColors.success : AppColors.danger,
                      ),
                      if (remaining < 0)
                        const Text(
                          'Payments are more than the bill. Enter extra cash as "cash received" so it is shown as change.',
                          style: TextStyle(color: AppColors.danger),
                        ),
                    ],
                    const SizedBox(height: 12),
                    if (change > 0)
                      Card(
                        color: const Color(0xFFE8F5E9),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Text('Change to give', style: t.titleMedium),
                              const Spacer(),
                              Text(formatMoney(change), style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    if (cashShort)
                      const Text(
                        'Cash received is less than the cash amount.',
                        style: TextStyle(color: AppColors.danger),
                      ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: _confirmed,
                      onChanged: (v) => setState(() => _confirmed = v ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('I have received this payment'),
                      subtitle: const Text(
                        'UPI and card payments are recorded manually. CaféDesk does not check them with any bank.',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    icon: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.check),
                    label: Text(total == 0 ? 'Complete free bill' : 'Complete sale'),
                    onPressed: !valid || _busy ? null : () => _finalize(detail),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _splitRow(_TenderRow r) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: DropdownButtonFormField<PaymentMethod>(
            isExpanded: true,
            initialValue: r.method,
            items: [for (final m in PaymentMethod.values) DropdownMenuItem(value: m, child: Text(m.label))],
            onChanged: (m) => setState(() => r.method = m ?? r.method),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: MoneyField(controller: r.applied, label: 'Amount', onChanged: (_) => setState(() {})),
        ),
        if (r.method == PaymentMethod.cash) ...[
          const SizedBox(width: 8),
          Expanded(
            child: MoneyField(controller: r.received, label: 'Cash received', onChanged: (_) => setState(() {})),
          ),
        ],
        IconButton(
          tooltip: 'Remove payment',
          onPressed: () => setState(() {
            _rows.remove(r);
            r.dispose();
          }),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  static List<int> _quickCash(int total) {
    final out = <int>{total};
    for (final step in [5000, 10000, 20000, 50000, 200000]) {
      final up = ((total + step - 1) ~/ step) * step;
      if (up > total) out.add(up);
    }
    return out.toList()..sort();
  }
}

/// Shown after a successful sale. The bill is already saved; printing
/// happens separately and can be retried without touching the bill.
class BillSavedScreen extends ConsumerWidget {
  const BillSavedScreen({super.key, required this.result});
  final FinalizeResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Sale complete'), automaticallyImplyLeading: false),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 64),
                const SizedBox(height: 8),
                Text('Bill ${result.receiptNo} saved', style: t.headlineSmall, textAlign: TextAlign.center),
                Text(formatMoney(result.total), style: t.titleLarge, textAlign: TextAlign.center),
                if (result.change > 0) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: const Color(0xFFE8F5E9),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Text('Give change', style: t.titleMedium),
                          Text(
                            formatMoney(result.change),
                            style: t.displaySmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                StreamView<List<PrintJobRow>>(
                  stream: (services.ctx.db.select(
                    services.ctx.db.printJobs,
                  )..where((j) => j.id.isIn(result.printJobIds))).watch(),
                  builder: (context, jobs) {
                    if (jobs.isEmpty) {
                      return const Text(
                        'No receipt printer is set up. The bill is saved — you can print it later from Bills.',
                        textAlign: TextAlign.center,
                      );
                    }
                    return Column(
                      children: [
                        for (final j in jobs)
                          ListTile(
                            leading: Icon(_jobIcon(j.state), color: _jobColor(j.state)),
                            title: Text('Receipt: ${PrintJobState.label(j.state)}'),
                            subtitle: j.lastError == null ? null : Text(j.lastError!),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).popUntil((r) => r.isFirst),
                  child: const Text('Done'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute<void>(builder: (_) => BillDetailScreen(billId: result.billId))),
                  child: const Text('View bill / reprint'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _jobIcon(String state) => switch (state) {
  PrintJobState.submitted || PrintJobState.resolved => Icons.print,
  PrintJobState.failed => Icons.print_disabled,
  PrintJobState.unknown => Icons.help_outline,
  _ => Icons.hourglass_top,
};

Color _jobColor(String state) => switch (state) {
  PrintJobState.submitted || PrintJobState.resolved => AppColors.success,
  PrintJobState.failed => AppColors.danger,
  PrintJobState.unknown || PrintJobState.held => AppColors.warning,
  _ => AppColors.info,
};

Color printJobColor(String state) => _jobColor(state);
IconData printJobIcon(String state) => _jobIcon(state);
