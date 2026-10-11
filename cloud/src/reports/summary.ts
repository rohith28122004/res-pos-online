// GET /v1/reports/summary — the cards of docs/REPORT_DEFINITIONS.md computed
// from the D1 projections, plus freshness (docs/PROTOCOL.md §8.2).
//
// Mirrors lib/features/dashboard/application/report_service.dart: business
// dates [from, to), refunds on the day they were issued, integer paise only.
// Sums come back from SQLite as integers; division uses BigInt half-up.

import { ApiError } from "../http/errors";

export interface ItemSales {
  name: string;
  netQuantity: number;
  netSales: number;
}

export interface SummaryReport {
  range: { from: string; to: string };
  unit: "paise";
  generatedAt: number;
  cards: {
    completedBills: number;
    billsTotal: number;
    averageBill: number;
    itemGrossSales: number;
    discounts: number;
    discountReversals: number;
    netItemSales: number;
    charges: number;
    chargeRefunds: number;
    netCharges: number;
    taxesCollected: number;
    taxesReversed: number;
    refunds: number;
    refundsTotal: number;
    netBilledValue: number;
    receiptsByMethod: Record<string, number>;
    refundsByMethod: Record<string, number>;
    expenses: number;
    expensesFromDrawer: number;
    operatingSurplusEstimate: number;
    drawerCashIn: number;
    drawerCashOut: number;
    netCashMovement: number;
    cancellations: number;
  };
  daily: Array<{ date: string; bills: number; billsTotal: number; refundsTotal: number; netBilledValue: number }>;
  hourly: number[];
  topItems: ItemSales[];
  categories: ItemSales[];
  orderTypes: Array<{ orderType: string; bills: number; total: number }>;
  refundList: Array<{
    refundId: string;
    refundNo: string;
    originalReceiptNo: string | null;
    businessDate: string;
    createdAt: number;
    total: number;
  }>;
  freshness: {
    source: { hostDeviceId: string };
    ackedThrough: { hostEpoch: number; sequence: number } | null;
    lastEventCommittedAt: number | null;
    lastIngestedAt: number | null;
  };
}

/** Half away from zero, like `divRoundHalfUp` in lib/core/money/money.dart. */
export function divRoundHalfUp(numerator: number, denominator: number): number {
  if (denominator <= 0) throw new RangeError("denominator must be > 0");
  const n = BigInt(numerator);
  const d = BigInt(denominator);
  if (n < 0n) return -divRoundHalfUp(-numerator, denominator);
  const q = n / d;
  const r = n - q * d;
  return Number(r * 2n >= d ? q + 1n : q);
}

const MAX_RANGE_DAYS = 400;
const DAY_MS = 86_400_000;

function dayNumber(date: string): number {
  const [y, m, d] = date.split("-").map(Number) as [number, number, number];
  return Date.UTC(y, m - 1, d) / DAY_MS;
}

function dateOfDay(day: number): string {
  return new Date(day * DAY_MS).toISOString().slice(0, 10);
}

/** Validates [from, to) and returns the business dates in it. */
export function daysInRange(from: string, to: string): string[] {
  const start = dayNumber(from);
  const end = dayNumber(to);
  if (end <= start) throw new ApiError("VALIDATION", "`to` must be after `from` (the range is [from, to))");
  if (end - start > MAX_RANGE_DAYS) {
    throw new ApiError("VALIDATION", `A report covers at most ${MAX_RANGE_DAYS} days`, { maxDays: MAX_RANGE_DAYS });
  }
  const days: string[] = [];
  for (let day = start; day < end; day++) days.push(dateOfDay(day));
  return days;
}

function int(value: unknown): number {
  const n = value ?? 0;
  if (typeof n !== "number" || !Number.isSafeInteger(n)) throw new ApiError("INTERNAL", "Report sum out of range");
  return n;
}

type Row = Record<string, unknown>;

function mergeItems(sold: Row[], refunded: Row[]): ItemSales[] {
  const byKey = new Map<string, ItemSales>();
  for (const row of sold) {
    byKey.set(String(row["k"]), { name: String(row["name"]), netQuantity: int(row["qty"]), netSales: int(row["net"]) });
  }
  for (const row of refunded) {
    const key = String(row["k"]);
    const current = byKey.get(key) ?? { name: String(row["name"]), netQuantity: 0, netSales: 0 };
    byKey.set(key, {
      name: current.name,
      netQuantity: current.netQuantity - int(row["qty"]),
      netSales: current.netSales - int(row["net"]),
    });
  }
  return [...byKey.values()];
}

export async function buildSummary(db: D1Database, restaurantId: string, from: string, to: string): Promise<SummaryReport> {
  const days = daysInRange(from, to);
  const q = (sql: string) => db.prepare(sql).bind(restaurantId, from, to);
  const inRange = "restaurant_id = ?1 AND business_date >= ?2 AND business_date < ?3";

  const results = await db.batch<Row>([
    /* 0 */ q(
      `SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(items_gross_ex),0) AS gross,
              COALESCE(SUM(items_discount_ex),0) AS disc, COALESCE(SUM(items_net_ex),0) AS net,
              COALESCE(SUM(charges_net_ex),0) AS charges, COALESCE(SUM(tax_total),0) AS tax
         FROM proj_bills WHERE ${inRange}`,
    ),
    /* 1 */ q(
      `SELECT COUNT(*) AS n, COALESCE(SUM(total),0) AS total, COALESCE(SUM(items_net_ex),0) AS net,
              COALESCE(SUM(items_discount_ex),0) AS disc, COALESCE(SUM(charges_net_ex),0) AS charges,
              COALESCE(SUM(tax_total),0) AS tax
         FROM proj_refunds WHERE ${inRange}`,
    ),
    /* 2 */ q(
      `SELECT p.method AS method, SUM(p.applied) AS amount
         FROM proj_payments AS p JOIN proj_bills AS b ON b.restaurant_id = p.restaurant_id AND b.id = p.bill_id
        WHERE p.restaurant_id = ?1 AND b.business_date >= ?2 AND b.business_date < ?3
        GROUP BY p.method ORDER BY p.method`,
    ),
    /* 3 */ q(
      `SELECT rp.method AS method, SUM(rp.amount) AS amount
         FROM proj_refund_payments AS rp
         JOIN proj_refunds AS r ON r.restaurant_id = rp.restaurant_id AND r.id = rp.refund_id
        WHERE rp.restaurant_id = ?1 AND r.business_date >= ?2 AND r.business_date < ?3
        GROUP BY rp.method ORDER BY rp.method`,
    ),
    /* 4 */ q(
      `SELECT COALESCE(SUM(amount),0) AS total,
              COALESCE(SUM(CASE WHEN paid_from_drawer = 1 THEN amount ELSE 0 END),0) AS drawer
         FROM proj_expenses WHERE voided_at IS NULL AND ${inRange}`,
    ),
    /* 5 */ q(
      `SELECT COALESCE(SUM(CASE WHEN direction = 'in' THEN amount ELSE 0 END),0) AS cash_in,
              COALESCE(SUM(CASE WHEN direction = 'out' THEN amount ELSE 0 END),0) AS cash_out
         FROM proj_cash_movements WHERE ${inRange}`,
    ),
    /* 6 */ q(
      `SELECT COUNT(*) AS n FROM proj_order_cancellations
        WHERE restaurant_id = ?1 AND cancel_business_date >= ?2 AND cancel_business_date < ?3`,
    ),
    /* 7 */ q(
      `SELECT business_date AS d, COUNT(*) AS n, SUM(total) AS total FROM proj_bills
        WHERE ${inRange} GROUP BY business_date`,
    ),
    /* 8 */ q(`SELECT business_date AS d, SUM(total) AS total FROM proj_refunds WHERE ${inRange} GROUP BY business_date`),
    /* 9 */ q(`SELECT local_hour AS h, SUM(total) AS total FROM proj_bills WHERE ${inRange} GROUP BY local_hour`),
    /* 10 */ q(
      `SELECT COALESCE(bl.item_id, bl.item_name) AS k, MAX(bl.item_name) AS name,
              SUM(bl.quantity) AS qty, SUM(bl.net_ex) AS net
         FROM proj_bill_lines AS bl JOIN proj_bills AS b ON b.restaurant_id = bl.restaurant_id AND b.id = bl.bill_id
        WHERE bl.restaurant_id = ?1 AND b.business_date >= ?2 AND b.business_date < ?3
        GROUP BY COALESCE(bl.item_id, bl.item_name)`,
    ),
    /* 11 */ q(
      `SELECT COALESCE(bl.item_id, bl.item_name) AS k, MAX(bl.item_name) AS name,
              SUM(rl.quantity) AS qty, SUM(rl.net_ex) AS net
         FROM proj_refund_lines AS rl
         JOIN proj_refunds AS r ON r.restaurant_id = rl.restaurant_id AND r.id = rl.refund_id
         JOIN proj_bill_lines AS bl ON bl.restaurant_id = rl.restaurant_id AND bl.id = rl.bill_line_id
        WHERE rl.restaurant_id = ?1 AND r.business_date >= ?2 AND r.business_date < ?3
        GROUP BY COALESCE(bl.item_id, bl.item_name)`,
    ),
    /* 12 */ q(
      `SELECT COALESCE(bl.category_name, 'Uncategorised') AS k, COALESCE(bl.category_name, 'Uncategorised') AS name,
              SUM(bl.quantity) AS qty, SUM(bl.net_ex) AS net
         FROM proj_bill_lines AS bl JOIN proj_bills AS b ON b.restaurant_id = bl.restaurant_id AND b.id = bl.bill_id
        WHERE bl.restaurant_id = ?1 AND b.business_date >= ?2 AND b.business_date < ?3
        GROUP BY k`,
    ),
    /* 13 */ q(
      `SELECT COALESCE(bl.category_name, 'Uncategorised') AS k, COALESCE(bl.category_name, 'Uncategorised') AS name,
              SUM(rl.quantity) AS qty, SUM(rl.net_ex) AS net
         FROM proj_refund_lines AS rl
         JOIN proj_refunds AS r ON r.restaurant_id = rl.restaurant_id AND r.id = rl.refund_id
         JOIN proj_bill_lines AS bl ON bl.restaurant_id = rl.restaurant_id AND bl.id = rl.bill_line_id
        WHERE rl.restaurant_id = ?1 AND r.business_date >= ?2 AND r.business_date < ?3
        GROUP BY k`,
    ),
    /* 14 */ q(
      `SELECT order_type AS t, COUNT(*) AS n, SUM(total) AS total FROM proj_bills
        WHERE ${inRange} GROUP BY order_type ORDER BY total DESC, order_type`,
    ),
    /* 15 */ q(
      `SELECT r.id, r.refund_no, b.receipt_no AS original_receipt, r.business_date, r.created_at, r.total
         FROM proj_refunds AS r
         LEFT JOIN proj_bills AS b ON b.restaurant_id = r.restaurant_id AND b.id = r.bill_id
        WHERE r.restaurant_id = ?1 AND r.business_date >= ?2 AND r.business_date < ?3
        ORDER BY r.created_at DESC LIMIT 200`,
    ),
    /* 16 */ db
      .prepare(
        `SELECT r.host_device_id, r.current_epoch, r.last_event_committed_at, r.last_ingested_at,
                e.start_sequence, e.next_sequence
           FROM restaurants AS r LEFT JOIN epochs AS e ON e.restaurant_id = r.id AND e.epoch = r.current_epoch
          WHERE r.id = ?1`,
      )
      .bind(restaurantId),
  ]);
  const rows = (i: number): Row[] => results[i]?.results ?? [];
  const one = (i: number): Row => rows(i)[0] ?? {};

  const bills = one(0);
  const refunds = one(1);
  const expenses = one(4);
  const moves = one(5);
  const byMethod = (i: number) =>
    Object.fromEntries(rows(i).map((r) => [String(r["method"]), int(r["amount"])])) as Record<string, number>;
  const receiptsByMethod = byMethod(2);
  const refundsByMethod = byMethod(3);

  const billCount = int(bills["n"]);
  const billsTotal = int(bills["total"]);
  const netItemSales = int(bills["net"]) - int(refunds["net"]);
  const netCharges = int(bills["charges"]) - int(refunds["charges"]);
  const expensesTotal = int(expenses["total"]);
  const drawerExpenses = int(expenses["drawer"]);
  const cashIn = int(moves["cash_in"]);
  const cashOut = int(moves["cash_out"]);

  const billsByDay = new Map(rows(7).map((r) => [String(r["d"]), r]));
  const refundsByDay = new Map(rows(8).map((r) => [String(r["d"]), int(r["total"])]));
  const hourly = Array.from({ length: 24 }, () => 0);
  for (const r of rows(9)) {
    const h = int(r["h"]);
    if (h >= 0 && h < 24) hourly[h] = int(r["total"]);
  }

  const topItems = mergeItems(rows(10), rows(11)).sort(
    (a, b) => b.netQuantity - a.netQuantity || b.netSales - a.netSales || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0),
  );
  const categories = mergeItems(rows(12), rows(13)).sort(
    (a, b) => b.netSales - a.netSales || (a.name < b.name ? -1 : a.name > b.name ? 1 : 0),
  );

  const fresh = one(16);
  const currentEpoch = fresh["current_epoch"] as number | null | undefined;
  const nextSequence = fresh["next_sequence"] as number | null | undefined;
  const startSequence = fresh["start_sequence"] as number | null | undefined;

  return {
    range: { from, to },
    unit: "paise",
    generatedAt: Date.now(),
    cards: {
      completedBills: billCount,
      billsTotal,
      averageBill: billCount === 0 ? 0 : divRoundHalfUp(billsTotal, billCount),
      itemGrossSales: int(bills["gross"]),
      discounts: int(bills["disc"]),
      discountReversals: int(refunds["disc"]),
      netItemSales,
      charges: int(bills["charges"]),
      chargeRefunds: int(refunds["charges"]),
      netCharges,
      taxesCollected: int(bills["tax"]),
      taxesReversed: int(refunds["tax"]),
      refunds: int(refunds["n"]),
      refundsTotal: int(refunds["total"]),
      netBilledValue: billsTotal - int(refunds["total"]),
      receiptsByMethod,
      refundsByMethod,
      expenses: expensesTotal,
      expensesFromDrawer: drawerExpenses,
      // Not profit: ingredient and other costs are not recorded.
      operatingSurplusEstimate: netItemSales + netCharges - expensesTotal,
      drawerCashIn: cashIn,
      drawerCashOut: cashOut,
      netCashMovement: (receiptsByMethod["cash"] ?? 0) - (refundsByMethod["cash"] ?? 0) + cashIn - cashOut - drawerExpenses,
      cancellations: int(one(6)["n"]),
    },
    daily: days.map((date) => {
      const b = billsByDay.get(date);
      const billsTotalOfDay = b ? int(b["total"]) : 0;
      const refundsTotalOfDay = refundsByDay.get(date) ?? 0;
      return {
        date,
        bills: b ? int(b["n"]) : 0,
        billsTotal: billsTotalOfDay,
        refundsTotal: refundsTotalOfDay,
        netBilledValue: billsTotalOfDay - refundsTotalOfDay,
      };
    }),
    hourly,
    topItems,
    categories,
    orderTypes: rows(14).map((r) => ({ orderType: String(r["t"]), bills: int(r["n"]), total: int(r["total"]) })),
    refundList: rows(15).map((r) => ({
      refundId: String(r["id"]),
      refundNo: String(r["refund_no"]),
      originalReceiptNo: (r["original_receipt"] as string | null) ?? null,
      businessDate: String(r["business_date"]),
      createdAt: int(r["created_at"]),
      total: int(r["total"]),
    })),
    freshness: {
      source: { hostDeviceId: String(fresh["host_device_id"]) },
      ackedThrough:
        currentEpoch == null || nextSequence == null || startSequence == null || nextSequence <= startSequence
          ? null
          : { hostEpoch: currentEpoch, sequence: nextSequence - 1 },
      lastEventCommittedAt: (fresh["last_event_committed_at"] as number | null) ?? null,
      lastIngestedAt: (fresh["last_ingested_at"] as number | null) ?? null,
    },
  };
}
