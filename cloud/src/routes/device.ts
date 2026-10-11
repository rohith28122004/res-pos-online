// Device routes (docs/PROTOCOL.md §8): relayed requests, commands through the
// mailbox, command status, events from the ledger and the notification socket.

import type { DeviceAuth } from "../auth/credentials";
import { requireActionAllowed, requireSnapshotScope } from "../auth/permissions";
import { authenticateSession, type StaffSession } from "../auth/session";
import { checkProtocolVersion, isPlainObject, readJson } from "../http/body";
import { ApiError, jsonResponse, updateRequired } from "../http/errors";
import { CanonicalJsonError, canonicalHash } from "../protocol/canonical";
import { DEVICE_AUDIENCE_EVENT_TYPES, MAX_REQUEST_BYTES } from "../protocol/constants";
import {
  CommandEnvelope,
  ID_PATTERN,
  RELAY_BODIES,
  RelayRequest,
  checkLineCount,
  isKnownAction,
  parseOrThrow,
  validateCommandAction,
} from "../protocol/schemas";
import { HUB_IDENTITY_HEADER, type DeviceIdentity, type HubError } from "../restaurant_hub/hub";
import { hubFor, requireWebSocketUpgrade } from "./host";

function hubError(error: HubError): ApiError {
  return new ApiError(error.code, error.message, error.details);
}

/** POST /v1/device/requests — sealed_auth (device only), snapshot / command_lookup (device + session). */
export async function handleDeviceRequest(request: Request, env: Env, device: DeviceAuth): Promise<Response> {
  const body = await readJson(request, MAX_REQUEST_BYTES);
  if (isPlainObject(body)) checkProtocolVersion(body["protocolVersion"], false);
  const input = parseOrThrow(RelayRequest, body, "device request");
  let session: StaffSession | null = null;
  if (input.kind === "sealed_auth") {
    parseOrThrow(RELAY_BODIES.sealed_auth, input.body, "sealed_auth body");
  } else {
    session = await authenticateSession(request, env.DB, device);
    if (input.kind === "snapshot") {
      requireSnapshotScope(session.role, parseOrThrow(RELAY_BODIES.snapshot, input.body, "snapshot body").scope);
    } else {
      parseOrThrow(RELAY_BODIES.command_lookup, input.body, "command_lookup body");
    }
  }
  const outcome = await hubFor(env, device.restaurantId).relayRequest({
    restaurantId: device.restaurantId,
    kind: input.kind,
    deviceId: device.deviceId,
    sessionToken: session?.token ?? null,
    body: input.body,
  });
  if (!outcome.ok) throw hubError(outcome.error);
  if (outcome.status === 204 || outcome.status === 205 || outcome.status === 304) {
    return new Response(null, { status: outcome.status, headers: { "Cache-Control": "no-store" } });
  }
  return jsonResponse(outcome.body ?? null, outcome.status);
}

/** POST /v1/device/commands — into the restaurant's mailbox; waits ≤ 8 s for the host. */
export async function handleSubmitCommand(request: Request, env: Env, device: DeviceAuth): Promise<Response> {
  const session = await authenticateSession(request, env.DB, device);
  const raw = await readJson(request, MAX_REQUEST_BYTES);
  if (!isPlainObject(raw)) throw new ApiError("VALIDATION", "Body must be a JSON object");
  checkProtocolVersion(raw["protocolVersion"], true);
  checkLineCount(raw["payload"]);
  const command = parseOrThrow(CommandEnvelope, raw, "command");
  // An action this cloud does not know cannot be checked against roles.
  if (!isKnownAction(command.action)) throw updateRequired();
  const action = command.action;
  validateCommandAction({ ...command, action });

  // Identity fields bind the command; they are compared, never trusted (§4.1).
  if (
    command.restaurantId !== device.restaurantId ||
    command.deviceId !== device.deviceId ||
    command.staffId !== session.staffId
  ) {
    throw new ApiError("FORBIDDEN", "restaurantId, deviceId and staffId must match this device and session");
  }
  requireActionAllowed(session.role, action);

  let bodyHash: string;
  try {
    bodyHash = await canonicalHash(raw);
  } catch (error) {
    if (error instanceof CanonicalJsonError) throw new ApiError("VALIDATION", error.message);
    throw error;
  }
  const outcome = await hubFor(env, device.restaurantId).submitCommand({
    restaurantId: device.restaurantId,
    commandId: command.commandId,
    command: raw,
    bodyHash,
    hostEpoch: command.hostEpoch,
    deviceId: device.deviceId,
    staffId: session.staffId,
    sessionToken: session.token,
    cloudEpoch: device.currentEpoch,
  });
  if (!outcome.ok) throw hubError(outcome.error);
  const entry = outcome.entry;
  return jsonResponse({
    commandId: entry.commandId,
    mailboxState: entry.mailboxState,
    receivedAt: entry.receivedAt,
    ...(entry.result ? { result: entry.result } : {}),
  });
}

/** GET /v1/device/commands/{commandId} — own commands only. */
export async function handleGetCommand(
  request: Request,
  env: Env,
  device: DeviceAuth,
  commandId: string,
): Promise<Response> {
  await authenticateSession(request, env.DB, device);
  if (!ID_PATTERN.test(commandId)) throw new ApiError("VALIDATION", "Invalid command id");
  const entry = await hubFor(env, device.restaurantId).getCommand(device.restaurantId, device.deviceId, commandId);
  if (entry === null) throw new ApiError("NOT_FOUND", "No such command from this device", { commandId });
  return jsonResponse(entry);
}

function intParam(url: URL, name: string, fallback: number | null, min: number, max: number): number {
  const raw = url.searchParams.get(name);
  if (raw === null) {
    if (fallback === null) throw new ApiError("VALIDATION", `Query parameter ${name} is required`);
    return fallback;
  }
  if (!/^\d{1,16}$/.test(raw) || !Number.isSafeInteger(Number(raw)) || Number(raw) < min || Number(raw) > max) {
    throw new ApiError("VALIDATION", `Query parameter ${name} must be an integer between ${min} and ${max}`);
  }
  return Number(raw);
}

const AUDIENCE_SQL = DEVICE_AUDIENCE_EVENT_TYPES.map((t) => `'${t}'`).join(", ");

/**
 * GET /v1/device/events?epoch=&after=&limit= — device-audience events from the
 * ledger, in the same page shape as the host's LAN `GET /v1/events`:
 * `{hostEpoch, events, through, latestSequence, snapshotRequired}`.
 *
 * Cloud-only events (bills, refunds, …) are not returned, so the sequences in
 * `events` can skip numbers. `through` is the cursor the device may advance to:
 * the latest ingested sequence when the page is complete, otherwise the last
 * returned event. A cursor ahead of the cloud (the host has events the cloud
 * has not ingested yet) gets an empty page with `through = after`.
 */
export async function handleDeviceEvents(request: Request, env: Env, device: DeviceAuth): Promise<Response> {
  await authenticateSession(request, env.DB, device);
  const url = new URL(request.url);
  const epoch = intParam(url, "epoch", null, 1, Number.MAX_SAFE_INTEGER);
  const after = intParam(url, "after", null, 0, Number.MAX_SAFE_INTEGER);
  const limit = intParam(url, "limit", 200, 1, 500);

  const state = await env.DB.prepare(
    `SELECT r.current_epoch, e.start_sequence, e.next_sequence
       FROM restaurants AS r LEFT JOIN epochs AS e ON e.restaurant_id = r.id AND e.epoch = r.current_epoch
      WHERE r.id = ?1`,
  )
    .bind(device.restaurantId)
    .first<{ current_epoch: number | null; start_sequence: number | null; next_sequence: number | null }>();
  const current = state?.current_epoch ?? null;
  const latestSequence = state?.next_sequence != null ? state.next_sequence - 1 : 0;
  const page = (events: unknown[], through: number, snapshotRequired: boolean) =>
    jsonResponse({ hostEpoch: current, events, through, latestSequence, snapshotRequired });

  // A cursor from another epoch, or from before what the cloud has, needs a fresh snapshot.
  if (current === null || epoch !== current || after < (state?.start_sequence ?? 1) - 1) {
    return page([], latestSequence, true);
  }
  if (after >= latestSequence) return page([], after, false);

  const rows = await env.DB.prepare(
    `SELECT sequence, event_json FROM events
      WHERE restaurant_id = ?1 AND host_epoch = ?2 AND sequence > ?3 AND type IN (${AUDIENCE_SQL})
      ORDER BY sequence LIMIT ?4`,
  )
    .bind(device.restaurantId, epoch, after, limit)
    .all<{ sequence: number; event_json: string }>();
  const complete = rows.results.length < limit;
  const through = complete ? latestSequence : rows.results[rows.results.length - 1]!.sequence;
  return page(
    rows.results.map((r) => JSON.parse(r.event_json) as unknown),
    through,
    false,
  );
}

/** GET /v1/device/socket */
export async function handleDeviceSocket(request: Request, env: Env, device: DeviceAuth): Promise<Response> {
  requireWebSocketUpgrade(request);
  const session = await authenticateSession(request, env.DB, device);
  const identity: DeviceIdentity = {
    kind: "device",
    restaurantId: device.restaurantId,
    deviceId: device.deviceId,
    staffId: session.staffId,
    sessionId: session.sessionId,
    role: session.role,
    expiresAt: session.expiresAt,
  };
  return hubFor(env, device.restaurantId).fetch("https://hub.internal/socket", {
    headers: { Upgrade: "websocket", [HUB_IDENTITY_HEADER]: JSON.stringify(identity) },
  });
}
