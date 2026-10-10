import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/time/business_time.dart';
import '../../../shared/widgets/common.dart';
import '../../bills/domain/payment_method.dart';
import '../../bills/presentation/bills_screen.dart';
import '../../orders/domain/order_models.dart';
import '../application/export_service.dart';
import '../application/report_service.dart';

/// Offline sales dashboard. Every figure is a SQL query over saved bills,
/// refunds, expenses and drawer movements — see docs/REPORT_DEFINITIONS.md.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  RangePreset _preset = RangePreset.today;
  BusinessDateRange? _custom;

  Future<BusinessDateRange> _range() async {
    if (_preset == RangePreset.custom && _custom != null) return _custom!;
    return (await ref.read(servicesProvider).ctx.calendar()).preset(_preset, DateTime.now().toUtc());
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(servicesProvider);
    final actor = requireActor(ref);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(vertical: 6),
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
              ),
              PopupMenuButton<ExportKind>(
                tooltip: 'Export CSV',
                icon: const Icon(Icons.download_outlined),
                onSelected: (kind) => _export(kind),
                itemBuilder: (_) => [
                  for (final k in ExportKind.values) PopupMenuItem(value: k, child: Text('Export ${k.label} (CSV)')),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureView<BusinessDateRange>(
            key: ValueKey('$_preset$_custom'),
            future: _range(),
            builder: (context, range) => StreamView<DashboardData>(
              stream: services.reports.watchDashboard(actor, range),
              loadingLabel: 'Calculating…',
              builder: (context, d) => _DashboardBody(data: d),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _export(ExportKind kind) async {
    final services = ref.read(servicesProvider);
    final range = await _range();
    if (!mounted) return;
    final file = await guard(context, () => services.exports.export(requireActor(ref), kind, range));
    if (file == null || !mounted) return;
    final saved = await guard(
      context,
      () => FilePicker.saveFile(fileName: file.fileName, bytes: file.bytes, mimeType: 'text/csv'),
    );
    if (saved != null && mounted) showInfo(context, 'Saved ${file.rowCount} row(s) to ${file.fileName}');
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final d = data;
    final t = Theme.of(context).textTheme;
    final cards = <Widget>[
      _Metric(
        'Net billed value',
        formatMoney(d.netBilledValue),
        'Bills ${formatMoney(d.billsTotal)} − refunds ${formatMoney(d.refundsTotal)} (incl. tax)',
        emphasis: true,
      ),
      _Metric('Completed bills', '${d.billCount}', 'Average bill ${formatMoney(d.averageBill)} (refunds not included)'),
      _Metric('Net item sales', formatMoney(d.netItemSales), 'Excl. tax · after discounts and item refunds'),
      _Metric('Item gross sales', formatMoney(d.itemsGrossEx), 'Excl. tax · before discounts'),
      _Metric('Discounts', formatMoney(d.itemsDiscountEx), 'Reversed by refunds: ${formatMoney(d.refundDiscountEx)}'),
      _Metric(
        'Service/delivery charges',
        formatMoney(d.chargesNetEx),
        'Refunded: ${formatMoney(d.refundChargesNetEx)} · excl. tax',
      ),
      _Metric('Taxes collected', formatMoney(d.taxCollected), 'Reversed: ${formatMoney(d.taxReversed)} · not revenue'),
      _Metric('Refunds', formatMoney(d.refundsTotal), '${d.refundCount} refund(s) issued in this period'),
      _Metric('Expenses', formatMoney(d.expensesTotal), 'From drawer: ${formatMoney(d.drawerExpenses)}'),
      _Metric(
        'Operating surplus estimate',
        formatMoney(d.operatingSurplusEstimate),
        'Net sales excl. tax − expenses. Not profit: ingredient costs are not recorded.',
      ),
      _Metric(
        'Net cash movement',
        formatMoney(d.netCashMovement),
        'Cash in − cash out, including refunds, drawer moves and drawer expenses',
      ),
      _Metric('Cancelled orders', '${d.cancellations}', 'Orders cancelled in this period'),
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text(
          'Business dates ${d.range.start} to ${d.range.lastDay}. Operational report — not a statutory tax report.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 8),
        if (d.isEmpty)
          const Card(
            child: EmptyState(
              icon: Icons.insights_outlined,
              title: 'No activity in this period',
              message: 'Completed bills, refunds and expenses will appear here as soon as they are saved.',
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 1100 ? 4 : (c.maxWidth >= 700 ? 3 : (c.maxWidth >= 420 ? 2 : 1));
              return GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: cols == 1 ? 3.2 : 1.9,
                children: cards,
              );
            },
          ),
          const SizedBox(height: 12),
          _PaymentsCard(data: d),
          const SizedBox(height: 12),
          if (d.daily.length > 1) ...[
            SectionCard(
              title: 'Daily net billed value',
              child: SizedBox(
                height: 220,
                child: _Bars(
                  values: [for (final p in d.daily) p.netBilled],
                  labels: [for (final p in d.daily) p.date.key.substring(5)],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SectionCard(
            title: 'Sales by hour (bills total)',
            child: SizedBox(
              height: 220,
              child: _Bars(values: d.hourly, labels: [for (var h = 0; h < 24; h++) '$h']),
            ),
          ),
          const SizedBox(height: 12),
          _ListCard(
            title: 'Top items (net quantity · net sales excl. tax)',
            rows: [
              for (final i in d.topItems.take(15)) (i.name, '${i.netQuantity} · ${formatMoney(i.netSales)}'),
            ],
          ),
          const SizedBox(height: 12),
          _ListCard(
            title: 'Category sales (net, excl. tax)',
            rows: [for (final c in d.categories) (c.name, formatMoney(c.netSales))],
          ),
          const SizedBox(height: 12),
          _ListCard(
            title: 'Order types',
            rows: [
              for (final o in d.orderTypes)
                (OrderType.parse(o.orderType).label, '${o.count} bill(s) · ${formatMoney(o.total)}'),
            ],
          ),
          const SizedBox(height: 12),
          _LedgerCard(range: d.range),
          const SizedBox(height: 12),
          _ListCard(
            title: 'Refunds issued (linked to the original sale)',
            rows: [
              for (final r in d.refunds)
                ('${r.refund.refundNo} for ${r.receiptNo}', '${formatMoney(r.refund.total)} · ${r.refund.reason}'),
            ],
          ),
        ],
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.title, this.value, this.caption, {this.emphasis = false});
  final String title;
  final String value;
  final String caption;
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      color: emphasis ? const Color(0xFFE6F2F0) : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: t.labelLarge),
            const Spacer(),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Text(caption, style: t.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _PaymentsCard extends StatelessWidget {
  const _PaymentsCard({required this.data});
  final DashboardData data;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: 'Payments',
    subtitle: 'Split tenders are counted under each method. UPI and card are staff-recorded, not bank-verified.',
    child: Table(
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(2), 2: FlexColumnWidth(2), 3: FlexColumnWidth(2)},
      children: [
        const TableRow(
          children: [
            Text('Method', style: TextStyle(fontWeight: FontWeight.w600)),
            Text(
              'Received',
              style: TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
            Text(
              'Refunded',
              style: TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
            Text(
              'Net',
              style: TextStyle(fontWeight: FontWeight.w600),
              textAlign: TextAlign.right,
            ),
          ],
        ),
        for (final m in PaymentMethod.values)
          TableRow(
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Text(m.label)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(formatMoney(data.receiptsByMethod[m.code] ?? 0), textAlign: TextAlign.right),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(formatMoney(data.refundsByMethod[m.code] ?? 0), textAlign: TextAlign.right),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  formatMoney((data.receiptsByMethod[m.code] ?? 0) - (data.refundsByMethod[m.code] ?? 0)),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
      ],
    ),
  );
}

class _ListCard extends StatelessWidget {
  const _ListCard({required this.title, required this.rows});
  final String title;
  final List<(String, String)> rows;
  @override
  Widget build(BuildContext context) => SectionCard(
    title: title,
    child: rows.isEmpty
        ? const Text('Nothing in this period')
        : Column(
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(r.$1, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: 8),
                      Text(r.$2),
                    ],
                  ),
                ),
            ],
          ),
  );
}

/// Day-by-day ledger for the selected range (same numbers as the CSV export).
class _LedgerCard extends ConsumerWidget {
  const _LedgerCard({required this.range});
  final BusinessDateRange range;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider);
    return SectionCard(
      title: 'Daily ledger',
      subtitle: 'Cash column = cash received − cash refunds + drawer in − drawer out − drawer expenses',
      child: FutureView<List<LedgerRow>>(
        future: services.reports.ledger(requireActor(ref), range),
        builder: (context, rows) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columnSpacing: 20,
            headingRowHeight: 40,
            dataRowMinHeight: 36,
            dataRowMaxHeight: 40,
            columns: const [
              DataColumn(label: Text('Day')),
              DataColumn(label: Text('Bills'), numeric: true),
              DataColumn(label: Text('Billed'), numeric: true),
              DataColumn(label: Text('Refunds'), numeric: true),
              DataColumn(label: Text('Net billed'), numeric: true),
              DataColumn(label: Text('Tax'), numeric: true),
              DataColumn(label: Text('Cash'), numeric: true),
              DataColumn(label: Text('UPI'), numeric: true),
              DataColumn(label: Text('Card'), numeric: true),
              DataColumn(label: Text('Expenses'), numeric: true),
              DataColumn(label: Text('Net cash'), numeric: true),
            ],
            rows: [
              for (final r in rows)
                DataRow(
                  cells: [
                    DataCell(Text(r.date.key)),
                    DataCell(Text('${r.billCount}')),
                    DataCell(Text(formatMoney(r.billsTotal))),
                    DataCell(Text(formatMoney(r.refundsTotal))),
                    DataCell(Text(formatMoney(r.netBilled))),
                    DataCell(Text(formatMoney(r.taxCollected - r.taxReversed))),
                    DataCell(Text(formatMoney(r.receiptsByMethod['cash'] ?? 0))),
                    DataCell(Text(formatMoney(r.receiptsByMethod['upi'] ?? 0))),
                    DataCell(Text(formatMoney(r.receiptsByMethod['card'] ?? 0))),
                    DataCell(Text(formatMoney(r.expenses))),
                    DataCell(Text(formatMoney(r.netCash))),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.values, required this.labels});
  final List<int> values;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final maxV = values.fold<int>(0, (a, b) => b > a ? b : a);
    final minV = values.fold<int>(0, (a, b) => b < a ? b : a);
    final step = (labels.length / 8).ceil().clamp(1, 1000);
    return BarChart(
      BarChartData(
        maxY: maxV <= 0 ? 100 : maxV * 1.15,
        minY: minV < 0 ? minV * 1.15 : 0,
        gridData: const FlGridData(drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${labels[group.x]}\n${formatMoney(rod.toY.round())}',
              const TextStyle(color: Colors.white),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 56,
              getTitlesWidget: (v, meta) => SideTitleWidget(
                meta: meta,
                child: Text(_short(v.round()), style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i % step != 0 || i >= labels.length) return const SizedBox.shrink();
                return SideTitleWidget(
                  meta: meta,
                  child: Text(labels[i], style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i].toDouble(),
                  color: values[i] < 0 ? AppColors.danger : AppColors.accent,
                  width: values.length > 20 ? 8 : 16,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _short(int paise) {
    final r = paise / 100;
    if (r.abs() >= 100000) return '₹${(r / 100000).toStringAsFixed(1)}L';
    if (r.abs() >= 1000) return '₹${(r / 1000).toStringAsFixed(1)}k';
    return '₹${r.toStringAsFixed(0)}';
  }
}
