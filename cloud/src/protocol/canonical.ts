// Canonical JSON and hashing (docs/PROTOCOL.md §2).
//
//  * object keys sorted by UTF-16 code unit order (Array.prototype.sort default,
//    identical to Dart's String.compareTo)
//  * no insignificant whitespace
//  * strings escaped exactly as JSON.stringify / Dart jsonEncode do
//    (non-ASCII is NOT escaped)
//  * integers only (safe integers, |n| <= 2^53 - 1); lone surrogates invalid
//
// The shared vectors in protocol/vectors/canonical_hash.json pin this down for
// both the TypeScript and the Dart implementation.

export class CanonicalJsonError extends Error {
  readonly path: string;

  constructor(message: string, path: string) {
    super(`${message} at ${path}`);
    this.name = "CanonicalJsonError";
    this.path = path;
  }
}

// A lead surrogate not followed by a trail, or a trail not preceded by a lead.
const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;

function checkString(value: string, path: string): void {
  if (LONE_SURROGATE.test(value)) {
    throw new CanonicalJsonError("Lone surrogate in string", path);
  }
}

function write(value: unknown, path: string, out: string[]): void {
  if (value === null) {
    out.push("null");
    return;
  }
  switch (typeof value) {
    case "boolean":
      out.push(value ? "true" : "false");
      return;
    case "number":
      if (!Number.isSafeInteger(value)) {
        throw new CanonicalJsonError("Only safe integers are allowed", path);
      }
      // String(-0) is "0", matching Dart's int encoding.
      out.push(String(value));
      return;
    case "string":
      checkString(value, path);
      out.push(JSON.stringify(value));
      return;
    case "object": {
      if (Array.isArray(value)) {
        out.push("[");
        for (let i = 0; i < value.length; i++) {
          if (i > 0) out.push(",");
          write(value[i], `${path}[${i}]`, out);
        }
        out.push("]");
        return;
      }
      const proto = Object.getPrototypeOf(value);
      if (proto !== Object.prototype && proto !== null) {
        throw new CanonicalJsonError("Only plain objects are allowed", path);
      }
      const record = value as Record<string, unknown>;
      const keys = Object.keys(record).sort();
      out.push("{");
      keys.forEach((key, i) => {
        checkString(key, `${path}.<key>`);
        if (i > 0) out.push(",");
        out.push(JSON.stringify(key), ":");
        write(record[key], `${path}.${key}`, out);
      });
      out.push("}");
      return;
    }
    default:
      throw new CanonicalJsonError(`Unsupported value of type ${typeof value}`, path);
  }
}

/** Canonical JSON text of a JSON value (see the module comment). */
export function canonicalJson(value: unknown): string {
  const out: string[] = [];
  write(value, "$", out);
  return out.join("");
}

const HEX = Array.from({ length: 256 }, (_, i) => i.toString(16).padStart(2, "0"));

export function bytesToHex(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let hex = "";
  for (const byte of view) hex += HEX[byte];
  return hex;
}

/** Lower-case hex SHA-256 of the UTF-8 bytes of `text`. */
export async function sha256hex(text: string): Promise<string> {
  return sha256hexBytes(new TextEncoder().encode(text));
}

export async function sha256hexBytes(bytes: ArrayBuffer | Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return bytesToHex(digest);
}

/** sha256hex(canonicalJson(value)) — bodyHash of commands, contentHash of events. */
export async function canonicalHash(value: unknown): Promise<string> {
  return sha256hex(canonicalJson(value));
}

/** base64url without padding. */
export function b64urlEncode(bytes: ArrayBuffer | Uint8Array): string {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let binary = "";
  for (const byte of view) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const B64URL = /^[A-Za-z0-9_-]*$/;

/** Decodes unpadded base64url; returns null for malformed input. */
export function b64urlDecode(text: string): Uint8Array | null {
  if (!B64URL.test(text) || text.length % 4 === 1) return null;
  const base64 = text.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((text.length + 3) % 4);
  try {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    // Reject non-canonical encodings (stray bits in the last character).
    if (b64urlEncode(bytes) !== text) return null;
    return bytes;
  } catch {
    return null;
  }
}

/** 32 bytes from the CSPRNG, b64url encoded (the `<secret>` of credentials). */
export function randomSecret(): string {
  return b64urlEncode(crypto.getRandomValues(new Uint8Array(32)));
}
