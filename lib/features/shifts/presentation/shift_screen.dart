import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/presentation/lock_screen.dart';
import '../../bills/domain/payment_method.dart';
import '../application/shift_service.dart';

Future<bool?> showOpenShiftDialog(BuildContext context, WidgetRef ref) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Open a shift'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Count the cash in the drawer before the first sale.'),
          const SizedBox(height: 12),
          MoneyField(controller: ctrl, label: 'Opening cash (float)', autofocus: true),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Open shift')),
      ],
    ),
  );
  if (ok != true || !context.mounted) {
    ctrl.dispose();
    return false;
  }
  final services = ref.read(servicesProvider);
  final r = await guard(
    context,
    () => services.shifts.openShift(requireActor(ref), openingFloat: money.parse(ctrl.text.isEmpty ? '0' : ctrl.text)),
    success: 'Shift opened',
  );
  ctrl.dispose();
  return r != null;
}

class ShiftScreen extends ConsumerWidget {
  const ShiftScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shift = ref.watch(currentShiftProvider);
    return shift.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e),
      data: (s) => s == null ? const _NoShift() : _OpenShift(shift: s),
    );
  }
}

class _NoShift extends ConsumerWidget {
  const _NoShift();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EmptyState(
          icon: Icons.lock_clock_outlined,
          title: 'No shift is open',
          message:
              'Open a shift with the starting cash before taking payments. One shift can be open at a time on this device.',
          action: FilledButton.icon(
            icon: const Icon(Icons.lock_open),
            label: const Text('Open shift'),
            onPressed: () => showOpenShiftDialog(context, ref),
          ),
        ),
        const SizedBox(height: 16),
        Text('Recent shifts', style: Theme.of(context).textTheme.titleMedium),
        FutureView<List<ShiftRow>>(
          future: services.shifts.recentShifts(),
          builder: (context, shifts) => Column(
            children: [
              for (final s in shifts) _ShiftHistoryTile(shift: s, canReopen: s == shifts.first),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShiftHistoryTile extends ConsumerWidget {
  const _ShiftHistoryTile({required this.shift, required this.canReopen});
  final ShiftRow shift;
  final bool canReopen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return FutureView<List<ShiftClosureRow>>(
      future: services.shifts.closures(shift.id),
      builder: (context, closures) {
        final last = closures.isEmpty ? null : closures.last;
        return Card(
          child: ListTile(
            title: Text('${shift.businessDate} · opened by ${shift.openedByName}'),
            subtitle: Text(
              last == null
                  ? 'Open'
                  : 'Expected ${formatMoney(last.expectedCash)} · counted ${formatMoney(last.countedCash)} · '
                        'variance ${formatMoney(last.variance)}${closures.length > 1 ? ' · closed ${closures.length} times' : ''}',
            ),
            trailing: canReopen && shift.status == 'closed'
                ? TextButton(
                    onPressed: () async {
                      final reason = await askReason(context, title: 'Reopen this shift?');
                      if (reason == null || !context.mounted) return;
                      await withOwnerApproval(
                        context,
                        ref,
                        purpose: 'Reopening a closed shift',
                        action: (a) =>
                            services.shifts.reopenShift(requireActor(ref), shift.id, approval: a, reason: reason),
                        success: 'Shift reopened',
                      );
                    },
                    child: const Text('Reopen'),
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _OpenShift extends ConsumerStatefulWidget {
  const _OpenShift({required this.shift});
  final ShiftRow shift;
  @override
  ConsumerState<_OpenShift> createState() => _OpenShiftState();
}

class _OpenShiftState extends ConsumerState<_OpenShift> {
  int _refresh = 0;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    return FutureView<(ShiftSummary, List<CashMovementRow>)>(
      key: ValueKey(_refresh),
      future: (() async =>
          (await services.shifts.summary(widget.shift.id), await services.shifts.movements(widget.shift.id)))(),
      builder: (context, data) {
        final (s, moves) = data;
        return RefreshIndicator(
          onRefresh: () async => setState(() => _refresh++),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SectionCard(
                title: 'Cash drawer',
                subtitle: 'Opened ${formatLocalMs(widget.shift.openedAt)} by ${widget.shift.openedByName}',
                trailing: IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => setState(() => _refresh++),
                  icon: const Icon(Icons.refresh),
                ),
                child: Column(
                  children: [
                    MoneyRow('Opening float', s.shift.openingFloat),
                    MoneyRow('+ Cash sales (amount applied)', s.cashReceipts),
                    MoneyRow('− Cash refunds', -s.cashRefunds),
                    MoneyRow('+ Cash in', s.cashIn),
                    MoneyRow('− Cash out', -s.cashOut),
                    MoneyRow('− Expenses paid from drawer', -s.drawerExpenses),
                    const Divider(),
                    MoneyRow('Expected cash in drawer', s.expectedCash, bold: true, big: true),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SectionCard(
                title: 'This shift',
                child: Column(
                  children: [
                    MoneyRow('${s.billCount} bill(s)', s.salesTotal),
                    for (final m in PaymentMethod.values)
                      if ((s.receiptsByMethod[m.code] ?? 0) > 0)
                        MoneyRow('${m.label} received', s.receiptsByMethod[m.code]!),
                    for (final m in PaymentMethod.values)
                      if ((s.refundsByMethod[m.code] ?? 0) > 0)
                        MoneyRow('${m.label} refunded', -s.refundsByMethod[m.code]!),
                    if (s.otherExpenses > 0) MoneyRow('Expenses not from drawer', s.otherExpenses),
                    if (s.openOrders > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: StatusChip(label: '${s.openOrders} open order(s)', color: AppColors.warning),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Cash in'),
                    onPressed: () => _movement(true),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.remove),
                    label: const Text('Cash out'),
                    onPressed: () => _movement(false),
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.lock),
                    label: const Text('Close shift'),
                    onPressed: () => _close(s),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (moves.isNotEmpty)
                SectionCard(
                  title: 'Drawer movements',
                  child: Column(
                    children: [
                      for (final m in moves)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${m.direction == 'in' ? 'Cash in' : 'Cash out'} · ${formatMoney(m.amount)}'),
                          subtitle: Text('${formatLocalMs(m.createdAt)} · ${m.reason} · ${m.createdByName}'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _movement(bool cashIn) async {
    final amount = TextEditingController();
    final reason = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(cashIn ? 'Cash into drawer' : 'Cash out of drawer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyField(controller: amount, label: 'Amount', autofocus: true),
            const SizedBox(height: 12),
            TextField(
              controller: reason,
              maxLength: 140,
              decoration: const InputDecoration(labelText: 'Reason (required)'),
            ),
            if (!cashIn) const Text('Paying a supplier? Record it under Expenses instead so it is not counted twice.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true && mounted) {
      final services = ref.read(servicesProvider);
      await guard(context, () async {
        final a = tryParseMoney(amount.text);
        if (a == null) throw const ValidationException('Enter an amount');
        await services.shifts.recordCashMovement(requireActor(ref), cashIn: cashIn, amount: a, reason: reason.text);
      }, success: 'Saved');
      if (mounted) setState(() => _refresh++);
    }
    amount.dispose();
    reason.dispose();
  }

  Future<void> _close(ShiftSummary s) async {
    final counted = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) {
          final value = tryParseMoney(counted.text);
          return AlertDialog(
            title: const Text('Close shift'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Expected cash: ${formatMoney(s.expectedCash)}'),
                const SizedBox(height: 12),
                MoneyField(
                  controller: counted,
                  label: 'Cash counted in drawer',
                  autofocus: true,
                  onChanged: (_) => setLocal(() {}),
                ),
                if (value != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Variance: ${formatMoney(value - s.expectedCash)}',
                      style: TextStyle(
                        color: value == s.expectedCash ? AppColors.success : AppColors.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLength: 300,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                if (s.openOrders > 0)
                  Text(
                    '${s.openOrders} order(s) are still open. Bill or cancel them, or an owner can carry them into the next shift.',
                    style: const TextStyle(color: AppColors.warning),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: value == null ? null : () => Navigator.pop(c, true),
                child: const Text('Close shift'),
              ),
            ],
          );
        },
      ),
    );
    if (ok == true && mounted) {
      final services = ref.read(servicesProvider);
      final actor = requireActor(ref);
      final countedValue = tryParseMoney(counted.text)!;
      if (s.openOrders > 0) {
        final carry = await confirm(
          context,
          title: 'Carry open orders?',
          message: 'Close the shift and keep ${s.openOrders} open order(s) for the next shift? This needs an owner.',
          confirmLabel: 'Carry over',
        );
        if (!carry || !mounted) return;
        await withOwnerApproval(
          context,
          ref,
          purpose: 'Closing a shift with open orders',
          action: (a) => services.shifts.closeShift(
            actor,
            countedCash: countedValue,
            note: note.text,
            carryOpenOrders: true,
            approval: a,
          ),
          success: 'Shift closed',
        );
      } else {
        await guard(
          context,
          () => services.shifts.closeShift(actor, countedCash: countedValue, note: note.text),
          success: 'Shift closed',
        );
      }
    }
    counted.dispose();
    note.dispose();
  }
}

Map<String, Object?> decodeSummary(String json) => (jsonDecode(json) as Map).cast<String, Object?>();
