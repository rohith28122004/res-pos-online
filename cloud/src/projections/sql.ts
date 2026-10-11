// Report projections, expressed as SQL over the immutable event ledger.
//
// The same statements serve three callers, so there is exactly one definition
// of how an event becomes projection rows:
//   * event ingest (src/ingest/ingest.ts) — inside the ingest D1 batch, over
//     the sequence range that batch just appended to the ledger;
//   * rebuildProjections() (src/projections/rebuild.ts) — over the whole ledger;
//   * scripts/rebuild-projections.mjs — the operator CLI for the local D1.
//
// This module is deliberately self-contained (no imports, erasable TypeScript
// only) so that Node can load it directly for the CLI script.
//
// Every statement takes the parameters:
//   ?1 restaurant_id   ?2 host_epoch   ?3 first sequence   ?4 last sequence
//
// Rows carry src_epoch / src_seq (the event that wrote them). An upsert only
// replaces a row with data from the same or a newer event, so replays in any
// order and repeated replays converge on the newest snapshot (idempotent).
// Payload rows are the host's Drift rows serialized with camelCase field names
// (lib/core/database/tables.dart); ingest validates them before they reach the
// ledger, so json_extract never meets a missing required field here.

interface Projection {
  /** Projection table. */
  readonly table: string;
  /** Primary key column besides restaurant_id. */
  readonly key: string;
  /** Event types that carry rows for this table. */
  readonly eventTypes: readonly string[];
  /** JSON path of the row (or rows) inside the event payload. */
  readonly path: string;
  /** True when `path` points at an array of rows. */
  readonly many: boolean;
  /** [column, camelCase field of the row object]. */
  readonly columns: ReadonlyArray<readonly [string, string]>;
  /** Only rows whose [field] equals [value] (a constant from this file). */
  readonly where?: readonly [string, string];
}

export const PROJECTIONS: readonly Projection[] = [
  {
    table: "proj_bills",
    key: "id",
    eventTypes: ["bill.finalized"],
    path: "$.bill",
    many: false,
    columns: [
      ["id", "id"],
      ["receipt_no", "receiptNo"],
      ["order_id", "orderId"],
      ["order_no", "orderNo"],
      ["order_type", "orderType"],
      ["business_date", "businessDate"],
      ["local_hour", "localHour"],
      ["created_at", "createdAt"],
      ["shift_id", "shiftId"],
      ["item_count", "itemCount"],
      ["items_gross_ex", "itemsGrossEx"],
      ["items_discount_ex", "itemsDiscountEx"],
      ["items_net_ex", "itemsNetEx"],
      ["charges_net_ex", "chargesNetEx"],
      ["tax_total", "taxTotal"],
      ["rounding_adjustment", "roundingAdjustment"],
      ["total", "total"],
      ["change_total", "changeTotal"],
    ],
  },
  {
    table: "proj_bill_lines",
    key: "id",
    eventTypes: ["bill.finalized"],
    path: "$.lines",
    many: true,
    columns: [
      ["id", "id"],
      ["bill_id", "billId"],
      ["item_id", "itemId"],
      ["item_name", "itemName"],
      ["variant_name", "variantName"],
      ["category_name", "categoryName"],
      ["quantity", "quantity"],
      ["gross_ex", "grossEx"],
      ["discount_ex", "discountEx"],
      ["net_ex", "netEx"],
      ["tax", "tax"],
      ["total", "total"],
    ],
  },
  {
    table: "proj_bill_charges",
    key: "id",
    eventTypes: ["bill.finalized"],
    path: "$.charges",
    many: true,
    columns: [
      ["id", "id"],
      ["bill_id", "billId"],
      ["kind", "kind"],
      ["net_ex", "netEx"],
      ["tax", "tax"],
      ["total", "total"],
    ],
  },
  {
    table: "proj_payments",
    key: "id",
    eventTypes: ["bill.finalized"],
    path: "$.payments",
    many: true,
    columns: [
      ["id", "id"],
      ["bill_id", "billId"],
      ["method", "method"],
      ["applied", "applied"],
      ["tendered", "tendered"],
      ["change_given", "changeGiven"],
      ["business_date", "businessDate"],
      ["shift_id", "shiftId"],
      ["created_at", "createdAt"],
    ],
  },
  {
    table: "proj_refunds",
    key: "id",
    eventTypes: ["refund.created"],
    path: "$.refund",
    many: false,
    columns: [
      ["id", "id"],
      ["refund_no", "refundNo"],
      ["bill_id", "billId"],
      ["business_date", "businessDate"],
      ["local_hour", "localHour"],
      ["created_at", "createdAt"],
      ["shift_id", "shiftId"],
      ["items_gross_ex", "itemsGrossEx"],
      ["items_discount_ex", "itemsDiscountEx"],
      ["items_net_ex", "itemsNetEx"],
      ["charges_net_ex", "chargesNetEx"],
      ["tax_total", "taxTotal"],
      ["rounding_adjustment", "roundingAdjustment"],
      ["total", "total"],
    ],
  },
  {
    table: "proj_refund_lines",
    key: "id",
    eventTypes: ["refund.created"],
    path: "$.lines",
    many: true,
    columns: [
      ["id", "id"],
      ["refund_id", "refundId"],
      ["bill_line_id", "billLineId"],
      ["quantity", "quantity"],
      ["gross_ex", "grossEx"],
      ["discount_ex", "discountEx"],
      ["net_ex", "netEx"],
      ["tax", "tax"],
      ["total", "total"],
    ],
  },
  {
    table: "proj_refund_charges",
    key: "id",
    eventTypes: ["refund.created"],
    path: "$.charges",
    many: true,
    columns: [
      ["id", "id"],
      ["refund_id", "refundId"],
      ["bill_charge_id", "billChargeId"],
      ["net_ex", "netEx"],
      ["tax", "tax"],
      ["total", "total"],
    ],
  },
  {
    table: "proj_refund_payments",
    key: "id",
    eventTypes: ["refund.created"],
    path: "$.payments",
    many: true,
    columns: [
      ["id", "id"],
      ["refund_id", "refundId"],
      ["method", "method"],
      ["amount", "amount"],
      ["business_date", "businessDate"],
      ["shift_id", "shiftId"],
      ["created_at", "createdAt"],
    ],
  },
  {
    // expense.voided carries the full row with voidedAt set; the newer event wins.
    table: "proj_expenses",
    key: "id",
    eventTypes: ["expense.recorded", "expense.voided"],
    path: "$.expense",
    many: false,
    columns: [
      ["id", "id"],
      ["category", "category"],
      ["amount", "amount"],
      ["business_date", "businessDate"],
      ["paid_from_drawer", "paidFromDrawer"],
      ["shift_id", "shiftId"],
      ["created_at", "createdAt"],
      ["voided_at", "voidedAt"],
    ],
  },
  {
    table: "proj_cash_movements",
    key: "id",
    eventTypes: ["cash_movement.recorded"],
    path: "$.movement",
    many: false,
    columns: [
      ["id", "id"],
      ["shift_id", "shiftId"],
      ["direction", "direction"],
      ["amount", "amount"],
      ["business_date", "businessDate"],
      ["created_at", "createdAt"],
    ],
  },
  {
    table: "proj_shifts",
    key: "id",
    eventTypes: ["shift.updated"],
    path: "$.shift",
    many: false,
    columns: [
      ["id", "id"],
      ["opened_at", "openedAt"],
      ["opening_float", "openingFloat"],
      ["status", "status"],
      ["business_date", "businessDate"],
      ["last_closed_at", "lastClosedAt"],
    ],
  },
  {
    // order.updated carries the OrderView; only cancelled orders are projected.
    table: "proj_order_cancellations",
    key: "order_id",
    eventTypes: ["order.updated"],
    path: "$",
    many: false,
    columns: [
      ["order_id", "orderId"],
      ["order_no", "orderNo"],
      ["order_type", "orderType"],
      ["cancelled_at", "cancelledAt"],
      ["cancel_business_date", "cancelBusinessDate"],
    ],
    where: ["status", "cancelled"],
  },
];

/** Every projection table, for clearing before a rebuild. */
export const PROJECTION_TABLES: readonly string[] = PROJECTIONS.map((p) => p.table);

// The ledger stores the whole event (events.event_json); `path` is relative to
// its payload, so "$.bill" becomes "$.payload.bill".
function eventPath(p: Projection): string {
  return `$.payload${p.path.slice(1)}`;
}

function fieldExpression(p: Projection, field: string): string {
  if (p.many) return `json_extract(r.value, '$.${field}')`;
  return `json_extract(e.event_json, '${eventPath(p)}.${field}')`;
}

function projectionSql(p: Projection): string {
  const columns = p.columns.map(([column]) => column);
  const values = p.columns.map(([, field]) => fieldExpression(p, field));
  const types = p.eventTypes.map((t) => `'${t}'`).join(", ");
  const from = p.many ? `events AS e, json_each(e.event_json, '${eventPath(p)}') AS r` : "events AS e";
  const filter = p.where ? `\n  AND ${fieldExpression(p, p.where[0])} = '${p.where[1]}'` : "";
  const updates = [...columns.filter((c) => c !== p.key), "src_epoch", "src_seq"]
    .map((c) => `${c} = excluded.${c}`)
    .join(", ");
  return [
    `INSERT INTO ${p.table} (restaurant_id, ${columns.join(", ")}, src_epoch, src_seq)`,
    `SELECT e.restaurant_id, ${values.join(", ")}, e.host_epoch, e.sequence`,
    `FROM ${from}`,
    `WHERE e.restaurant_id = ?1 AND e.host_epoch = ?2 AND e.sequence BETWEEN ?3 AND ?4`,
    `  AND e.type IN (${types})${filter}`,
    `ORDER BY e.host_epoch, e.sequence`,
    `ON CONFLICT (restaurant_id, ${p.key}) DO UPDATE SET ${updates}`,
    `WHERE excluded.src_epoch > ${p.table}.src_epoch`,
    `   OR (excluded.src_epoch = ${p.table}.src_epoch AND excluded.src_seq >= ${p.table}.src_seq)`,
  ].join("\n");
}

/** One upsert statement per projection table; parameters ?1..?4 as above. */
export const PROJECTION_STATEMENTS: readonly string[] = PROJECTIONS.map(projectionSql);

/** Statements that clear one restaurant's projections (?1 restaurant_id). */
export const CLEAR_PROJECTION_STATEMENTS: readonly string[] = PROJECTION_TABLES.map(
  (table) => `DELETE FROM ${table} WHERE restaurant_id = ?1`,
);

const SAFE_ID = /^[A-Za-z0-9_-]{1,64}$/;

/**
 * Replaces ?N placeholders with SQL literals, for `wrangler d1 execute --command`
 * (which cannot bind parameters). Only IDs and safe integers are accepted, so
 * the result cannot contain injected SQL.
 */
export function inlineParameters(sql: string, params: ReadonlyArray<string | number>): string {
  return sql.replace(/\?(\d+)/g, (_match, index: string) => {
    const value = params[Number(index) - 1];
    if (typeof value === "number" && Number.isSafeInteger(value)) return String(value);
    if (typeof value === "string" && SAFE_ID.test(value)) return `'${value}'`;
    throw new Error(`Parameter ?${index} must be an ID or a safe integer`);
  });
}
