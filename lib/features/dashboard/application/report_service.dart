import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/money/money.dart';
import '../../../core/security/permissions.dart';
import '../../../core/service_context.dart';
import '../../../core/time/business_time.dart';

/// Implements docs/REPORT_DEFINITIONS.md. Every number comes from SQL over
/// persisted rows filtered by business date `[start, end)`.

class DailyPoint {
  const DailyPoint({required this.date, required this.billCount, required this.billsTotal, required this.refundsTotal});
  final BusinessDate date;
  final int billCount;
  final int billsTotal;
  final int refundsTotal;
  int get netBilled => billsTotal - refundsTotal;
}

class ItemSales {
  const ItemSales({required this.name, required this.netQuantity, required this.netSales});
  final String name;
  final int netQuantity;
  final int netSales;
}

class OrderTypeSales {
  const OrderTypeSales({required this.orderType, required this.count, required this.total});
  final String orderType;
  final int count;
  final int total;
}

class RefundListItem {
  const RefundListItem({required this.refund, required this.receiptNo});
  final RefundRow refund;
  final String receiptNo;
}

class DashboardData {
  const DashboardData({
    required this.range,
    required this.billCount,
    required this.billsTotal,
    required this.itemsGrossEx,
    required this.itemsDiscountEx,
    required this.itemsNetEx,
    required this.chargesNetEx,
    required this.taxCollected,
    required this.refundCount,
    required this.refundsTotal,
    required this.refundItemsNetEx,
    required this.refundDiscountEx,
    required this.refundChargesNetEx,
    required this.taxReversed,
    required this.receiptsByMethod,
    required this.refundsByMethod,
    required this.expensesTotal,
    required this.drawerExpenses,
    required this.cashIn,
    required this.cashOut,
    required this.cancellations,
    required this.daily,
    required this.hourly,
    required this.topItems,
    required this.categories,
    required this.orderTypes,
    required this.refunds,
  });

  final BusinessDateRange range;
  final int billCount;
  final int billsTotal;
  final int itemsGrossEx;
  final int itemsDiscountEx;
  final int itemsNetEx;
  final int chargesNetEx;
  final int taxCollected;
  final int refundCount;
  final int refundsTotal;
  final int refundItemsNetEx;
  final int refundDiscountEx;
  final int refundChargesNetEx;
  final int taxReversed;
  final Map<String, int> receiptsByMethod;
  final Map<String, int> refundsByMethod;
  final int expensesTotal;
  final int drawerExpenses;
  final int cashIn;
  final int cashOut;
  final int cancellations;
  final List<DailyPoint> daily;

  /// Index = local hour 0..23, value = Σ bills.total.
  final List<int> hourly;
  final List<ItemSales> topItems;
  final List<ItemSales> categories;
  final List<OrderTypeSales> orderTypes;
  final List<RefundListItem> refunds;

  int get netItemSales => itemsNetEx - refundItemsNetEx;
  int get netBilledValue => billsTotal - refundsTotal;
  int get averageBill => billCount == 0 ? 0 : divRoundHalfUp(billsTotal, billCount);
  int get netCharges => chargesNetEx - refundChargesNetEx;

  /// Not profit: ingredient and other costs are not recorded.
  int get operatingSurplusEstimate => netItemSales + netCharges - expensesTotal;
  int get netCashMovement =>
      (receiptsByMethod['cash'] ?? 0) - (refundsByMethod['cash'] ?? 0) + cashIn - cashOut - drawerExpenses;

  bool get isEmpty => billCount == 0 && refundCount == 0 && expensesTotal == 0 && cashIn == 0 && cashOut == 0;
}

class LedgerRow {
  const LedgerRow({
    required this.date,
    required this.billCount,
    required this.billsTotal,
    required this.itemsNetEx,
    required this.chargesNetEx,
    required this.taxCollected,
    required this.refundsTotal,
    required this.refundItemsNetEx,
    required this.taxReversed,
    required this.receiptsByMethod,
    required this.refundsByMethod,
    required this.expenses,
    required this.drawerExpenses,
    required this.cashIn,
    required this.cashOut,
  });

  final BusinessDate date;
  final int billCount;
  final int billsTotal;
  final int itemsNetEx;
  final int chargesNetEx;
  final int taxCollected;
  final int refundsTotal;
  final int refundItemsNetEx;
  final int taxReversed;
  final Map<String, int> receiptsByMethod;
  final Map<String, int> refundsByMethod;
  final int expenses;
  final int drawerExpenses;
  final int cashIn;
  final int cashOut;

  int get netBilled => billsTotal - refundsTotal;
  int get netCash =>
      (receiptsByMethod['cash'] ?? 0) - (refundsByMethod['cash'] ?? 0) + cashIn - cashOut - drawerExpenses;
}

class ReportService {
  ReportService(this.ctx);

  final ServiceContext ctx;
  AppDatabase get _db => ctx.db;

  List<Variable<Object>> _vars(BusinessDateRange r) => [
    Variable.withString(r.start.key),
    Variable.withString(r.endExclusive.key),
  ];

  Future<QueryRow> _one(String sql, BusinessDateRange r) => _db.customSelect(sql, variables: _vars(r)).getSingle();

  Future<List<QueryRow>> _many(String sql, BusinessDateRange r) => _db.customSelect(sql, variables: _vars(r)).get();

  /// Re-emits whenever a bill, refund, expense or drawer movement commits.
  Stream<DashboardData> watchDashboard(Actor actor, BusinessDateRange range) async* {
    yield await dashboard(actor, range);
    await for (final _ in _db.tableUpdates(
      TableUpdateQuery.onAllTables([_db.bills, _db.refunds, _db.expenses, _db.cashMovements, _db.orders]),
    )) {
      yield await dashboard(actor, range);
    }
  }

  Future<DashboardData> dashboard(Actor actor, BusinessDateRange range) async {
    actor.require(Permission.viewReports);
    const inRange = 'business_date >= ?1 AND business_date < ?2';

    final bills = await _one(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(items_gross_ex),0) AS gross, '
      'COALESCE(SUM(items_discount_ex),0) AS disc, COALESCE(SUM(items_net_ex),0) AS net, '
      'COALESCE(SUM(charges_net_ex),0) AS charges, COALESCE(SUM(tax_total),0) AS tax FROM bills WHERE $inRange',
      range,
    );
    final refunds = await _one(
      'SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(items_net_ex),0) AS net, '
      'COALESCE(SUM(items_discount_ex),0) AS disc, COALESCE(SUM(charges_net_ex),0) AS charges, '
      'COALESCE(SUM(tax_total),0) AS tax FROM refunds WHERE $inRange',
      range,
    );
    final receipts = await _many(
      'SELECT p.method AS method, SUM(p.applied) AS amount FROM payments p JOIN bills b ON b.id = p.bill_id '
      'WHERE b.business_date >= ?1 AND b.business_date < ?2 GROUP BY p.method',
      range,
    );
    final refundPays = await _many(
      'SELECT rp.method AS method, SUM(rp.amount) AS amount FROM refund_payments rp JOIN refunds r ON r.id = rp.refund_id '
      'WHERE r.business_date >= ?1 AND r.business_date < ?2 GROUP BY rp.method',
      range,
    );
    final expenses = await _one(
      'SELECT COALESCE(SUM(amount),0) AS total, COALESCE(SUM(CASE WHEN paid_from_drawer = 1 THEN amount ELSE 0 END),0) AS drawer '
      'FROM expenses WHERE voided_at IS NULL AND $inRange',
      range,
    );
    final moves = await _one(
      "SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END),0) AS cash_in, "
      "COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END),0) AS cash_out FROM cash_movements WHERE $inRange",
      range,
    );
    final cancels = await _one(
      "SELECT COUNT(*) AS n FROM orders WHERE status = 'cancelled' AND cancel_business_date >= ?1 AND cancel_business_date < ?2",
      range,
    );

    final dailyBills = await _many(
      'SELECT business_date AS d, COUNT(*) AS n, SUM(total) AS total FROM bills WHERE $inRange GROUP BY business_date',
      range,
    );
    final dailyRefunds = await _many(
      'SELECT business_date AS d, SUM(total) AS total FROM refunds WHERE $inRange GROUP BY business_date',
      range,
    );
    final billsByDay = {for (final r in dailyBills) r.read<String>('d'): r};
    final refundsByDay = {for (final r in dailyRefunds) r.read<String>('d'): r.read<int>('total')};
    final daily = [
      for (final d in range.days)
        DailyPoint(
          date: d,
          billCount: billsByDay[d.key]?.read<int>('n') ?? 0,
          billsTotal: billsByDay[d.key]?.read<int>('total') ?? 0,
          refundsTotal: refundsByDay[d.key] ?? 0,
        ),
    ];

    final hourlyRows = await _many(
      'SELECT local_hour AS h, SUM(total) AS total FROM bills WHERE $inRange GROUP BY local_hour',
      range,
    );
    final hourly = List<int>.filled(24, 0);
    for (final r in hourlyRows) {
      final h = r.read<int>('h');
      if (h >= 0 && h < 24) hourly[h] = r.read<int>('total');
    }

    final soldItems = await _many(
      'SELECT COALESCE(bl.item_id, bl.item_name) AS k, MAX(bl.item_name) AS name, SUM(bl.quantity) AS qty, SUM(bl.net_ex) AS net '
      'FROM bill_lines bl JOIN bills b ON b.id = bl.bill_id WHERE b.business_date >= ?1 AND b.business_date < ?2 '
      'GROUP BY COALESCE(bl.item_id, bl.item_name)',
      range,
    );
    final refundedItems = await _many(
      'SELECT COALESCE(bl.item_id, bl.item_name) AS k, MAX(bl.item_name) AS name, SUM(rl.quantity) AS qty, SUM(rl.net_ex) AS net '
      'FROM refund_lines rl JOIN refunds r ON r.id = rl.refund_id JOIN bill_lines bl ON bl.id = rl.bill_line_id '
      'WHERE r.business_date >= ?1 AND r.business_date < ?2 GROUP BY COALESCE(bl.item_id, bl.item_name)',
      range,
    );
    final topItems = _merge(soldItems, refundedItems)
      ..sort((a, b) {
        final byQty = b.netQuantity.compareTo(a.netQuantity);
        return byQty != 0 ? byQty : b.netSales.compareTo(a.netSales);
      });

    final soldCats = await _many(
      "SELECT COALESCE(bl.category_name, 'Uncategorised') AS k, COALESCE(bl.category_name, 'Uncategorised') AS name, "
      'SUM(bl.quantity) AS qty, SUM(bl.net_ex) AS net FROM bill_lines bl JOIN bills b ON b.id = bl.bill_id '
      'WHERE b.business_date >= ?1 AND b.business_date < ?2 GROUP BY k',
      range,
    );
    final refundedCats = await _many(
      "SELECT COALESCE(bl.category_name, 'Uncategorised') AS k, COALESCE(bl.category_name, 'Uncategorised') AS name, "
      'SUM(rl.quantity) AS qty, SUM(rl.net_ex) AS net FROM refund_lines rl JOIN refunds r ON r.id = rl.refund_id '
      'JOIN bill_lines bl ON bl.id = rl.bill_line_id WHERE r.business_date >= ?1 AND r.business_date < ?2 GROUP BY k',
      range,
    );
    final categories = _merge(soldCats, refundedCats)..sort((a, b) => b.netSales.compareTo(a.netSales));

    final types = await _many(
      'SELECT order_type AS t, COUNT(*) AS n, SUM(total) AS total FROM bills WHERE $inRange GROUP BY order_type ORDER BY total DESC',
      range,
    );

    final refundRows = await _db
        .customSelect(
          'SELECT r.*, b.receipt_no AS original_receipt FROM refunds r JOIN bills b ON b.id = r.bill_id '
          'WHERE r.business_date >= ?1 AND r.business_date < ?2 ORDER BY r.created_at DESC LIMIT 200',
          variables: _vars(range),
          readsFrom: {_db.refunds, _db.bills},
        )
        .get();

    return DashboardData(
      range: range,
      billCount: bills.read<int>('n'),
      billsTotal: bills.read<int>('total'),
      itemsGrossEx: bills.read<int>('gross'),
      itemsDiscountEx: bills.read<int>('disc'),
      itemsNetEx: bills.read<int>('net'),
      chargesNetEx: bills.read<int>('charges'),
      taxCollected: bills.read<int>('tax'),
      refundCount: refunds.read<int>('n'),
      refundsTotal: refunds.read<int>('total'),
      refundItemsNetEx: refunds.read<int>('net'),
      refundDiscountEx: refunds.read<int>('disc'),
      refundChargesNetEx: refunds.read<int>('charges'),
      taxReversed: refunds.read<int>('tax'),
      receiptsByMethod: {for (final r in receipts) r.read<String>('method'): r.read<int>('amount')},
      refundsByMethod: {for (final r in refundPays) r.read<String>('method'): r.read<int>('amount')},
      expensesTotal: expenses.read<int>('total'),
      drawerExpenses: expenses.read<int>('drawer'),
      cashIn: moves.read<int>('cash_in'),
      cashOut: moves.read<int>('cash_out'),
      cancellations: cancels.read<int>('n'),
      daily: daily,
      hourly: hourly,
      topItems: topItems,
      categories: categories,
      orderTypes: [
        for (final t in types)
          OrderTypeSales(orderType: t.read<String>('t'), count: t.read<int>('n'), total: t.read<int>('total')),
      ],
      refunds: [
        for (final r in refundRows)
          RefundListItem(refund: _db.refunds.map(r.data), receiptNo: r.read<String>('original_receipt')),
      ],
    );
  }

  static List<ItemSales> _merge(List<QueryRow> sold, List<QueryRow> refunded) {
    final map = <String, (String, int, int)>{};
    for (final r in sold) {
      map[r.read<String>('k')] = (r.read<String>('name'), r.read<int>('qty'), r.read<int>('net'));
    }
    for (final r in refunded) {
      final k = r.read<String>('k');
      final prev = map[k] ?? (r.read<String>('name'), 0, 0);
      map[k] = (prev.$1, prev.$2 - r.read<int>('qty'), prev.$3 - r.read<int>('net'));
    }
    return [for (final v in map.values) ItemSales(name: v.$1, netQuantity: v.$2, netSales: v.$3)];
  }

  /// One row per business date in range, including empty days.
  Future<List<LedgerRow>> ledger(Actor actor, BusinessDateRange range) async {
    actor.require(Permission.viewReports);
    Future<Map<String, QueryRow>> byDay(String sql) async => {
      for (final r in await _many(sql, range)) r.read<String>('d'): r,
    };
    Future<Map<String, Map<String, int>>> byDayMethod(String sql) async {
      final out = <String, Map<String, int>>{};
      for (final r in await _many(sql, range)) {
        out.putIfAbsent(r.read<String>('d'), () => {})[r.read<String>('method')] = r.read<int>('amount');
      }
      return out;
    }

    const inRange = 'business_date >= ?1 AND business_date < ?2';
    final bills = await byDay(
      'SELECT business_date AS d, COUNT(*) AS n, SUM(total) AS total, SUM(items_net_ex) AS net, '
      'SUM(charges_net_ex) AS charges, SUM(tax_total) AS tax FROM bills WHERE $inRange GROUP BY business_date',
    );
    final refunds = await byDay(
      'SELECT business_date AS d, SUM(total) AS total, SUM(items_net_ex) AS net, '
      'SUM(tax_total) AS tax FROM refunds WHERE $inRange GROUP BY business_date',
    );
    final receipts = await byDayMethod(
      'SELECT b.business_date AS d, p.method AS method, SUM(p.applied) AS amount '
      'FROM payments p JOIN bills b ON b.id = p.bill_id WHERE b.business_date >= ?1 AND b.business_date < ?2 '
      'GROUP BY b.business_date, p.method',
    );
    final refundPays = await byDayMethod(
      'SELECT r.business_date AS d, rp.method AS method, SUM(rp.amount) AS amount '
      'FROM refund_payments rp JOIN refunds r ON r.id = rp.refund_id WHERE r.business_date >= ?1 AND r.business_date < ?2 '
      'GROUP BY r.business_date, rp.method',
    );
    final expenses = await byDay(
      'SELECT business_date AS d, SUM(amount) AS total, '
      'SUM(CASE WHEN paid_from_drawer = 1 THEN amount ELSE 0 END) AS drawer FROM expenses '
      'WHERE voided_at IS NULL AND $inRange GROUP BY business_date',
    );
    final moves = await byDay(
      "SELECT business_date AS d, SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END) AS cash_in, "
      "SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END) AS cash_out FROM cash_movements WHERE $inRange GROUP BY business_date",
    );

    return [
      for (final d in range.days)
        LedgerRow(
          date: d,
          billCount: bills[d.key]?.read<int>('n') ?? 0,
          billsTotal: bills[d.key]?.read<int>('total') ?? 0,
          itemsNetEx: bills[d.key]?.read<int>('net') ?? 0,
          chargesNetEx: bills[d.key]?.read<int>('charges') ?? 0,
          taxCollected: bills[d.key]?.read<int>('tax') ?? 0,
          refundsTotal: refunds[d.key]?.read<int>('total') ?? 0,
          refundItemsNetEx: refunds[d.key]?.read<int>('net') ?? 0,
          taxReversed: refunds[d.key]?.read<int>('tax') ?? 0,
          receiptsByMethod: receipts[d.key] ?? const {},
          refundsByMethod: refundPays[d.key] ?? const {},
          expenses: expenses[d.key]?.read<int>('total') ?? 0,
          drawerExpenses: expenses[d.key]?.read<int>('drawer') ?? 0,
          cashIn: moves[d.key]?.read<int>('cash_in') ?? 0,
          cashOut: moves[d.key]?.read<int>('cash_out') ?? 0,
        ),
    ];
  }

  Future<BusinessCalendar> calendar() => ctx.calendar();
}
