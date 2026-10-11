// Staff session tokens: cds1.<b64url(claimsJson)>.<b64url(Ed25519 signature)>
// signed by the restaurant's host signing key (docs/PROTOCOL.md §3.2).
//
// The cloud accepts a token only if the signature verifies with the host
// signing public key registered at enrollment, rid/did match the authenticated
// device, it has not expired, its session was not revoked, its staff member is
// not disabled and still has the token's role, and it was issued in the
// restaurant's current host epoch. The role must also fit the device kind.

import { ApiError } from "../http/errors";
import { b64urlDecode } from "../protocol/canonical";
import { SESSION_MAX_LIFETIME_S, type StaffRole } from "../protocol/constants";
import { SessionClaims } from "../protocol/schemas";
import type { DeviceAuth } from "./credentials";
import { requireRoleFitsDevice } from "./permissions";

export interface StaffSession {
  readonly sessionId: string;
  readonly staffId: string;
  readonly name: string;
  readonly role: StaffRole;
  readonly epoch: number;
  /** Expiry, epoch milliseconds. */
  readonly expiresAt: number;
  /** The raw token, forwarded to the host with relayed commands and requests. */
  readonly token: string;
}

const TOKEN = /^cds1\.([A-Za-z0-9_-]{2,4096})\.([A-Za-z0-9_-]{86})$/;

// Imported public keys, keyed by their b64url text (bounded cache).
const keyCache = new Map<string, Promise<CryptoKey>>();

function importSigningKey(publicKey: string): Promise<CryptoKey> {
  let key = keyCache.get(publicKey);
  if (!key) {
    const raw = b64urlDecode(publicKey);
    if (raw === null || raw.byteLength !== 32) throw new ApiError("INTERNAL", "Stored host signing key is invalid");
    if (keyCache.size >= 256) keyCache.clear();
    key = crypto.subtle.importKey("raw", raw, { name: "Ed25519" }, false, ["verify"]);
    keyCache.set(publicKey, key);
  }
  return key;
}

function invalidToken(): ApiError {
  return new ApiError("UNAUTHENTICATED", "Missing or invalid staff session; sign in again");
}

interface SessionRow {
  signing_public_key: string;
  session_revoked: number;
  staff_role: string | null;
  staff_disabled: number | null;
}

/** Verifies `Authorization: Bearer cds1.…` for an authenticated device. */
export async function authenticateSession(
  request: Request,
  db: D1Database,
  device: DeviceAuth,
  now: number = Date.now(),
): Promise<StaffSession> {
  const header = request.headers.get("Authorization");
  const token = header?.startsWith("Bearer ") ? header.slice(7) : null;
  const match = token === null ? null : TOKEN.exec(token);
  if (token === null || !match) throw invalidToken();
  const [, claimsPart, signaturePart] = match as unknown as [string, string, string];

  const claimsBytes = b64urlDecode(claimsPart);
  const signature = b64urlDecode(signaturePart);
  if (claimsBytes === null || signature === null || signature.byteLength !== 64) throw invalidToken();
  let claimsJson: unknown;
  try {
    claimsJson = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(claimsBytes));
  } catch {
    throw invalidToken();
  }
  const parsed = SessionClaims.safeParse(claimsJson);
  if (!parsed.success) throw invalidToken();
  const claims = parsed.data;

  // One read: the restaurant's signing key plus the replicated revocation state.
  const row = await db
    .prepare(
      `SELECT hk.signing_public_key,
              EXISTS (SELECT 1 FROM revoked_sessions
                       WHERE restaurant_id = ?1 AND session_id = ?2) AS session_revoked,
              sa.role AS staff_role, sa.disabled AS staff_disabled
         FROM host_keys AS hk
         LEFT JOIN staff_access AS sa ON sa.restaurant_id = hk.restaurant_id AND sa.staff_id = ?3
        WHERE hk.restaurant_id = ?1`,
    )
    .bind(device.restaurantId, claims.sid, claims.sub)
    .first<SessionRow>();
  if (!row) throw invalidToken();

  // Signature first: nothing below is believed before it verifies.
  const key = await importSigningKey(row.signing_public_key);
  const signed = new TextEncoder().encode(`cds1.${claimsPart}`);
  const valid = await crypto.subtle.verify({ name: "Ed25519" }, key, signature, signed);
  if (!valid) throw invalidToken();

  if (claims.rid !== device.restaurantId || claims.did !== device.deviceId) throw invalidToken();
  if (claims.exp <= claims.iat || claims.exp - claims.iat > SESSION_MAX_LIFETIME_S) throw invalidToken();
  if (claims.exp * 1000 <= now) {
    throw new ApiError("SESSION_EXPIRED", "Your session has expired; sign in again");
  }
  if (row.session_revoked === 1) {
    throw new ApiError("SESSION_EXPIRED", "This session was signed out; sign in again");
  }
  if (row.staff_disabled === 1) {
    throw new ApiError("STAFF_DISABLED", "This staff account is disabled");
  }
  if (row.staff_role !== null && row.staff_role !== claims.role) {
    throw new ApiError("SESSION_EXPIRED", "Your role changed; sign in again");
  }
  if (device.currentEpoch !== null && claims.ep !== device.currentEpoch) {
    throw new ApiError("SESSION_EXPIRED", "The POS was restored; sign in again");
  }
  requireRoleFitsDevice(claims.role, device.deviceKind);

  return {
    sessionId: claims.sid,
    staffId: claims.sub,
    name: claims.name,
    role: claims.role,
    epoch: claims.ep,
    expiresAt: claims.exp * 1000,
    token,
  };
}
