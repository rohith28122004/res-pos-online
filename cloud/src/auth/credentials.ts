// Host and device credential authentication (docs/PROTOCOL.md §3, §8).
//
// Credentials are bearer secrets; the cloud stores only sha256hex(credential).
// The restaurant is always taken from the matching credential row — never from
// the request.

import { ApiError } from "../http/errors";
import { sha256hex } from "../protocol/canonical";
import type { DeviceKind } from "../protocol/constants";

export interface HostAuth {
  readonly kind: "host";
  readonly restaurantId: string;
  readonly hostDeviceId: string;
  readonly credentialHash: string;
  readonly currentEpoch: number | null;
}

export interface DeviceAuth {
  readonly kind: "device";
  readonly restaurantId: string;
  readonly deviceId: string;
  readonly deviceKind: DeviceKind;
  readonly credentialHash: string;
  readonly currentEpoch: number | null;
}

const SECRET = "[A-Za-z0-9_-]{43}"; // 32 bytes, b64url without padding
const ID = "[A-Za-z0-9_-]{1,64}";
const HOST_CREDENTIAL = new RegExp(`^cdh1\\.(${ID})\\.(${ID})\\.(${SECRET})$`);
const DEVICE_CREDENTIAL = new RegExp(`^cdd1\\.(${ID})\\.(${SECRET})$`);

function unauthenticated(message = "Missing or invalid credential"): ApiError {
  return new ApiError("UNAUTHENTICATED", message);
}

/** The value of `Authorization: Bearer <value>`, or null. */
export function bearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (header === null) return null;
  const match = /^Bearer ([\x21-\x7e]{1,4096})$/.exec(header);
  return match?.[1] ?? null;
}

export function isHostBearer(request: Request): boolean {
  return bearerToken(request)?.startsWith("cdh1.") ?? false;
}

export function formatHostCredential(restaurantId: string, hostDeviceId: string, secret: string): string {
  return `cdh1.${restaurantId}.${hostDeviceId}.${secret}`;
}

interface HostRow {
  restaurant_id: string;
  subject_id: string;
  revoked_at: number | null;
  current_epoch: number | null;
}

/** `Authorization: Bearer cdh1.<restaurantId>.<hostDeviceId>.<secret>`. */
export async function authenticateHost(request: Request, db: D1Database): Promise<HostAuth> {
  const token = bearerToken(request);
  const match = token === null ? null : HOST_CREDENTIAL.exec(token);
  if (token === null || !match) throw unauthenticated();
  const credentialHash = await sha256hex(token);
  const row = await db
    .prepare(
      `SELECT c.restaurant_id, c.subject_id, c.revoked_at, r.current_epoch
         FROM credentials AS c JOIN restaurants AS r ON r.id = c.restaurant_id
        WHERE c.credential_hash = ?1 AND c.kind = 'host'`,
    )
    .bind(credentialHash)
    .first<HostRow>();
  // The IDs inside the credential are only compared with the stored row.
  if (!row || row.restaurant_id !== match[1] || row.subject_id !== match[2]) throw unauthenticated();
  if (row.revoked_at !== null) throw unauthenticated("Host credential was rotated or revoked");
  return {
    kind: "host",
    restaurantId: row.restaurant_id,
    hostDeviceId: row.subject_id,
    credentialHash,
    currentEpoch: row.current_epoch,
  };
}

interface DeviceRow {
  restaurant_id: string;
  subject_id: string;
  credential_revoked_at: number | null;
  device_revoked_at: number | null;
  role: DeviceKind;
  current_epoch: number | null;
}

/** `X-CafeDesk-Device: cdd1.<deviceId>.<secret>`. */
export async function authenticateDevice(request: Request, db: D1Database): Promise<DeviceAuth> {
  const credential = request.headers.get("X-CafeDesk-Device");
  const match = credential === null ? null : DEVICE_CREDENTIAL.exec(credential);
  if (credential === null || !match) throw unauthenticated();
  const credentialHash = await sha256hex(credential);
  const row = await db
    .prepare(
      `SELECT c.restaurant_id, c.subject_id, c.revoked_at AS credential_revoked_at,
              d.revoked_at AS device_revoked_at, d.role, r.current_epoch
         FROM credentials AS c
         JOIN devices AS d ON d.restaurant_id = c.restaurant_id AND d.device_id = c.subject_id
         JOIN restaurants AS r ON r.id = c.restaurant_id
        WHERE c.credential_hash = ?1 AND c.kind = 'device'`,
    )
    .bind(credentialHash)
    .first<DeviceRow>();
  if (!row || row.subject_id !== match[1]) throw unauthenticated();
  if (row.credential_revoked_at !== null || row.device_revoked_at !== null) {
    throw new ApiError("DEVICE_REVOKED", "This device was unpaired; pair it again");
  }
  return {
    kind: "device",
    restaurantId: row.restaurant_id,
    deviceId: row.subject_id,
    deviceKind: row.role,
    credentialHash,
    currentEpoch: row.current_epoch,
  };
}
