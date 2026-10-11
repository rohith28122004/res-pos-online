// Size-limited request body reading (docs/PROTOCOL.md §2: larger → 413 TOO_LARGE).

import { ApiError, updateRequired } from "./errors";
import { MAX_PROTOCOL_VERSION, MIN_PROTOCOL_VERSION } from "../protocol/constants";

function tooLarge(limit: number): ApiError {
  return new ApiError("TOO_LARGE", "Request body is too large", { maxBytes: limit });
}

/**
 * Reads the whole body, refusing anything over `limit` bytes. The declared
 * Content-Length is checked first; the stream is counted as well, so a missing
 * or wrong header cannot bypass the limit.
 */
export async function readBodyBytes(request: Request, limit: number): Promise<Uint8Array> {
  const declared = request.headers.get("Content-Length");
  if (declared !== null && /^\d+$/.test(declared) && Number(declared) > limit) {
    throw tooLarge(limit);
  }
  if (request.body === null) return new Uint8Array(0);
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) {
      await reader.cancel();
      throw tooLarge(limit);
    }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

/** Reads and parses a JSON body (UTF-8, `application/json`), size-limited. */
export async function readJson(request: Request, limit: number): Promise<unknown> {
  const contentType = request.headers.get("Content-Type") ?? "";
  if (!/^application\/json\s*(;|$)/i.test(contentType)) {
    throw new ApiError("VALIDATION", "Content-Type must be application/json");
  }
  const bytes = await readBodyBytes(request, limit);
  let text: string;
  try {
    text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes);
  } catch {
    throw new ApiError("VALIDATION", "Body is not valid UTF-8");
  }
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw new ApiError("VALIDATION", "Body is not valid JSON");
  }
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * §1: a request that states an unsupported protocol version is refused with
 * 426 UPDATE_REQUIRED before anything else is looked at. `required` makes a
 * missing version a validation error (commands, events).
 */
export function checkProtocolVersion(value: unknown, required: boolean): void {
  if (value === undefined) {
    if (required) throw new ApiError("VALIDATION", "protocolVersion is required");
    return;
  }
  if (typeof value !== "number" || !Number.isSafeInteger(value)) {
    throw new ApiError("VALIDATION", "protocolVersion must be an integer");
  }
  if (value < MIN_PROTOCOL_VERSION || value > MAX_PROTOCOL_VERSION) throw updateRequired();
}
