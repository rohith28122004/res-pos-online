// Private R2 storage, always under restaurants/<authenticated restaurantId>/.
//
// * Backups: encrypted archives the host made (the cloud never sees the key),
//   restaurants/<rid>/backups/<backupId>.cdenc, SHA-256 verified on upload,
//   manifest indexed in D1, listed / downloaded only with that restaurant's
//   host credential.
// * Media (menu images): restaurants/<rid>/media/<name>, uploaded by the host,
//   downloaded by the restaurant's paired devices.
// Nothing is public: there is no public bucket, r2.dev URL or custom domain.

import type { DeviceAuth, HostAuth } from "../auth/credentials";
import { readBodyBytes } from "../http/body";
import { ApiError, binaryHeaders, jsonResponse } from "../http/errors";
import { b64urlDecode, b64urlEncode, canonicalJson, CanonicalJsonError, sha256hexBytes } from "../protocol/canonical";
import { ID_PATTERN } from "../protocol/schemas";

const MAX_MANIFEST_BYTES = 16 * 1024;

function limit(value: string, fallback: number): number {
  const n = Number(value);
  return Number.isSafeInteger(n) && n > 0 ? n : fallback;
}

function backupKey(restaurantId: string, backupId: string): string {
  return `restaurants/${restaurantId}/backups/${backupId}.cdenc`;
}

function mediaKey(restaurantId: string, name: string): string {
  return `restaurants/${restaurantId}/media/${name}`;
}

interface BackupRow {
  backup_id: string;
  r2_key: string;
  sha256: string;
  size_bytes: number;
  manifest_json: string;
  created_at: number;
}

function backupView(row: BackupRow) {
  return {
    backupId: row.backup_id,
    sha256: row.sha256,
    size: row.size_bytes,
    manifest: JSON.parse(row.manifest_json) as unknown,
    createdAt: row.created_at,
  };
}

function requireBackupId(backupId: string): void {
  if (!ID_PATTERN.test(backupId)) throw new ApiError("VALIDATION", "Invalid backup id");
}

function parseManifest(header: string | null): string {
  if (header === null) throw new ApiError("VALIDATION", "X-Manifest header is required");
  const bytes = b64urlDecode(header);
  if (bytes === null || bytes.byteLength > MAX_MANIFEST_BYTES) {
    throw new ApiError("VALIDATION", "X-Manifest must be base64url JSON of at most 16 KiB");
  }
  try {
    const manifest = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes)) as unknown;
    if (typeof manifest !== "object" || manifest === null || Array.isArray(manifest)) throw new Error("not an object");
    return canonicalJson(manifest);
  } catch (error) {
    const reason = error instanceof CanonicalJsonError ? `: ${error.message}` : "";
    throw new ApiError("VALIDATION", `X-Manifest must be a JSON object${reason}`);
  }
}

function requireSha256Header(request: Request): string {
  const value = request.headers.get("X-Content-SHA256")?.toLowerCase() ?? null;
  if (value === null || !/^[0-9a-f]{64}$/.test(value)) {
    throw new ApiError("VALIDATION", "X-Content-SHA256 must be the hex SHA-256 of the body");
  }
  return value;
}

/** PUT /v1/host/backups/{backupId} */
export async function handlePutBackup(
  request: Request,
  env: Env,
  host: HostAuth,
  backupId: string,
  now: number,
): Promise<Response> {
  requireBackupId(backupId);
  const declared = requireSha256Header(request);
  const manifestJson = parseManifest(request.headers.get("X-Manifest"));
  const rid = host.restaurantId;

  const existing = await env.DB.prepare("SELECT * FROM backups WHERE restaurant_id = ?1 AND backup_id = ?2")
    .bind(rid, backupId)
    .first<BackupRow>();
  if (existing) {
    if (existing.sha256 !== declared) {
      throw new ApiError("CONTENT_MISMATCH", "A different archive was already stored under this backup id", {
        backupId,
      });
    }
    return jsonResponse({ backup: backupView(existing), created: false });
  }

  const body = await readBodyBytes(request, limit(env.MAX_BACKUP_BYTES, 50 * 1024 * 1024));
  if (body.byteLength === 0) throw new ApiError("VALIDATION", "The archive is empty");
  const actual = await sha256hexBytes(body);
  if (actual !== declared) {
    throw new ApiError("VALIDATION", "The body does not match X-Content-SHA256; nothing was stored", {
      expected: declared,
      actual,
    });
  }
  const key = backupKey(rid, backupId);
  // R2 checks the SHA-256 again on its side.
  await env.BUCKET.put(key, body, {
    sha256: actual,
    httpMetadata: { contentType: "application/octet-stream" },
    customMetadata: { backupId },
  });
  await env.DB.prepare(
    `INSERT INTO backups (restaurant_id, backup_id, r2_key, sha256, size_bytes, manifest_json, created_at)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7) ON CONFLICT (restaurant_id, backup_id) DO NOTHING`,
  )
    .bind(rid, backupId, key, actual, body.byteLength, manifestJson, now)
    .run();
  const row = await env.DB.prepare("SELECT * FROM backups WHERE restaurant_id = ?1 AND backup_id = ?2")
    .bind(rid, backupId)
    .first<BackupRow>();
  if (!row || row.sha256 !== actual) {
    throw new ApiError("CONTENT_MISMATCH", "A different archive was stored under this backup id concurrently");
  }
  return jsonResponse({ backup: backupView(row), created: true }, 201);
}

/** GET /v1/host/backups */
export async function handleListBackups(env: Env, host: HostAuth): Promise<Response> {
  const rows = await env.DB.prepare("SELECT * FROM backups WHERE restaurant_id = ?1 ORDER BY created_at DESC, backup_id")
    .bind(host.restaurantId)
    .all<BackupRow>();
  return jsonResponse({ backups: rows.results.map(backupView) });
}

/** GET /v1/host/backups/{backupId} */
export async function handleGetBackup(env: Env, host: HostAuth, backupId: string): Promise<Response> {
  requireBackupId(backupId);
  const row = await env.DB.prepare("SELECT * FROM backups WHERE restaurant_id = ?1 AND backup_id = ?2")
    .bind(host.restaurantId, backupId)
    .first<BackupRow>();
  const object = row ? await env.BUCKET.get(row.r2_key) : null;
  if (!row || !object) throw new ApiError("NOT_FOUND", "No such backup", { backupId });
  return new Response(object.body, {
    headers: binaryHeaders({
      "Content-Type": "application/octet-stream",
      "Content-Length": String(object.size),
      "Content-Disposition": `attachment; filename="${backupId}.cdenc"`,
      "X-Content-SHA256": row.sha256,
      "X-Manifest": b64urlEncode(new TextEncoder().encode(row.manifest_json)),
    }),
  });
}

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

const MEDIA_NAME = /^[A-Za-z0-9_-]{1,64}\.(jpg|jpeg|png|webp)$/;
const MEDIA_TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  webp: "image/webp",
};

function mediaType(name: string): string {
  const match = MEDIA_NAME.exec(name);
  if (!match) throw new ApiError("VALIDATION", "Media names are <id>.jpg|jpeg|png|webp");
  return MEDIA_TYPES[match[1]!]!;
}

/** PUT /v1/host/media/{name} */
export async function handlePutMedia(request: Request, env: Env, host: HostAuth, name: string): Promise<Response> {
  const contentType = mediaType(name);
  const sent = request.headers.get("Content-Type")?.split(";")[0]?.trim().toLowerCase();
  if (sent !== contentType) throw new ApiError("VALIDATION", `Content-Type must be ${contentType}`);
  const body = await readBodyBytes(request, limit(env.MAX_MEDIA_BYTES, 5 * 1024 * 1024));
  if (body.byteLength === 0) throw new ApiError("VALIDATION", "The file is empty");
  const sha256 = await sha256hexBytes(body);
  const declared = request.headers.get("X-Content-SHA256");
  if (declared !== null && declared.toLowerCase() !== sha256) {
    throw new ApiError("VALIDATION", "The body does not match X-Content-SHA256; nothing was stored", {
      expected: declared.toLowerCase(),
      actual: sha256,
    });
  }
  await env.BUCKET.put(mediaKey(host.restaurantId, name), body, { sha256, httpMetadata: { contentType } });
  return jsonResponse({ name, size: body.byteLength, sha256, contentType }, 201);
}

/** GET /v1/host/media */
export async function handleListMedia(env: Env, host: HostAuth): Promise<Response> {
  const prefix = mediaKey(host.restaurantId, "");
  const media: Array<{ name: string; size: number; uploadedAt: number }> = [];
  let cursor: string | undefined;
  do {
    const page = await env.BUCKET.list({ prefix, cursor, limit: 1000 });
    for (const object of page.objects) {
      media.push({ name: object.key.slice(prefix.length), size: object.size, uploadedAt: object.uploaded.getTime() });
    }
    cursor = page.truncated ? page.cursor : undefined;
  } while (cursor !== undefined);
  return jsonResponse({ media });
}

/** DELETE /v1/host/media/{name} */
export async function handleDeleteMedia(env: Env, host: HostAuth, name: string): Promise<Response> {
  mediaType(name);
  await env.BUCKET.delete(mediaKey(host.restaurantId, name));
  return jsonResponse({ ok: true });
}

/** GET /v1/device/media/{name} (and the host's own GET /v1/host/media/{name}). */
export async function handleGetMedia(env: Env, auth: HostAuth | DeviceAuth, name: string): Promise<Response> {
  const contentType = mediaType(name);
  const object = await env.BUCKET.get(mediaKey(auth.restaurantId, name));
  if (!object) throw new ApiError("NOT_FOUND", "No such media", { name });
  return new Response(object.body, {
    headers: binaryHeaders({
      "Content-Type": contentType,
      "Content-Length": String(object.size),
      "Cache-Control": "private, max-age=300",
      ETag: object.httpEtag,
    }),
  });
}
