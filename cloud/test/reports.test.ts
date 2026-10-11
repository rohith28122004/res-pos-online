// Cloud reports from projections: the hand-calculated fixture of
// docs/REPORT_DEFINITIONS.md, built as host events, plus projection rebuild.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { PROJECTION_TABLES } from "../src/projections/sql";
import { rebuildProjections } from "../src/projections/rebuild";
import { divRoundHalfUp } from "../src/reports/summary";
import { api, event, hostHeaders, json, newRestaurant, sendEvents, type Event, type Restaurant } from "./helpers";

// Restaurant time zone Asia/Kolkata (UTC+05:30); epoch ms of a local time.
const ist = (date: string, time: string) => Date.parse(`${date}T${time}:00+05:30`);

interface LineSpec {
  item: string;
  category: string;
  qty: number;
  grossEx: number;
  discountEx: number;
  netEx: number;
  tax: number;
  total: number;
}

const COFFEE = { item: "Coffee", category: "Beverages" };
const SANDWICH = { item: "Sandwich", category: "Food" };
const CAKE = { item: "Cake", category: "Bakery" };

function billEvent(
  r: Restaurant,
  spec: {
    no: number;
    businessDate: string;
    at: number;
    localHour: number;
    orderType: string;
    lines: LineSpec[];
    charges?: Array<{ kind: string; netEx: number; tax: number; total: number }>;
    payments: Array<{ method: string; applied: number; tendered?: number; change?: number }>;
  },
): { event: Event; lineIds: string[]; chargeIds: string[]; billId: string } {
  const billId = crypto.randomUUID();
  const lineIds = spec.lines.map(() => crypto.randomUUID());
  const chargeIds = (spec.charges ?? []).map(() => crypto.randomUUID());
  const sum = (f: (l: LineSpec) => number) => spec.lines.reduce((a, l) => a + f(l), 0);
  const chargesNetEx = (spec.charges ?? []).reduce((a, c) => a + c.netEx, 0);
  const chargesTax = (spec.charges ?? []).reduce((a, c) => a + c.tax, 0);
  const chargesTotal = (spec.charges ?? []).reduce((a, c) => a + c.total, 0);
  const total = sum((l) => l.total) + chargesTotal;
  const changeTotal = spec.payments.reduce((a, p) => a + (p.change ?? 0), 0);
  const bill = {
    id: billId,
    receiptNo: `CD-${String(spec.no).padStart(5, "0")}`,
    receiptSeq: spec.no,
    orderId: crypto.randomUUID(),
    operationId: crypto.randomUUID(),
    orderNo: spec.no,
    orderType: spec.orderType,
    tableLabel: spec.orderType === "dine_in" ? "T4" : null,
    customerName: null,
    guestCount: null,
    businessDate: spec.businessDate,
    localHour: spec.localHour,
    createdAt: spec.at,
    staffId: "cashier-1",
    staffName: "Ravi",
    shiftId: "shift-S1",
    itemCount: sum((l) => l.qty),
    itemsGrossEntered: sum((l) => l.grossEx),
    discountEnteredTotal: sum((l) => l.discountEx),
    itemsGrossEx: sum((l) => l.grossEx),
    itemsDiscountEx: sum((l) => l.discountEx),
    itemsNetEx: sum((l) => l.netEx),
    chargesNetEx,
    taxTotal: sum((l) => l.tax) + chargesTax,
    subtotalBeforeRounding: total,
    roundingAdjustment: 0,
    total,
    changeTotal,
    discountReason: null,
    discountApprovedBy: null,
    currencyCode: "INR",
    timeZone: "Asia/Kolkata",
    restaurantJson: "{}",
  };
  const lines = spec.lines.map((l, i) => ({
    id: lineIds[i],
    billId,
    orderLineId: crypto.randomUUID(),
    itemId: `item-${l.item.toLowerCase()}`,
    itemName: l.item,
    variantName: null,
    categoryId: `cat-${l.category.toLowerCase()}`,
    categoryName: l.category,
    modifiersJson: "[]",
    note: null,
    quantity: l.qty,
    unitPriceEntered: l.grossEx / l.qty,
    grossEntered: l.grossEx,
    lineDiscountEntered: 0,
    billDiscountEntered: l.discountEx,
    grossEx: l.grossEx,
    discountEx: l.discountEx,
    netEx: l.netEx,
    taxMode: l.tax > 0 ? "added" : "none",
    taxRateBps: l.tax > 0 ? 500 : 0,
    tax: l.tax,
    total: l.total,
    sortOrder: i,
  }));
  const charges = (spec.charges ?? []).map((c, i) => ({
    id: chargeIds[i],
    billId,
    kind: c.kind,
    label: "Delivery",
    amountEntered: c.total,
    netEx: c.netEx,
    taxMode: "none",
    taxRateBps: 0,
    tax: c.tax,
    total: c.total,
  }));
  const payments = spec.payments.map((p) => ({
    id: crypto.randomUUID(),
    billId,
    method: p.method,
    applied: p.applied,
    tendered: p.tendered ?? p.applied,
    changeGiven: p.change ?? 0,
    shiftId: "shift-S1",
    businessDate: spec.businessDate,
    createdAt: spec.at,
    confirmedBy: "cashier-1",
    confirmedByName: "Ravi",
  }));
  return {
    event: event(
      r,
      "bill.finalized",
      "bill",
      billId,
      { bill, lines, charges, taxComponents: [], payments },
      { businessDate: spec.businessDate, committedAt: spec.at },
    ),
    lineIds,
    chargeIds,
    billId,
  };
}

function refundEvent(
  r: Restaurant,
  spec: {
    no: number;
    billId: string;
    businessDate: string;
    at: number;
    lines: Array<{ billLineId: string; qty: number; grossEx: number; discountEx: number; netEx: number; tax: number; total: number }>;
    charges?: Array<{ billChargeId: string; netEx: number; tax: number; total: number }>;
    payments: Array<{ method: string; amount: number }>;
  },
): Event {
  const id = crypto.randomUUID();
  const sum = (f: (l: (typeof spec.lines)[number]) => number) => spec.lines.reduce((a, l) => a + f(l), 0);
  const chargesNetEx = (spec.charges ?? []).reduce((a, c) => a + c.netEx, 0);
  const total = sum((l) => l.total) + (spec.charges ?? []).reduce((a, c) => a + c.total, 0);
  const refund = {
    id,
    refundNo: `RF-${spec.no}`,
    billId: spec.billId,
    operationId: crypto.randomUUID(),
    reason: "Spilled",
    authorizedBy: "owner-1",
    authorizedByName: "Owner",
    createdBy: "cashier-1",
    createdByName: "Ravi",
    createdAt: spec.at,
    businessDate: spec.businessDate,
    localHour: 12,
    shiftId: "shift-S1",
    itemsGrossEx: sum((l) => l.grossEx),
    itemsDiscountEx: sum((l) => l.discountEx),
    itemsNetEx: sum((l) => l.netEx),
    chargesNetEx,
    taxTotal: sum((l) => l.tax) + (spec.charges ?? []).reduce((a, c) => a + c.tax, 0),
    roundingAdjustment: 0,
    total,
  };
  const lines = spec.lines.map((l) => ({
    id: crypto.randomUUID(),
    refundId: id,
    billLineId: l.billLineId,
    quantity: l.qty,
    grossEx: l.grossEx,
    discountEx: l.discountEx,
    netEx: l.netEx,
    tax: l.tax,
    total: l.total,
  }));
  const charges = (spec.charges ?? []).map((c) => ({ id: crypto.randomUUID(), refundId: id, ...c }));
  const payments = spec.payments.map((p) => ({
    id: crypto.randomUUID(),
    refundId: id,
    method: p.method,
    amount: p.amount,
    shiftId: "shift-S1",
    businessDate: spec.businessDate,
    createdAt: spec.at,
  }));
  return event(
    r,
    "refund.created",
    "refund",
    id,
    { refund, lines, charges, taxComponents: [], payments },
    { businessDate: spec.businessDate, committedAt: spec.at },
  );
}

function expenseRow(id: string, amount: number, businessDate: string, fromDrawer: boolean, voidedAt: number | null) {
  return {
    id,
    category: "Supplies",
    amount,
    note: null,
    createdBy: "owner-1",
    createdByName: "Owner",
    createdAt: ist(businessDate, "15:00"),
    businessDate,
    paidFromDrawer: fromDrawer,
    shiftId: fromDrawer ? "shift-S1" : null,
    voidedAt,
    voidedBy: voidedAt ? "owner-1" : null,
    voidReason: voidedAt ? "duplicate" : null,
  };
}

function orderView(orderId: string, status: string, cancelBusinessDate: string | null) {
  return {
    orderId,
    orderNo: 99,
    orderRef: "T2 · #99",
    orderType: "dine_in",
    tableId: "t2",
    tableLabel: "T2",
    status,
    revision: status === "cancelled" ? 2 : 1,
    createdBy: "waiter-1",
    createdByName: "Asha",
    createdAt: ist("2026-10-05", "12:00"),
    guestCount: 2,
    note: null,
    cancelledAt: status === "cancelled" ? ist("2026-10-05", "12:10") : null,
    cancelBusinessDate,
    estimatedTotal: 0,
    lines: [],
  };
}

/** Builds the REPORT_DEFINITIONS.md fixture as host events, sent in several batches. */
async function buildFixture(r: Restaurant) {
  const coffee2 = { ...COFFEE, qty: 2, grossEx: 20000, discountEx: 2000, netEx: 18000, tax: 900, total: 18900 };
  const sandwich1Disc = { ...SANDWICH, qty: 1, grossEx: 20000, discountEx: 2000, netEx: 18000, tax: 0, total: 18000 };
  const cake1 = { ...CAKE, qty: 1, grossEx: 10000, discountEx: 0, netEx: 10000, tax: 500, total: 10500 };
  const sandwich1 = { ...SANDWICH, qty: 1, grossEx: 20000, discountEx: 0, netEx: 20000, tax: 0, total: 20000 };
  const coffee3 = { ...COFFEE, qty: 3, grossEx: 30000, discountEx: 0, netEx: 30000, tax: 1500, total: 31500 };

  const shift = event(r, "shift.updated", "shift", "shift-S1", {
    shift: {
      id: "shift-S1",
      openedBy: "owner-1",
      openedByName: "Owner",
      openedAt: ist("2026-10-05", "09:00"),
      openingFloat: 100000,
      status: "open",
      businessDate: "2026-10-05",
      lastClosedAt: null,
    },
    closures: [],
  });
  const b1 = billEvent(r, {
    no: 1, businessDate: "2026-10-05", at: ist("2026-10-05", "10:00"), localHour: 10, orderType: "dine_in",
    lines: [coffee2, sandwich1Disc],
    payments: [{ method: "cash", applied: 36900, tendered: 50000, change: 13100 }],
  });
  const b2 = billEvent(r, {
    no: 2, businessDate: "2026-10-05", at: ist("2026-10-05", "23:30"), localHour: 23, orderType: "takeaway",
    lines: [cake1],
    payments: [{ method: "upi", applied: 5500 }, { method: "card", applied: 5000 }],
  });
  await sendEvents(r, [shift, b1.event, b2.event]);

  const b3 = billEvent(r, {
    no: 3, businessDate: "2026-10-05", at: ist("2026-10-06", "02:30"), localHour: 2, orderType: "takeaway",
    lines: [sandwich1],
    payments: [{ method: "cash", applied: 20000 }],
  });
  const cancelledOrder = crypto.randomUUID();
  const otherOrder = crypto.randomUUID();
  await sendEvents(r, [
    b3.event,
    event(r, "order.updated", "order", cancelledOrder, orderView(cancelledOrder, "open", null)),
    event(r, "order.updated", "order", cancelledOrder, orderView(cancelledOrder, "cancelled", "2026-10-05")),
    event(r, "order.updated", "order", otherOrder, orderView(otherOrder, "open", null)),
    event(r, "expense.recorded", "expense", "E1", { expense: expenseRow("E1", 15000, "2026-10-05", true, null) }),
    event(r, "cash_movement.recorded", "cash_movement", "M1", {
      movement: {
        id: "M1", shiftId: "shift-S1", direction: "out", amount: 10000, reason: "Change run",
        createdBy: "owner-1", createdByName: "Owner", createdAt: ist("2026-10-05", "16:00"), businessDate: "2026-10-05",
      },
    }),
  ]);

  const b4 = billEvent(r, {
    no: 4, businessDate: "2026-10-06", at: ist("2026-10-06", "11:00"), localHour: 11, orderType: "delivery",
    lines: [coffee3],
    charges: [{ kind: "delivery", netEx: 4000, tax: 0, total: 4000 }],
    payments: [{ method: "card", applied: 35500 }],
  });
  const r1 = refundEvent(r, {
    no: 1, billId: b1.billId, businessDate: "2026-10-06", at: ist("2026-10-06", "12:00"),
    lines: [{ billLineId: b1.lineIds[0]!, qty: 1, grossEx: 10000, discountEx: 1000, netEx: 9000, tax: 450, total: 9450 }],
    payments: [{ method: "cash", amount: 9450 }],
  });
  await sendEvents(r, [
    b4.event,
    r1,
    event(r, "expense.recorded", "expense", "E2", { expense: expenseRow("E2", 50000, "2026-10-06", false, null) }),
    event(r, "expense.recorded", "expense", "E3", { expense: expenseRow("E3", 8000, "2026-10-06", true, null) }),
    event(r, "expense.voided", "expense", "E3", {
      expense: expenseRow("E3", 8000, "2026-10-06", true, ist("2026-10-06", "18:00")),
    }),
    event(r, "cash_movement.recorded", "cash_movement", "M2", {
      movement: {
        id: "M2", shiftId: "shift-S1", direction: "in", amount: 5000, reason: "Float top-up",
        createdBy: "owner-1", createdByName: "Owner", createdAt: ist("2026-10-06", "09:30"), businessDate: "2026-10-06",
      },
    }),
  ]);

  // Negative period: B4 fully refunded on 2026-10-07.
  const r2 = refundEvent(r, {
    no: 2, billId: b4.billId, businessDate: "2026-10-07", at: ist("2026-10-07", "10:00"),
    lines: [{ billLineId: b4.lineIds[0]!, qty: 3, grossEx: 30000, discountEx: 0, netEx: 30000, tax: 1500, total: 31500 }],
    charges: [{ billChargeId: b4.chargeIds[0]!, netEx: 4000, tax: 0, total: 4000 }],
    payments: [{ method: "card", amount: 35500 }],
  });
  await sendEvents(r, [r2]);
  return { lastCommittedAt: ist("2026-10-07", "10:00") };
}

async function summary(r: Restaurant, from: string, to: string) {
  const res = await api(`/v1/reports/summary?from=${from}&to=${to}`, { headers: hostHeaders(r) });
  expect(res.status).toBe(200);
  return json(res);
}

describe("cloud report fixture (docs/REPORT_DEFINITIONS.md)", () => {
  it("reproduces every hand-calculated card", async () => {
    const r = await newRestaurant();
    const { lastCommittedAt } = await buildFixture(r);

    const day1 = await summary(r, "2026-10-05", "2026-10-06");
    expect(day1.cards).toEqual({
      completedBills: 3,
      billsTotal: 67400,
      averageBill: 22467, // 67400 / 3 = 22466.67 → 22467
      itemGrossSales: 70000,
      discounts: 4000,
      discountReversals: 0,
      netItemSales: 66000,
      charges: 0,
      chargeRefunds: 0,
      netCharges: 0,
      taxesCollected: 1400,
      taxesReversed: 0,
      refunds: 0,
      refundsTotal: 0,
      netBilledValue: 67400,
      receiptsByMethod: { card: 5000, cash: 56900, upi: 5500 },
      refundsByMethod: {},
      expenses: 15000,
      expensesFromDrawer: 15000,
      operatingSurplusEstimate: 51000,
      drawerCashIn: 0,
      drawerCashOut: 10000,
      netCashMovement: 31900, // 569.00 − 0 + 0 − 100.00 − 150.00
      cancellations: 1,
    });
    expect(day1.orderTypes).toEqual([
      { orderType: "dine_in", bills: 1, total: 36900 },
      { orderType: "takeaway", bills: 2, total: 30500 },
    ]);
    expect(day1.hourly[2]).toBe(20000);
    expect(day1.hourly[10]).toBe(36900);
    expect(day1.hourly[23]).toBe(10500);
    expect(day1.hourly.reduce((a: number, b: number) => a + b, 0)).toBe(67400);
    expect(day1.topItems).toEqual([
      { name: "Sandwich", netQuantity: 2, netSales: 38000 },
      { name: "Coffee", netQuantity: 2, netSales: 18000 },
      { name: "Cake", netQuantity: 1, netSales: 10000 },
    ]);

    const day2 = await summary(r, "2026-10-06", "2026-10-07");
    expect(day2.cards).toMatchObject({
      completedBills: 1,
      billsTotal: 35500,
      averageBill: 35500,
      itemGrossSales: 30000,
      discounts: 0,
      discountReversals: 1000,
      netItemSales: 21000,
      charges: 4000,
      chargeRefunds: 0,
      taxesCollected: 1500,
      taxesReversed: 450,
      refunds: 1,
      refundsTotal: 9450,
      netBilledValue: 26050,
      receiptsByMethod: { card: 35500 },
      refundsByMethod: { cash: 9450 },
      expenses: 50000, // the voided 80.00 is excluded
      expensesFromDrawer: 0,
      operatingSurplusEstimate: -25000,
      netCashMovement: -4450, // 0 − 94.50 + 50.00 − 0 − 0
      cancellations: 0,
    });
    expect(day2.topItems).toEqual([{ name: "Coffee", netQuantity: 2, netSales: 21000 }]);
    expect(day2.refundList).toHaveLength(1);
    expect(day2.refundList[0]).toMatchObject({ refundNo: "RF-1", originalReceiptNo: "CD-00001", total: 9450 });

    const both = await summary(r, "2026-10-05", "2026-10-07");
    expect(both.cards).toMatchObject({
      completedBills: 4,
      billsTotal: 102900,
      averageBill: 25725,
      netItemSales: 87000,
      netBilledValue: 93450,
      operatingSurplusEstimate: 26000,
    });
    expect(both.daily).toEqual([
      { date: "2026-10-05", bills: 3, billsTotal: 67400, refundsTotal: 0, netBilledValue: 67400 },
      { date: "2026-10-06", bills: 1, billsTotal: 35500, refundsTotal: 9450, netBilledValue: 26050 },
    ]);

    const negative = await summary(r, "2026-10-07", "2026-10-08");
    expect(negative.cards).toMatchObject({
      completedBills: 0,
      averageBill: 0,
      netBilledValue: -35500,
      netItemSales: -30000,
      chargeRefunds: 4000,
      refundsByMethod: { card: 35500 },
    });

    // Freshness: which host, how far the ledger is acknowledged, and when.
    expect(negative.freshness).toMatchObject({
      source: { hostDeviceId: r.hostDeviceId },
      ackedThrough: { hostEpoch: 1, sequence: r.nextSeq - 1 },
      lastEventCommittedAt: lastCommittedAt,
    });
    expect(negative.freshness.lastIngestedAt).toBeGreaterThan(0);

    // Shift S1 is projected too (for drawer views later).
    const shift = await env.DB.prepare("SELECT opening_float, status FROM proj_shifts WHERE restaurant_id = ?1 AND id = 'shift-S1'")
      .bind(r.restaurantId)
      .first();
    expect(shift).toEqual({ opening_float: 100000, status: "open" });
  });

  it("rebuilding projections from the ledger yields identical rows and report numbers", async () => {
    const r = await newRestaurant();
    await buildFixture(r);
    const ranges: Array<[string, string]> = [
      ["2026-10-05", "2026-10-06"],
      ["2026-10-06", "2026-10-07"],
      ["2026-10-05", "2026-10-08"],
    ];
    const strip = (report: any) => ({ ...report, generatedAt: 0 });
    const before = await Promise.all(ranges.map(([f, t]) => summary(r, f, t)));
    const snapshot = async () => {
      const out: Record<string, unknown[]> = {};
      for (const table of PROJECTION_TABLES) {
        out[table] = (
          await env.DB.prepare(`SELECT * FROM ${table} WHERE restaurant_id = ?1 ORDER BY 2`).bind(r.restaurantId).all()
        ).results;
      }
      return out;
    };
    const rowsBefore = await snapshot();
    expect(rowsBefore["proj_bills"]).toHaveLength(4);

    // Corrupt the projections, then rebuild twice.
    await env.DB.prepare("DELETE FROM proj_bills WHERE restaurant_id = ?1").bind(r.restaurantId).run();
    await env.DB.prepare("UPDATE proj_expenses SET amount = 1 WHERE restaurant_id = ?1").bind(r.restaurantId).run();
    await rebuildProjections(env.DB, r.restaurantId);
    await rebuildProjections(env.DB, r.restaurantId);

    expect(await snapshot()).toEqual(rowsBefore);
    const after = await Promise.all(ranges.map(([f, t]) => summary(r, f, t)));
    expect(after.map(strip)).toEqual(before.map(strip));
  });

  it("validates the date range", async () => {
    const r = await newRestaurant();
    for (const query of ["from=2026-10-06&to=2026-10-05", "from=2026-02-30&to=2026-03-01", "from=2026-10-05", "from=2020-01-01&to=2026-01-01"]) {
      const res = await api(`/v1/reports/summary?${query}`, { headers: hostHeaders(r) });
      expect(res.status).toBe(400);
      expect((await json(res)).error.code).toBe("VALIDATION");
    }
  });
});

describe("divRoundHalfUp", () => {
  it("rounds half away from zero with integers only", () => {
    expect(divRoundHalfUp(67400, 3)).toBe(22467);
    expect(divRoundHalfUp(5, 2)).toBe(3);
    expect(divRoundHalfUp(4, 3)).toBe(1);
    expect(divRoundHalfUp(-5, 2)).toBe(-3);
    expect(divRoundHalfUp(9007199254740991, 2)).toBe(4503599627370496);
  });
});
