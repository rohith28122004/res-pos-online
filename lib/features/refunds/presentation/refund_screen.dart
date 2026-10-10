import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/lock_screen.dart';
import '../../bills/domain/payment_method.dart';
import '../application/refund_service.dart';

/// Owner-authorised full or partial refund against the original bill. The
/// amounts reverse what was captured on the bill, not today's prices.
class RefundScreen extends ConsumerStatefulWidget {
  const RefundScreen({super.key, required this.billId});
  final String billId;
  @override
  ConsumerState<RefundScreen> createState() => _RefundScreenState();
}

class _RefundScreenState extends ConsumerState<RefundScreen> {
  late final String _operationId = ref.read(servicesProvider).ctx.ids.newId();
  late final Future<RefundableState> _state = ref.read(servicesProvider).refunds.refundableState(widget.billId);
  final _qty = <String, int>{};
  final _charges = <String>{};
  final _reason = TextEditingController();
  final _tenderCtrls = <String, TextEditingController>{};
  bool _customTenders = false;
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    for (final c in _tenderCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(String method) => _tenderCtrls.putIfAbsent(method, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Refund')),
      body: FutureView<RefundableState>(
        future: _state,
        builder: (context, state) {
          RefundPreview? preview;
          String? previewError;
          try {
            preview = services.refunds.preview(state, _qty, _charges.toList());
          } on AppException catch (e) {
            previewError = e.message;
          }
          final t = Theme.of(context).textTheme;
          final refundable = state.refundableByMethod;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Receipt ${state.bill.receiptNo} · total ${formatMoney(state.bill.total)} · refunded so far ${formatMoney(state.refundedTotal)}',
                    style: t.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'The original bill stays unchanged. A refund is recorded on today\'s business date and linked to the bill.',
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Items to refund',
                    child: Column(
                      children: [
                        for (final l in state.lines)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              l.line.variantName == null
                                  ? l.line.itemName
                                  : '${l.line.itemName} (${l.line.variantName})',
                            ),
                            subtitle: Text(
                              'Sold ${l.line.quantity} · already refunded ${l.refundedQuantity} · line total ${formatMoney(l.line.total)}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Less',
                                  onPressed: (_qty[l.line.id] ?? 0) > 0
                                      ? () => setState(() => _qty[l.line.id] = (_qty[l.line.id] ?? 0) - 1)
                                      : null,
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                                Text('${_qty[l.line.id] ?? 0}', style: t.titleMedium),
                                IconButton(
                                  tooltip: 'More',
                                  onPressed: (_qty[l.line.id] ?? 0) < l.remaining
                                      ? () => setState(() => _qty[l.line.id] = (_qty[l.line.id] ?? 0) + 1)
                                      : null,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                          ),
                        for (final c in state.charges)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: c.refunded || _charges.contains(c.charge.id),
                            onChanged: c.refunded
                                ? null
                                : (v) => setState(
                                    () => v == true ? _charges.add(c.charge.id) : _charges.remove(c.charge.id),
                                  ),
                            title: Text(c.charge.label),
                            subtitle: Text(c.refunded ? 'Already refunded' : formatMoney(c.charge.total)),
                          ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() {
                              for (final l in state.lines) {
                                _qty[l.line.id] = l.remaining;
                              }
                              _charges
                                ..clear()
                                ..addAll(state.charges.where((c) => !c.refunded).map((c) => c.charge.id));
                            }),
                            child: const Text('Refund everything remaining'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (previewError != null) Text(previewError, style: const TextStyle(color: AppColors.danger)),
                  if (preview != null && preview.total > 0) ...[
                    SectionCard(
                      title: 'Refund amount',
                      child: Column(
                        children: [
                          MoneyRow('Items (excl. tax)', preview.itemsNetEx),
                          if (preview.chargesNetEx > 0) MoneyRow('Charges (excl. tax)', preview.chargesNetEx),
                          MoneyRow('Tax reversed', preview.taxTotal),
                          if (preview.roundingAdjustment != 0) MoneyRow('Rounding', preview.roundingAdjustment),
                          MoneyRow('Refund total', preview.total, bold: true, big: true),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SectionCard(
                      title: 'Pay the refund by',
                      subtitle: 'Limited to what each method paid on this bill',
                      trailing: Switch(value: _customTenders, onChanged: (v) => setState(() => _customTenders = v)),
                      child: Column(
                        children: [
                          if (!_customTenders)
                            for (final e in preview.defaultTenders.entries.where((e) => e.value > 0))
                              MoneyRow(PaymentMethod.parse(e.key).label, e.value)
                          else
                            for (final m in refundable.keys)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: MoneyField(
                                  controller: _ctrl(m),
                                  label: '${PaymentMethod.parse(m).label} (max ${formatMoney(refundable[m]!)})',
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _reason,
                    maxLength: 200,
                    decoration: const InputDecoration(labelText: 'Reason (required)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.undo),
                    label: Text(
                      preview == null || preview.total == 0 ? 'Refund' : 'Refund ${formatMoney(preview.total)}',
                    ),
                    onPressed: _busy || preview == null || preview.total == 0 || _reason.text.trim().isEmpty
                        ? null
                        : () => _submit(state, preview!),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submit(RefundableState state, RefundPreview preview) async {
    final services = ref.read(servicesProvider);
    final actor = requireActor(ref);
    final ok = await confirm(
      context,
      title: 'Refund ${formatMoney(preview.total)}?',
      message: 'This cannot be undone. Make sure the money is handed back by the chosen method.',
      confirmLabel: 'Refund',
    );
    if (!ok || !mounted) return;
    Map<String, int>? tenders;
    if (_customTenders) {
      tenders = {for (final e in _tenderCtrls.entries) e.key: tryParseMoney(e.value.text) ?? 0};
    }
    setState(() => _busy = true);
    final r = await withOwnerApproval(
      context,
      ref,
      purpose: 'Refund of ${formatMoney(preview.total)} on ${state.bill.receiptNo}',
      action: (approval) => services.refunds.issueRefund(
        actor,
        RefundRequest(
          billId: state.bill.id,
          operationId: _operationId,
          lineQuantities: Map.of(_qty)..removeWhere((_, v) => v == 0),
          chargeIds: _charges.toList(),
          tenders: tenders,
          reason: _reason.text,
          approval: approval,
        ),
      ),
    );
    if (mounted) setState(() => _busy = false);
    if (r != null && mounted) {
      showInfo(context, 'Refund ${r.refundNo} recorded');
      Navigator.pop(context);
    }
  }
}
