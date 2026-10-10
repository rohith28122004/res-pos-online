import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/database/app_database.dart';
import '../../../core/errors/app_exception.dart';
import '../../../core/security/permissions.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../../bills/presentation/bills_screen.dart';
import '../application/expense_service.dart';

/// Expenses are recorded separately from sales and refunds.
class ExpensesScreen extends ConsumerStatefulWidget {
  const ExpensesScreen({super.key});
  @override
  ConsumerState<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends ConsumerState<ExpensesScreen> {
  RangePreset _preset = RangePreset.today;
  BusinessDateRange? _custom;

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
        onPressed: () => _add(context),
      ),
      body: Column(
        children: [
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final p in [
                  RangePreset.today,
                  RangePreset.yesterday,
                  RangePreset.last7Days,
                  RangePreset.thisMonth,
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(presetLabel(p)),
                      selected: _preset == p,
                      onSelected: (_) => setState(() => _preset = p),
                    ),
                  ),
                ChoiceChip(
                  label: Text(
                    _preset == RangePreset.custom && _custom != null
                        ? '${_custom!.start} – ${_custom!.lastDay}'
                        : 'Custom…',
                  ),
                  selected: _preset == RangePreset.custom,
                  onSelected: (_) async {
                    final r = await pickBusinessRange(context);
                    if (r != null) {
                      setState(() {
                        _custom = r;
                        _preset = RangePreset.custom;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: FutureView<BusinessDateRange>(
              key: ValueKey('$_preset$_custom'),
              future: (() async => _preset == RangePreset.custom
                  ? _custom!
                  : (await services.ctx.calendar()).preset(_preset, DateTime.now().toUtc()))(),
              builder: (context, range) => StreamView<List<ExpenseRow>>(
                stream: services.expenses.watchExpenses(range),
                builder: (context, list) {
                  if (list.isEmpty) {
                    return const EmptyState(icon: Icons.payments_outlined, title: 'No expenses in this period');
                  }
                  final active = list.where((e) => e.voidedAt == null);
                  final total = active.fold<int>(0, (a, e) => a + e.amount);
                  final drawer = active.where((e) => e.paidFromDrawer).fold<int>(0, (a, e) => a + e.amount);
                  return ListView(
                    padding: const EdgeInsets.only(bottom: 96),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Total ${formatMoney(total)} · from drawer ${formatMoney(drawer)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final e in list)
                        ListTile(
                          title: Text(
                            '${e.category} · ${formatMoney(e.amount)}',
                            style: e.voidedAt != null ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
                          ),
                          subtitle: Text(
                            [
                              e.businessDate,
                              e.createdByName,
                              if (e.paidFromDrawer) 'from drawer',
                              ?e.note,
                              if (e.voidedAt != null) 'VOID: ${e.voidReason}',
                            ].join(' · '),
                          ),
                          trailing: e.voidedAt == null && actor.can(Permission.voidExpense)
                              ? IconButton(
                                  tooltip: 'Void expense',
                                  icon: const Icon(Icons.block),
                                  onPressed: () async {
                                    final reason = await askReason(
                                      context,
                                      title: 'Void this expense?',
                                      confirmLabel: 'Void',
                                    );
                                    if (reason != null && context.mounted) {
                                      await guard(
                                        context,
                                        () => services.expenses.voidExpense(actor, e.id, reason: reason),
                                        success: 'Expense voided',
                                      );
                                    }
                                  },
                                )
                              : (e.voidedAt != null ? const StatusChip(label: 'Void', color: AppColors.danger) : null),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final category = TextEditingController();
    var drawer = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Add expense'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Autocomplete<String>(
                  optionsBuilder: (v) =>
                      expenseCategorySuggestions.where((s) => s.toLowerCase().contains(v.text.toLowerCase())),
                  onSelected: (v) => category.text = v,
                  fieldViewBuilder: (context, ctrl, focus, _) => TextField(
                    controller: ctrl,
                    focusNode: focus,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Category'),
                    onChanged: (v) => category.text = v,
                  ),
                ),
                const SizedBox(height: 12),
                MoneyField(controller: amount, label: 'Amount'),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Note (optional)'),
                ),
                SwitchListTile(
                  value: drawer,
                  onChanged: (v) => setLocal(() => drawer = v),
                  title: const Text('Paid from the cash drawer'),
                  subtitle: const Text('Reduces the expected cash for the open shift'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) {
      final services = ref.read(servicesProvider);
      await guard(context, () async {
        final a = tryParseMoney(amount.text);
        if (a == null) throw const ValidationException('Enter an amount');
        await services.expenses.addExpense(
          requireActor(ref),
          category: category.text,
          amount: a,
          note: note.text,
          paidFromDrawer: drawer,
        );
      }, success: 'Expense saved');
    }
    amount.dispose();
    note.dispose();
    category.dispose();
  }
}
