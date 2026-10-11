// Input validation for every request body, event payload and hub message.
//
// Objects are "loose": unknown fields are kept and ignored, because adding an
// optional field is a compatible change (docs/PROTOCOL.md §1). Hashes are always
// computed over the raw parsed JSON, never over a schema's output.

import { z } from "zod";
import { ApiError } from "../http/errors";
import { b64urlDecode } from "./canonical";
import { COMMAND_ACTIONS, DEVICE_KINDS, MAX_LINES_PER_COMMAND, RELAY_KINDS, STAFF_ROLES } from "./constants";

export const ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

export const Id = z.string().regex(ID_PATTERN, "must be 1–64 characters of [A-Za-z0-9_-]");
const Int = z.int();
const NonNegative = z.int().min(0);
const Positive = z.int().min(1);

export function isValidBusinessDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;
  const [year, month, day] = [Number(match[1]), Number(match[2]), Number(match[3])];
  const date = new Date(Date.UTC(year, month - 1, day));
  return date.getUTCFullYear() === year && date.getUTCMonth() === month - 1 && date.getUTCDate() === day;
}

export const BusinessDate = z.string().refine(isValidBusinessDate, "must be a YYYY-MM-DD date");
export const Sha256Hex = z.string().regex(/^[0-9a-f]{64}$/, "must be 64 lower-case hex characters");

function b64urlOfLength(bytes: number) {
  return z.string().refine((s) => b64urlDecode(s)?.byteLength === bytes, `must be ${bytes} bytes, base64url`);
}

const Text = (max: number) => z.string().max(max);

// ---------------------------------------------------------------------------
// Validation helper
// ---------------------------------------------------------------------------

export function parseOrThrow<T>(schema: z.ZodType<T>, value: unknown, what: string): T {
  const result = schema.safeParse(value);
  if (result.success) return result.data;
  const issues = result.error.issues.slice(0, 10).map((issue) => ({
    path: issue.path.map(String).join("."),
    message: issue.message,
  }));
  throw new ApiError("VALIDATION", `Invalid ${what}`, { issues });
}

// ---------------------------------------------------------------------------
// Enrollment and host requests (§8)
// ---------------------------------------------------------------------------

export const EnrollRequest = z.looseObject({
  protocolVersion: Int.optional(),
  enrollmentCode: z.string().min(1).max(64),
  // Created by the host when it first starts in connected mode (devices may
  // be paired over the LAN before the café ever reaches the cloud).
  restaurantId: Id,
  restaurantName: z.string().trim().min(1).max(100),
  hostDeviceId: Id,
  hostSigningPublicKey: b64urlOfLength(32),
  hostSealPublicKey: b64urlOfLength(32),
  appVersion: z.string().min(1).max(32),
});

export const OpenEpochRequest = z.looseObject({
  epoch: Positive,
  startSequence: Positive,
  reason: z.string().trim().min(1).max(200),
});

// ---------------------------------------------------------------------------
// Events (§5)
// ---------------------------------------------------------------------------

export const EventEnvelope = z.looseObject({
  protocolVersion: Int,
  eventId: Id,
  hostEpoch: Positive,
  sequence: Positive,
  type: z
    .string()
    .max(64)
    .regex(/^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$/, "must look like 'aggregate.verb'"),
  aggregateType: z.string().min(1).max(64),
  aggregateId: Id,
  revision: NonNegative,
  committedAtUtc: NonNegative,
  businessDate: BusinessDate.nullable(),
  payload: z.record(z.string(), z.unknown()),
});
export type EventEnvelope = z.infer<typeof EventEnvelope>;

export const EventBatch = z.looseObject({
  protocolVersion: Int.optional(),
  hostEpoch: Positive,
  events: z.array(z.unknown()),
});

// Financial rows: the host's Drift rows, camelCase (lib/core/database/tables.dart).

const BillRow = z.looseObject({
  id: Id,
  receiptNo: z.string().min(1).max(64),
  orderId: Id,
  orderNo: Int,
  orderType: z.string().min(1).max(32),
  businessDate: BusinessDate,
  localHour: z.int().min(0).max(23),
  createdAt: NonNegative,
  shiftId: Id,
  itemCount: NonNegative,
  itemsGrossEx: Int,
  itemsDiscountEx: Int,
  itemsNetEx: Int,
  chargesNetEx: Int,
  taxTotal: Int,
  roundingAdjustment: Int,
  total: NonNegative,
  changeTotal: NonNegative,
});

const BillLineRow = z.looseObject({
  id: Id,
  billId: Id,
  itemId: Id.nullish(),
  itemName: z.string().min(1).max(200),
  variantName: Text(200).nullish(),
  categoryName: Text(200).nullish(),
  quantity: Positive,
  grossEx: Int,
  discountEx: Int,
  netEx: Int,
  tax: Int,
  total: Int,
});

const BillChargeRow = z.looseObject({
  id: Id,
  billId: Id,
  kind: z.string().min(1).max(32),
  netEx: Int,
  tax: Int,
  total: Int,
});

const PaymentRow = z.looseObject({
  id: Id,
  billId: Id,
  method: z.string().min(1).max(32),
  applied: Positive,
  tendered: Int,
  changeGiven: NonNegative,
  shiftId: Id,
  businessDate: BusinessDate,
  createdAt: NonNegative,
});

const BillFinalized = z.looseObject({
  bill: BillRow,
  lines: z.array(BillLineRow),
  charges: z.array(BillChargeRow),
  taxComponents: z.array(z.unknown()),
  payments: z.array(PaymentRow),
});

const RefundRow = z.looseObject({
  id: Id,
  refundNo: z.string().min(1).max(64),
  billId: Id,
  businessDate: BusinessDate,
  localHour: z.int().min(0).max(23),
  createdAt: NonNegative,
  shiftId: Id.nullish(),
  itemsGrossEx: Int,
  itemsDiscountEx: Int,
  itemsNetEx: Int,
  chargesNetEx: Int,
  taxTotal: Int,
  roundingAdjustment: Int,
  total: Positive,
});

const RefundLineRow = z.looseObject({
  id: Id,
  refundId: Id,
  billLineId: Id,
  quantity: Positive,
  grossEx: Int,
  discountEx: Int,
  netEx: Int,
  tax: Int,
  total: Int,
});

const RefundChargeRow = z.looseObject({
  id: Id,
  refundId: Id,
  billChargeId: Id,
  netEx: Int,
  tax: Int,
  total: Int,
});

const RefundPaymentRow = z.looseObject({
  id: Id,
  refundId: Id,
  method: z.string().min(1).max(32),
  amount: Positive,
  shiftId: Id.nullish(),
  businessDate: BusinessDate,
  createdAt: NonNegative,
});

const RefundCreated = z.looseObject({
  refund: RefundRow,
  lines: z.array(RefundLineRow),
  charges: z.array(RefundChargeRow),
  taxComponents: z.array(z.unknown()),
  payments: z.array(RefundPaymentRow),
});

const ExpenseRow = z.looseObject({
  id: Id,
  category: z.string().min(1).max(100),
  amount: Positive,
  businessDate: BusinessDate,
  paidFromDrawer: z.boolean(),
  shiftId: Id.nullish(),
  createdAt: NonNegative,
  voidedAt: NonNegative.nullish(),
});

const CashMovementRow = z.looseObject({
  id: Id,
  shiftId: Id,
  direction: z.enum(["in", "out"]),
  amount: Positive,
  businessDate: BusinessDate,
  createdAt: NonNegative,
});

const ShiftRow = z.looseObject({
  id: Id,
  openedAt: NonNegative,
  openingFloat: NonNegative,
  status: z.string().min(1).max(32),
  businessDate: BusinessDate,
  lastClosedAt: NonNegative.nullish(),
});

const OrderView = z.looseObject({
  orderId: Id,
  orderNo: Int,
  orderType: z.string().min(1).max(32),
  status: z.string().min(1).max(32),
  revision: NonNegative,
  cancelledAt: NonNegative.nullish(),
  cancelBusinessDate: BusinessDate.nullish(),
});

const TicketView = z.looseObject({
  ticketId: Id,
  status: z.string().min(1).max(32),
  revision: NonNegative,
});

export const DevicePaired = z.looseObject({
  deviceId: Id,
  role: z.enum(DEVICE_KINDS),
  name: z.string().min(1).max(100),
  credentialHash: Sha256Hex,
  pairedAt: NonNegative,
});
export type DevicePaired = z.infer<typeof DevicePaired>;

export const DeviceRevoked = z.looseObject({ deviceId: Id, revokedAt: NonNegative });
export const SessionRevoked = z.looseObject({ sid: Id, staffId: Id, revokedAt: NonNegative });
export const StaffAccessChanged = z.looseObject({
  staffId: Id,
  role: z.enum(STAFF_ROLES),
  disabled: z.boolean(),
});

function sameIds(rows: ReadonlyArray<Record<string, unknown>>, field: string, id: string): boolean {
  return rows.every((row) => row[field] === id);
}

/**
 * Validates the payload of known event types and returns the aggregate ID the
 * payload implies (it must equal the envelope's aggregateId). Unknown types are
 * stored as they are (§1: clients ignore unknown event types).
 */
export function validateEventPayload(event: EventEnvelope): void {
  const where = `payload of ${event.type} #${event.sequence}`;
  let aggregateId: string | null = null;
  switch (event.type) {
    case "bill.finalized": {
      const p = parseOrThrow(BillFinalized, event.payload, where);
      const id = p.bill.id;
      if (!sameIds(p.lines, "billId", id) || !sameIds(p.charges, "billId", id) || !sameIds(p.payments, "billId", id)) {
        throw new ApiError("VALIDATION", `Invalid ${where}: rows must belong to bill ${id}`);
      }
      aggregateId = id;
      break;
    }
    case "refund.created": {
      const p = parseOrThrow(RefundCreated, event.payload, where);
      const id = p.refund.id;
      if (!sameIds(p.lines, "refundId", id) || !sameIds(p.charges, "refundId", id) || !sameIds(p.payments, "refundId", id)) {
        throw new ApiError("VALIDATION", `Invalid ${where}: rows must belong to refund ${id}`);
      }
      aggregateId = id;
      break;
    }
    case "expense.recorded":
    case "expense.voided": {
      const p = parseOrThrow(z.looseObject({ expense: ExpenseRow }), event.payload, where);
      if (event.type === "expense.voided" && (p.expense.voidedAt === null || p.expense.voidedAt === undefined)) {
        throw new ApiError("VALIDATION", `Invalid ${where}: voidedAt is required`);
      }
      aggregateId = p.expense.id;
      break;
    }
    case "cash_movement.recorded":
      aggregateId = parseOrThrow(z.looseObject({ movement: CashMovementRow }), event.payload, where).movement.id;
      break;
    case "shift.updated":
      aggregateId = parseOrThrow(z.looseObject({ shift: ShiftRow, closures: z.array(z.unknown()) }), event.payload, where)
        .shift.id;
      break;
    case "order.updated": {
      const p = parseOrThrow(OrderView, event.payload, where);
      if (p.status === "cancelled" && !p.cancelBusinessDate) {
        throw new ApiError("VALIDATION", `Invalid ${where}: a cancelled order needs cancelBusinessDate`);
      }
      aggregateId = p.orderId;
      break;
    }
    case "ticket.updated":
      aggregateId = parseOrThrow(TicketView, event.payload, where).ticketId;
      break;
    case "device.paired":
      aggregateId = parseOrThrow(DevicePaired, event.payload, where).deviceId;
      break;
    case "device.revoked":
      aggregateId = parseOrThrow(DeviceRevoked, event.payload, where).deviceId;
      break;
    case "session.revoked":
      aggregateId = parseOrThrow(SessionRevoked, event.payload, where).sid;
      break;
    case "staff.access_changed":
      aggregateId = parseOrThrow(StaffAccessChanged, event.payload, where).staffId;
      break;
    default:
      return; // menu.changed, tables.changed and future types: nothing to check
  }
  if (aggregateId !== event.aggregateId) {
    throw new ApiError("VALIDATION", `Invalid ${where}: aggregateId must be ${aggregateId}`);
  }
}

// ---------------------------------------------------------------------------
// Commands (§4)
// ---------------------------------------------------------------------------

export const CommandEnvelope = z.looseObject({
  protocolVersion: Int,
  commandId: Id,
  restaurantId: Id,
  deviceId: Id,
  staffId: Id,
  hostEpoch: Positive,
  action: z.string().min(1).max(64),
  aggregateId: Id.nullable(),
  expectedRevision: NonNegative.nullable(),
  issuedAt: NonNegative,
  payload: z.record(z.string(), z.unknown()),
});
export type CommandEnvelope = z.infer<typeof CommandEnvelope>;

const Line = z.looseObject({
  itemId: Id,
  variantId: Id.nullish(),
  modifierIds: z.array(Id).max(50).optional(),
  quantity: z.int().min(1).max(99),
  note: z.string().max(140).nullish(),
  expectedUnitPrice: NonNegative,
});

const Lines = z.array(Line).min(1).max(MAX_LINES_PER_COMMAND);

const ACTION_RULES: Record<
  (typeof COMMAND_ACTIONS)[number],
  { aggregate: "null" | "id"; revision: "null" | "optional" | "required"; payload: z.ZodType }
> = {
  "order.place": {
    aggregate: "null",
    revision: "null",
    payload: z.looseObject({
      orderType: z.enum(["dine_in", "takeaway"]),
      tableId: Id.nullish(),
      guestCount: z.int().min(1).max(999).nullish(),
      note: z.string().max(500).nullish(),
      lines: Lines,
      sendToKitchen: z.boolean(),
    }),
  },
  "order.add": {
    aggregate: "id",
    revision: "optional",
    payload: z.looseObject({ lines: Lines, sendToKitchen: z.boolean() }),
  },
  "order.change_quantity": {
    aggregate: "id",
    revision: "required",
    payload: z.looseObject({
      lineId: Id,
      quantity: z.int().min(0).max(99),
      reason: z.string().max(500).nullish(),
      approvalId: Id.nullish(),
    }),
  },
  "order.send_to_kitchen": {
    aggregate: "id",
    revision: "null",
    payload: z.looseObject({}),
  },
  "ticket.set_status": {
    aggregate: "id",
    revision: "required",
    payload: z.looseObject({ status: z.enum(["preparing", "ready"]) }),
  },
};

export function isKnownAction(action: string): action is (typeof COMMAND_ACTIONS)[number] {
  return (COMMAND_ACTIONS as readonly string[]).includes(action);
}

/** §4.4 rules on aggregateId / expectedRevision / payload for a known action. */
export function validateCommandAction(command: CommandEnvelope & { action: (typeof COMMAND_ACTIONS)[number] }): void {
  const rule = ACTION_RULES[command.action];
  if (rule.aggregate === "null" && command.aggregateId !== null) {
    throw new ApiError("VALIDATION", `${command.action} takes aggregateId null`);
  }
  if (rule.aggregate === "id" && command.aggregateId === null) {
    throw new ApiError("VALIDATION", `${command.action} needs an aggregateId`);
  }
  if (rule.revision === "null" && command.expectedRevision !== null) {
    throw new ApiError("VALIDATION", `${command.action} takes expectedRevision null`);
  }
  if (rule.revision === "required" && command.expectedRevision === null) {
    throw new ApiError("VALIDATION", `${command.action} needs an expectedRevision`);
  }
  parseOrThrow(rule.payload, command.payload, `payload of ${command.action}`);
}

/** Line count over the limit is TOO_LARGE (§4.5), checked before full validation. */
export function checkLineCount(payload: unknown): void {
  if (typeof payload === "object" && payload !== null && "lines" in payload) {
    const lines = (payload as { lines: unknown }).lines;
    if (Array.isArray(lines) && lines.length > MAX_LINES_PER_COMMAND) {
      throw new ApiError("TOO_LARGE", `At most ${MAX_LINES_PER_COMMAND} lines per command`, {
        maxLines: MAX_LINES_PER_COMMAND,
      });
    }
  }
}

// ---------------------------------------------------------------------------
// Device relay requests (§6, §8)
// ---------------------------------------------------------------------------

const Sealed = z.looseObject({
  v: z.literal(1),
  alg: z.literal("X25519-HKDF-SHA256-A256GCM"),
  epk: b64urlOfLength(32),
  nonce: b64urlOfLength(12),
  ct: z.string().min(22).max(16_384).regex(/^[A-Za-z0-9_-]+$/),
});

export const RelayRequest = z.looseObject({
  protocolVersion: Int.optional(),
  kind: z.enum(RELAY_KINDS),
  body: z.record(z.string(), z.unknown()),
});

export const RELAY_BODIES = {
  sealed_auth: z.looseObject({ sealed: Sealed }),
  snapshot: z.looseObject({ scope: z.enum(["waiter", "kitchen"]) }),
  command_lookup: z.looseObject({ commandId: Id }),
} as const;

// ---------------------------------------------------------------------------
// Staff session token claims (§3.2)
// ---------------------------------------------------------------------------

export const SessionClaims = z.looseObject({
  v: z.literal(1),
  sid: Id,
  rid: Id,
  did: Id,
  sub: Id,
  name: z.string().max(100),
  role: z.enum(STAFF_ROLES),
  ep: Positive,
  iat: NonNegative,
  exp: NonNegative,
});
export type SessionClaims = z.infer<typeof SessionClaims>;

// ---------------------------------------------------------------------------
// Host socket messages (§8.1)
// ---------------------------------------------------------------------------

export const CommandResult = z.looseObject({
  commandId: Id,
  state: z.enum(["accepted", "rejected"]),
  resultId: Id.nullish(),
  revision: NonNegative.nullish(),
  hostEpoch: Positive,
  eventSequence: NonNegative,
  acceptedAt: NonNegative.nullish(),
  result: z.record(z.string(), z.unknown()).nullish(),
  error: z
    .looseObject({
      code: z.string().min(1).max(64),
      message: z.string().max(1000),
      retryable: z.boolean(),
      details: z.record(z.string(), z.unknown()).nullish(),
    })
    .nullish(),
});
export type CommandResult = z.infer<typeof CommandResult>;

export const HostMessage = z.discriminatedUnion("t", [
  z.looseObject({ t: z.literal("result"), result: CommandResult }),
  z.looseObject({
    t: z.literal("response"),
    requestId: z.string().min(1).max(128),
    status: z.int().min(200).max(599),
    body: z.unknown(),
  }),
  z.looseObject({ t: z.literal("events_available"), hostEpoch: Positive, latestSequence: NonNegative }),
  z.looseObject({ t: z.literal("ping") }),
  z.looseObject({ t: z.literal("pong") }),
]);
export type HostMessage = z.infer<typeof HostMessage>;
