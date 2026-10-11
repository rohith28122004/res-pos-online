// POST /v1/enroll — consume a single-use operator enrollment code, create the
// restaurant under the ID the host created locally, register the host's public
// keys and issue the host credential.
//
// The host proposes restaurantId (it pairs LAN devices before ever reaching
// the cloud). Enroll only ever creates a NEW restaurant: an ID that already
// exists is refused with 409 CONFLICT, so enrollment can never attach a second
// host to an existing restaurant.

import { formatHostCredential } from "../auth/credentials";
import { checkProtocolVersion, isPlainObject, readJson } from "../http/body";
import { ApiError, jsonResponse } from "../http/errors";
import { clientAddress, hitRateLimit } from "../http/rate_limit";
import { b64urlDecode, randomSecret, sha256hex } from "../protocol/canonical";
import { ENROLL_RATE_LIMIT, ENROLL_RATE_WINDOW_MS, MAX_REQUEST_BYTES } from "../protocol/constants";
import { hashEnrollmentCode, normalizeEnrollmentCode } from "../protocol/enrollment_code";
import { EnrollRequest, parseOrThrow } from "../protocol/schemas";

function invalidCode(): ApiError {
  // One message for unknown, used and expired codes: no oracle for guessing.
  return new ApiError("UNAUTHENTICATED", "Enrollment code is invalid, already used or expired");
}

function alreadyEnrolled(restaurantId: string): ApiError {
  return new ApiError("CONFLICT", "This restaurant is already enrolled", { restaurantId });
}

export async function handleEnroll(request: Request, env: Env, now: number): Promise<Response> {
  await hitRateLimit(env.DB, `enroll:${clientAddress(request)}`, ENROLL_RATE_LIMIT, ENROLL_RATE_WINDOW_MS, now);
  const body = await readJson(request, MAX_REQUEST_BYTES);
  if (isPlainObject(body)) checkProtocolVersion(body["protocolVersion"], false);
  const input = parseOrThrow(EnrollRequest, body, "enrollment request");

  const normalized = normalizeEnrollmentCode(input.enrollmentCode);
  if (normalized === null) throw invalidCode();
  try {
    await crypto.subtle.importKey("raw", b64urlDecode(input.hostSigningPublicKey)!, { name: "Ed25519" }, false, [
      "verify",
    ]);
  } catch {
    throw new ApiError("VALIDATION", "hostSigningPublicKey is not a valid Ed25519 public key");
  }

  const codeHash = await hashEnrollmentCode(normalized);
  const restaurantId = input.restaurantId;
  const hostCredential = formatHostCredential(restaurantId, input.hostDeviceId, randomSecret());
  const credentialHash = await sha256hex(hostCredential);

  // One transaction: the code is consumed only together with everything it
  // creates, and only when no restaurant with this ID exists yet.
  let created = false;
  try {
    const results = await env.DB.batch([
      env.DB.prepare(
        `UPDATE enrollment_codes SET used_at = ?3, restaurant_id = ?2
          WHERE code_hash = ?1 AND used_at IS NULL AND expires_at > ?3
            AND NOT EXISTS (SELECT 1 FROM restaurants WHERE id = ?2)`,
      ).bind(codeHash, restaurantId, now),
      env.DB.prepare(
        `INSERT INTO restaurants (id, name, host_device_id, app_version, created_at)
         SELECT ?1, ?2, ?3, ?4, ?5
          WHERE EXISTS (SELECT 1 FROM enrollment_codes
                         WHERE code_hash = ?6 AND restaurant_id = ?1 AND used_at = ?5)`,
      ).bind(restaurantId, input.restaurantName, input.hostDeviceId, input.appVersion, now, codeHash),
      env.DB.prepare(
        `INSERT INTO host_keys (restaurant_id, host_device_id, signing_public_key, seal_public_key, created_at)
         SELECT ?1, ?2, ?3, ?4, ?5
          WHERE changes() = 1 AND EXISTS (SELECT 1 FROM restaurants WHERE id = ?1)`,
      ).bind(restaurantId, input.hostDeviceId, input.hostSigningPublicKey, input.hostSealPublicKey, now),
      env.DB.prepare(
        `INSERT INTO credentials (credential_hash, kind, restaurant_id, subject_id, created_at)
         SELECT ?1, 'host', ?2, ?3, ?4
          WHERE changes() = 1 AND EXISTS (SELECT 1 FROM restaurants WHERE id = ?2)`,
      ).bind(credentialHash, restaurantId, input.hostDeviceId, now),
    ]);
    created = results[1]?.meta.changes === 1 && results[3]?.meta.changes === 1;
  } catch (error) {
    // Two enrollments racing for the same restaurant ID: the loser rolls back
    // completely (its code stays unused).
    if (error instanceof Error && /UNIQUE|PRIMARY KEY/i.test(error.message)) throw alreadyEnrolled(restaurantId);
    throw error;
  }

  if (!created) {
    // Only a caller holding a valid code learns that the restaurant exists.
    const [code, restaurant] = await env.DB.batch([
      env.DB.prepare(
        "SELECT 1 AS ok FROM enrollment_codes WHERE code_hash = ?1 AND used_at IS NULL AND expires_at > ?2",
      ).bind(codeHash, now),
      env.DB.prepare("SELECT 1 AS ok FROM restaurants WHERE id = ?1").bind(restaurantId),
    ]);
    if ((code?.results.length ?? 0) > 0 && (restaurant?.results.length ?? 0) > 0) throw alreadyEnrolled(restaurantId);
    throw invalidCode();
  }

  // The secret appears here once; the cloud keeps only its hash.
  return jsonResponse({ restaurantId, hostCredential }, 201);
}
