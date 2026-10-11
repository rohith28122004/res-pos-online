// Host routes (docs/PROTOCOL.md §8): credential rotation, sync state, epochs,
// event ingest and the relay socket. Every handler receives an authenticated
// HostAuth; the restaurant comes from the credential row only.

import { formatHostCredential, type HostAuth } from "../auth/credentials";
import { readJson } from "../http/body";
import { ApiError, jsonResponse } from "../http/errors";
import { ingestEvents } from "../ingest/ingest";
import { randomSecret, sha256hex } from "../protocol/canonical";
import { MAX_EVENT_BATCH_BYTES, MAX_REQUEST_BYTES } from "../protocol/constants";
import { OpenEpochRequest, parseOrThrow } from "../protocol/schemas";
import { HUB_IDENTITY_HEADER, type HostIdentity, type RestaurantHub } from "../restaurant_hub/hub";

/**
 * The RPC surface of a restaurant's hub. Everything these methods exchange is
 * structured-cloneable JSON data; the explicit type avoids the generic RPC
 * mapping turning `unknown` JSON payloads into `never`.
 */
export type HubStub = Pick<
  RestaurantHub,
  "submitCommand" | "getCommand" | "relayRequest" | "epochOpened" | "eventsCommitted" | "hostCredentialRotated" | "hostConnected"
> & { fetch(input: string, init?: RequestInit): Promise<Response> };

export function hubFor(env: Env, restaurantId: string): HubStub {
  return env.HUB.get(env.HUB.idFromName(restaurantId)) as unknown as HubStub;
}

interface EpochRow {
  epoch: number;
  start_sequence: number;
  next_sequence: number;
}

async function syncState(db: D1Database, restaurantId: string) {
  const [restaurant, epochs] = await db.batch<Record<string, unknown>>([
    db.prepare("SELECT current_epoch FROM restaurants WHERE id = ?1").bind(restaurantId),
    db
      .prepare("SELECT epoch, start_sequence, next_sequence FROM epochs WHERE restaurant_id = ?1 ORDER BY epoch")
      .bind(restaurantId),
  ]);
  return {
    currentEpoch: (restaurant?.results[0]?.["current_epoch"] as number | null | undefined) ?? null,
    epochs: ((epochs?.results ?? []) as unknown as EpochRow[]).map((e) => ({
      epoch: e.epoch,
      startSequence: e.start_sequence,
      nextSequence: e.next_sequence,
    })),
  };
}

/** GET /v1/host/sync-state */
export async function handleSyncState(env: Env, host: HostAuth): Promise<Response> {
  return jsonResponse(await syncState(env.DB, host.restaurantId));
}

/** POST /v1/host/credential/rotate — the presented credential stops working. */
export async function handleRotateCredential(env: Env, host: HostAuth, now: number): Promise<Response> {
  const hostCredential = formatHostCredential(host.restaurantId, host.hostDeviceId, randomSecret());
  const newHash = await sha256hex(hostCredential);
  const results = await env.DB.batch([
    env.DB.prepare(
      "UPDATE credentials SET revoked_at = ?2 WHERE credential_hash = ?1 AND kind = 'host' AND revoked_at IS NULL",
    ).bind(host.credentialHash, now),
    // Only if this request revoked the old credential (no double rotation).
    env.DB.prepare(
      `INSERT INTO credentials (credential_hash, kind, restaurant_id, subject_id, created_at)
       SELECT ?1, 'host', ?2, ?3, ?4 WHERE changes() = 1`,
    ).bind(newHash, host.restaurantId, host.hostDeviceId, now),
  ]);
  if (results[1]?.meta.changes !== 1) throw new ApiError("UNAUTHENTICATED", "Host credential was already rotated");
  await hubFor(env, host.restaurantId).hostCredentialRotated(host.restaurantId, host.credentialHash);
  return jsonResponse({ hostCredential });
}

/** POST /v1/host/epoch — open a new epoch after a restore; older queued commands are quarantined. */
export async function handleOpenEpoch(request: Request, env: Env, host: HostAuth, now: number): Promise<Response> {
  const input = parseOrThrow(OpenEpochRequest, await readJson(request, MAX_REQUEST_BYTES), "epoch request");
  const rid = host.restaurantId;
  for (let attempt = 1; ; attempt++) {
    const [restaurant, existing] = await env.DB.batch<Record<string, unknown>>([
      env.DB.prepare("SELECT current_epoch FROM restaurants WHERE id = ?1").bind(rid),
      env.DB.prepare("SELECT start_sequence FROM epochs WHERE restaurant_id = ?1 AND epoch = ?2").bind(rid, input.epoch),
    ]);
    const current = (restaurant?.results[0]?.["current_epoch"] as number | null | undefined) ?? null;
    const existingStart = existing?.results[0]?.["start_sequence"] as number | undefined;
    if (existingStart !== undefined) {
      if (existingStart !== input.startSequence || input.epoch !== current) {
        throw new ApiError("EPOCH_CHANGED", `Epoch ${input.epoch} is already open with another start`, {
          currentEpoch: current,
          startSequence: existingStart,
        });
      }
      break; // the same request again: idempotent
    }
    if (current !== null && input.epoch < current) {
      throw new ApiError("EPOCH_CHANGED", "The cloud already has a newer epoch", { currentEpoch: current });
    }
    try {
      await env.DB.batch([
        env.DB.prepare(
          `INSERT INTO epochs (restaurant_id, epoch, start_sequence, next_sequence, opened_at, reason)
           VALUES (?1, ?2, ?3, ?3, ?4, ?5)`,
        ).bind(rid, input.epoch, input.startSequence, now, input.reason),
        env.DB.prepare(
          `UPDATE restaurants SET current_epoch = ?2
            WHERE id = ?1 AND (current_epoch IS NULL OR current_epoch < ?2)`,
        ).bind(rid, input.epoch),
      ]);
      break;
    } catch (error) {
      if (attempt < 3 && error instanceof Error && /UNIQUE|PRIMARY KEY/i.test(error.message)) continue;
      throw error;
    }
  }
  const quarantined = await hubFor(env, rid).epochOpened(rid, input.epoch);
  return jsonResponse({ ...(await syncState(env.DB, rid)), quarantinedCommands: quarantined });
}

/** POST /v1/host/events */
export async function handleEvents(request: Request, env: Env, host: HostAuth, now: number): Promise<Response> {
  const body = await readJson(request, MAX_EVENT_BATCH_BYTES);
  const outcome = await ingestEvents(env.DB, host, body, now);
  const notify = outcome.notify;
  if (notify) {
    // The batch is committed; telling sockets is best effort (devices also poll).
    try {
      const hub = hubFor(env, host.restaurantId);
      if (notify.epochOpened !== null) await hub.epochOpened(host.restaurantId, notify.epochOpened);
      await hub.eventsCommitted({
        restaurantId: host.restaurantId,
        hostEpoch: notify.hostEpoch,
        latestSequence: notify.latestSequence,
        notifyDevices: notify.deviceAudience,
        revokedDevices: notify.revokedDevices,
        revokedSessions: notify.revokedSessions,
        staffChanged: notify.staffChanged,
      });
    } catch (error) {
      console.error("Hub notification after ingest failed", error instanceof Error ? error.message : "unknown");
    }
  }
  return jsonResponse({
    ackedThrough: outcome.ackedThrough,
    appended: outcome.appended,
    duplicates: outcome.duplicates,
  });
}

export function requireWebSocketUpgrade(request: Request): void {
  if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
    throw new ApiError("VALIDATION", "Expected a WebSocket upgrade request");
  }
}

/** GET /v1/host/socket */
export async function handleHostSocket(request: Request, env: Env, host: HostAuth, now: number): Promise<Response> {
  requireWebSocketUpgrade(request);
  const identity: HostIdentity = {
    kind: "host",
    restaurantId: host.restaurantId,
    hostDeviceId: host.hostDeviceId,
    credentialHash: host.credentialHash,
    connectedAt: now,
  };
  return hubFor(env, host.restaurantId).fetch("https://hub.internal/socket", {
    headers: { Upgrade: "websocket", [HUB_IDENTITY_HEADER]: JSON.stringify(identity) },
  });
}
