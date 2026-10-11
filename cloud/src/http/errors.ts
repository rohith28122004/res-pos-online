// Structured errors: {error:{code,message,retryable,details}} (docs/PROTOCOL.md §4.5).

import { MAX_PROTOCOL_VERSION, MIN_PROTOCOL_VERSION } from "../protocol/constants";

export type ErrorCode =
  | "UPDATE_REQUIRED"
  | "UNAUTHENTICATED"
  | "SESSION_EXPIRED"
  | "DEVICE_REVOKED"
  | "FORBIDDEN"
  | "STAFF_DISABLED"
  | "VALIDATION"
  | "TOO_LARGE"
  | "RATE_LIMITED"
  | "EPOCH_CHANGED"
  | "COMMAND_ID_REUSED"
  | "GAP"
  | "CONTENT_MISMATCH"
  | "CONFLICT"
  | "NOT_FOUND"
  | "HOST_UNREACHABLE"
  | "HOST_TIMEOUT"
  | "INTERNAL";

const STATUS: Record<ErrorCode, number> = {
  UPDATE_REQUIRED: 426,
  UNAUTHENTICATED: 401,
  SESSION_EXPIRED: 401,
  DEVICE_REVOKED: 401,
  FORBIDDEN: 403,
  STAFF_DISABLED: 403,
  VALIDATION: 400,
  TOO_LARGE: 413,
  RATE_LIMITED: 429,
  EPOCH_CHANGED: 409,
  COMMAND_ID_REUSED: 409,
  GAP: 409,
  CONTENT_MISMATCH: 409,
  CONFLICT: 409,
  NOT_FOUND: 404,
  HOST_UNREACHABLE: 503,
  HOST_TIMEOUT: 504,
  INTERNAL: 500,
};

/** Codes where repeating the identical request later may succeed (§4.5 retry policy). */
const RETRYABLE: ReadonlySet<ErrorCode> = new Set<ErrorCode>([
  "RATE_LIMITED",
  "HOST_UNREACHABLE",
  "HOST_TIMEOUT",
  "INTERNAL",
]);

export interface ErrorBody {
  code: ErrorCode;
  message: string;
  retryable: boolean;
  details: Record<string, unknown>;
}

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly details: Record<string, unknown>;

  constructor(code: ErrorCode, message: string, details: Record<string, unknown> = {}) {
    super(message);
    this.name = "ApiError";
    this.code = code;
    this.details = details;
  }

  get status(): number {
    return STATUS[this.code];
  }

  toBody(): ErrorBody {
    return { code: this.code, message: this.message, retryable: RETRYABLE.has(this.code), details: this.details };
  }
}

export function statusForCode(code: ErrorCode): number {
  return STATUS[code];
}

export function updateRequired(): ApiError {
  return new ApiError("UPDATE_REQUIRED", "Update CaféDesk Online on this device", {
    min: MIN_PROTOCOL_VERSION,
    max: MAX_PROTOCOL_VERSION,
  });
}

const BASE_HEADERS: Record<string, string> = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

export function jsonResponse(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...BASE_HEADERS, "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

export function errorResponse(error: ApiError): Response {
  const headers: Record<string, string> = {};
  const retryAfterMs = error.details["retryAfterMs"];
  if (error.code === "RATE_LIMITED" && typeof retryAfterMs === "number") {
    headers["Retry-After"] = String(Math.max(1, Math.ceil(retryAfterMs / 1000)));
  }
  return jsonResponse({ error: error.toBody() }, error.status, headers);
}

export function binaryHeaders(extra: Record<string, string>): Headers {
  return new Headers({ ...BASE_HEADERS, ...extra });
}
