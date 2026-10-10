import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../../orders/domain/order_models.dart';
import '../application/bill_service.dart';
import '../domain/payment_method.dart';
import 'bill_detail_screen.dart';

class BillsScreen extends ConsumerStatefulWidget {
  const BillsScreen({super.key});
  @override
  ConsumerState<BillsScreen> createState() => _BillsScreenState();
}

class _BillsScreenState extends ConsumerState<BillsScreen> {
  final _search = TextEditingController();
  RangePreset _preset = RangePreset.today;
  BusinessDateRange? _custom;
  PaymentMethod? _method;
  int _refresh = 0;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<BusinessDateRange?> _range() async {
    if (_preset == RangePreset.custom) return _custom;
    final calendar = await ref.read(servicesProvider).ctx.calendar();
    return calendar.preset(_preset, DateTime.now().toUtc());
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    final calendarFuture = services.ctx.calendar();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            controller: _search,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Receipt number, table or order number',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            children: [
              for (final p in [RangePreset.today, RangePreset.yesterday, RangePreset.last7Days, RangePreset.thisMonth])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(presetLabel(p)),
                    selected: _preset == p,
                    onSelected: (_) => setState(() => _preset = p),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ChoiceChip(
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
              ),
              for (final m in PaymentMethod.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(m.label),
                    selected: _method == m,
                    onSelected: (on) => setState(() => _method = on ? m : null),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: FutureView<(List<BillListItem>, BusinessCalendar)>(
            key: ValueKey('$_preset$_custom$_method${_search.text}$_refresh'),
            future: () async {
              final range = await _range();
              final list = await services.bills.search(
                actor,
                BillSearchQuery(text: _search.text, range: range, method: _method),
              );
              return (list, await calendarFuture);
            }(),
            builder: (context, data) {
              final (bills, calendar) = data;
              if (bills.isEmpty) {
                return const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'No bills found',
                  message: 'Try another date range or search.',
                );
              }
              final total = bills.fold<int>(0, (a, b) => a + b.bill.total);
              return RefreshIndicator(
                onRefresh: () async => setState(() => _refresh++),
                child: ListView.separated(
                  itemCount: bills.length + 1,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          '${bills.length} bill(s) · ${formatMoney(total)}${bills.length == 200 ? ' (showing the latest 200)' : ''}',
                        ),
                      );
                    }
                    final b = bills[i - 1];
                    return ListTile(
                      title: Text('${b.bill.receiptNo} · ${formatMoney(b.bill.total)}'),
                      subtitle: Text(
                        [
                          calendar.formatLocal(DateTime.fromMillisecondsSinceEpoch(b.bill.createdAt, isUtc: true)),
                          OrderType.parse(b.bill.orderType).label,
                          ?b.bill.tableLabel,
                          b.methods.join(' + '),
                        ].join(' · '),
                      ),
                      trailing: b.refunded > 0
                          ? StatusChip(label: 'Refunded ${formatMoney(b.refunded)}', color: AppColors.warning)
                          : const Icon(Icons.chevron_right),
                      onTap: () async {
                        await Navigator.of(
                          context,
                        ).push(MaterialPageRoute<void>(builder: (_) => BillDetailScreen(billId: b.bill.id)));
                        if (mounted) setState(() => _refresh++);
                      },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

String presetLabel(RangePreset p) => switch (p) {
  RangePreset.today => 'Today',
  RangePreset.yesterday => 'Yesterday',
  RangePreset.last7Days => 'Last 7 days',
  RangePreset.thisMonth => 'This month',
  RangePreset.custom => 'Custom',
};

/// Picks an inclusive date range and returns it as `[start, end)`.
Future<BusinessDateRange?> pickBusinessRange(BuildContext context) async {
  final now = DateTime.now();
  final r = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2020),
    lastDate: DateTime(now.year + 1),
    initialDateRange: DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    helpText: 'Business dates (inclusive)',
  );
  if (r == null) return null;
  return BusinessDateRange.inclusive(BusinessDate.fromDateTime(r.start), BusinessDate.fromDateTime(r.end));
}
