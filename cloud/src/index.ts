// CaféDesk Online cloud relay — Worker entry (docs/PROTOCOL.md §8).
//
// The POS host is the only authority for orders, tickets, bills and refunds.
// This Worker authenticates, validates, stores the host's immutable events,
// projects reports, keeps private backups and relays commands through the
// restaurant's Durable Object. It never decides a business outcome.

import { authenticateDevice, authenticateHost } from "./auth/credentials";
import { authenticateSession } from "./auth/session";
import { ApiError, errorResponse, jsonResponse } from "./http/errors";
import { MAX_PROTOCOL_VERSION, MIN_PROTOCOL_VERSION } from "./protocol/constants";
import {
  handleDeviceEvents,
  handleDeviceRequest,
  handleDeviceSocket,
  handleGetCommand,
  handleSubmitCommand,
} from "./routes/device";
import { handleEnroll } from "./routes/enroll";
import {
  handleEvents,
  handleHostSocket,
  handleOpenEpoch,
  handleRotateCredential,
  handleSyncState,
} from "./routes/host";
import { handleSummary } from "./routes/reports";
import {
  handleDeleteMedia,
  handleGetBackup,
  handleGetMedia,
  handleListBackups,
  handleListMedia,
  handlePutBackup,
  handlePutMedia,
} from "./routes/storage";

export { RestaurantHub } from "./restaurant_hub/hub";

function notFound(): never {
  throw new ApiError("NOT_FOUND", "No such route");
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const method = request.method;
  const parts = url.pathname.split("/").filter((p) => p !== "");
  if (parts[0] !== "v1") notFound();
  const path = parts.slice(1);
  const at = (i: number) => decodeURIComponent(path[i] ?? "");
  const now = Date.now();
  const is = (m: string, ...segments: string[]) =>
    method === m && path.length === segments.length && segments.every((s, i) => s === "*" || s === path[i]);

  // --- unauthenticated -------------------------------------------------------
  if (is("GET", "health")) {
    return jsonResponse({ ok: true, minProtocolVersion: MIN_PROTOCOL_VERSION, maxProtocolVersion: MAX_PROTOCOL_VERSION });
  }
  if (is("POST", "enroll")) return handleEnroll(request, env, now);

  // --- host ------------------------------------------------------------------
  if (path[0] === "host") {
    const host = await authenticateHost(request, env.DB);
    if (is("POST", "host", "credential", "rotate")) return handleRotateCredential(env, host, now);
    if (is("GET", "host", "sync-state")) return handleSyncState(env, host);
    if (is("POST", "host", "epoch")) return handleOpenEpoch(request, env, host, now);
    if (is("POST", "host", "events")) return handleEvents(request, env, host, now);
    if (is("GET", "host", "socket")) return handleHostSocket(request, env, host, now);
    if (is("GET", "host", "backups")) return handleListBackups(env, host);
    if (is("PUT", "host", "backups", "*")) return handlePutBackup(request, env, host, at(2), now);
    if (is("GET", "host", "backups", "*")) return handleGetBackup(env, host, at(2));
    if (is("GET", "host", "media")) return handleListMedia(env, host);
    if (is("PUT", "host", "media", "*")) return handlePutMedia(request, env, host, at(2));
    if (is("GET", "host", "media", "*")) return handleGetMedia(env, host, at(2));
    if (is("DELETE", "host", "media", "*")) return handleDeleteMedia(env, host, at(2));
    notFound();
  }

  // --- device ------------------------------------------------------------------
  if (path[0] === "device") {
    const device = await authenticateDevice(request, env.DB);
    if (is("POST", "device", "requests")) return handleDeviceRequest(request, env, device);
    if (is("POST", "device", "commands")) return handleSubmitCommand(request, env, device);
    if (is("GET", "device", "commands", "*")) return handleGetCommand(request, env, device, at(2));
    if (is("GET", "device", "events")) return handleDeviceEvents(request, env, device);
    if (is("GET", "device", "socket")) return handleDeviceSocket(request, env, device);
    // Menu images: the device credential is enough (no staff data inside).
    if (is("GET", "device", "media", "*")) return handleGetMedia(env, device, at(2));
    await authenticateSession(request, env.DB, device);
    notFound();
  }

  if (is("GET", "reports", "summary")) return handleSummary(request, env);
  notFound();
}

export default {
  async fetch(request, env): Promise<Response> {
    try {
      return await route(request, env);
    } catch (error) {
      if (error instanceof ApiError) return errorResponse(error);
      if (error instanceof URIError) return errorResponse(new ApiError("VALIDATION", "Malformed URL"));
      // Never log request bodies, headers or credentials.
      console.error("Unhandled error", error instanceof Error ? `${error.name}: ${error.message}` : "unknown");
      return errorResponse(new ApiError("INTERNAL", "Internal error"));
    }
  },
} satisfies ExportedHandler<Env>;
