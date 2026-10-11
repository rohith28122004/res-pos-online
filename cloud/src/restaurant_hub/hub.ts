// RestaurantHub — one Durable Object per restaurant (idFromName(restaurantId)),
// docs/PROTOCOL.md §8.1.
//
// * Hibernating WebSockets: at most one host socket (a newer authenticated host
//   connection replaces the older one) and any number of device sockets, tagged
//   by device, staff and session so revocations can close them.
// * The durable command mailbox (./mailbox.ts) in SQLite storage.
// * Request relay (sealed_auth, snapshot, command_lookup): forwarded to the host
//   socket, answered within HOST_WAIT_MS or refused (503 / 504).
//
// The hub never invents a business result: a queued or delivered command is
// relay state only; acceptance is the host's result, stored verbatim.
//
// Only the Worker talks to this object. The Worker authenticates every caller
// and passes the verified identity in; nothing here trusts client input for
// identity.

import { DurableObject } from "cloudflare:workers";
import {
  HOST_WAIT_MS,
  MAILBOX_DELIVERY_TTL_MS,
  MAX_HOST_MESSAGE_BYTES,
  type RelayKind,
  type StaffRole,
} from "../protocol/constants";
import { CommandResult, HostMessage } from "../protocol/schemas";
import { isResubmittable, Mailbox, toView, type MailboxRow, type MailboxView, type StateChange } from "./mailbox";

/** Identity attached to a host socket (serializeAttachment, survives hibernation). */
export interface HostIdentity {
  kind: "host";
  restaurantId: string;
  hostDeviceId: string;
  credentialHash: string;
  connectedAt: number;
}

/** Identity attached to a device socket. */
export interface DeviceIdentity {
  kind: "device";
  restaurantId: string;
  deviceId: string;
  staffId: string;
  sessionId: string;
  role: StaffRole;
  /** Session expiry, epoch milliseconds. */
  expiresAt: number;
}

type SocketIdentity = HostIdentity | DeviceIdentity;

/** Header the Worker uses to hand the verified identity to the hub. */
export const HUB_IDENTITY_HEADER = "X-CafeDesk-Hub-Identity";

export interface SubmitCommandInput {
  restaurantId: string;
  commandId: string;
  /** The command envelope exactly as the device sent it (parsed JSON). */
  command: Record<string, unknown>;
  bodyHash: string;
  hostEpoch: number;
  deviceId: string;
  staffId: string;
  sessionToken: string;
  /** Current epoch according to D1 (null before epoch 1 opens). */
  cloudEpoch: number | null;
}

export interface HubError {
  code: "COMMAND_ID_REUSED" | "EPOCH_CHANGED" | "HOST_UNREACHABLE" | "HOST_TIMEOUT";
  message: string;
  details: Record<string, unknown>;
}

export type SubmitOutcome = { ok: true; entry: MailboxView } | { ok: false; error: HubError };

export interface RelayInput {
  restaurantId: string;
  kind: RelayKind;
  deviceId: string;
  sessionToken: string | null;
  body: Record<string, unknown>;
}

export type RelayOutcome = { ok: true; status: number; body: unknown } | { ok: false; error: HubError };

export interface EventsCommittedInput {
  restaurantId: string;
  hostEpoch: number;
  latestSequence: number;
  /** Whether the batch had device-audience events (only then are devices woken). */
  notifyDevices: boolean;
  /** Devices revoked or re-paired by this batch: their sockets are closed. */
  revokedDevices: string[];
  /** Sessions revoked by this batch. */
  revokedSessions: string[];
  /** Staff disabled or whose role changed: their sockets are closed. */
  staffChanged: string[];
}

interface PendingRequest {
  resolve: (outcome: RelayOutcome) => void;
  timer: ReturnType<typeof setTimeout>;
  /** Internal look-ups for stale deliveries carry the command id. */
  lookupCommandId: string | null;
}

const CLOSE_REPLACED = 4000;
const CLOSE_REVOKED = 4001;
const CLOSE_SESSION_EXPIRED = 4002;

function hostUnreachable(): HubError {
  return { code: "HOST_UNREACHABLE", message: "The POS is not connected to the cloud", details: {} };
}

function byteLength(text: string): number {
  return new TextEncoder().encode(text).byteLength;
}

export class RestaurantHub extends DurableObject<Env> {
  readonly #mailbox: Mailbox;
  readonly #pendingRequests = new Map<string, PendingRequest>();
  readonly #answerWaiters = new Map<string, Set<() => void>>();

  /** Wall clock; tests replace it to move time (e.g. past the 30-minute limit). */
  clock: () => number = () => Date.now();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    this.#mailbox = new Mailbox(ctx.storage.sql);
    // Pings are answered by the runtime without waking a hibernated object.
    ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('{"t":"ping"}', '{"t":"pong"}'));
  }

  // -------------------------------------------------------------------------
  // Restaurant binding: one hub serves exactly one restaurant.
  // -------------------------------------------------------------------------

  #bindRestaurant(restaurantId: string): void {
    const bound = this.#mailbox.getMeta("restaurant_id");
    if (bound === null) {
      this.#mailbox.setMeta("restaurant_id", restaurantId);
    } else if (bound !== restaurantId) {
      // idFromName(restaurantId) makes this impossible unless the Worker is wrong.
      throw new Error("RestaurantHub called for a different restaurant");
    }
  }

  #currentEpoch(cloudEpoch: number | null): number | null {
    const stored = this.#mailbox.getMeta("epoch");
    const known = stored === null ? null : Number(stored);
    if (cloudEpoch !== null && (known === null || cloudEpoch > known)) {
      this.#mailbox.setMeta("epoch", String(cloudEpoch));
      return cloudEpoch;
    }
    return known;
  }

  // -------------------------------------------------------------------------
  // WebSockets
  // -------------------------------------------------------------------------

  override async fetch(request: Request): Promise<Response> {
    const raw = request.headers.get(HUB_IDENTITY_HEADER);
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket" || raw === null) {
      return new Response("Expected an authenticated WebSocket upgrade", { status: 400 });
    }
    const identity = JSON.parse(raw) as SocketIdentity;
    this.#bindRestaurant(identity.restaurantId);
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    if (identity.kind === "host") {
      const previous = this.ctx.getWebSockets("host");
      this.ctx.acceptWebSocket(server, ["host"]);
      server.serializeAttachment(identity);
      for (const old of previous) {
        try {
          old.close(CLOSE_REPLACED, "Replaced by a newer host connection");
        } catch {
          // already closing
        }
      }
      this.#broadcastToDevices({ t: "host", connected: true });
      this.#deliverPending(server);
    } else {
      this.ctx.acceptWebSocket(server, [
        "device",
        `device:${identity.deviceId}`,
        `staff:${identity.staffId}`,
        `session:${identity.sessionId}`,
      ]);
      server.serializeAttachment(identity);
      server.send(JSON.stringify({ t: "host", connected: this.#hostSocket() !== null }));
      const latest = this.#mailbox.getMeta("latest");
      if (latest !== null) server.send(JSON.stringify({ t: "events", ...(JSON.parse(latest) as object) }));
    }
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    const identity = ws.deserializeAttachment() as SocketIdentity | null;
    if (identity === null) return;
    if (identity.kind === "device") {
      // Device sockets are read-only (§7.2); only enforce session expiry here.
      if (identity.expiresAt <= this.clock()) ws.close(CLOSE_SESSION_EXPIRED, "Session expired");
      return;
    }
    if (typeof message !== "string" || byteLength(message) > MAX_HOST_MESSAGE_BYTES) {
      this.#sendError(ws, "Messages must be JSON text of at most 1 MiB");
      return;
    }
    let parsed: unknown;
    try {
      parsed = JSON.parse(message);
    } catch {
      this.#sendError(ws, "Message is not valid JSON");
      return;
    }
    const result = HostMessage.safeParse(parsed);
    if (!result.success) {
      this.#sendError(ws, "Unrecognised or invalid message");
      return;
    }
    const msg = result.data;
    switch (msg.t) {
      case "result":
        this.#onHostResult(msg.result);
        break;
      case "response":
        this.#onHostResponse(msg.requestId, msg.status, msg.body);
        break;
      case "events_available":
        // Informational: devices are told about events only after the batch is
        // durably ingested (POST /host/events), never before.
        this.#mailbox.setMeta(
          "host_latest",
          JSON.stringify({ hostEpoch: msg.hostEpoch, latestSequence: msg.latestSequence }),
        );
        break;
      case "ping":
        ws.send('{"t":"pong"}');
        break;
      case "pong":
        break;
    }
  }

  override async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
    this.#onSocketGone(ws);
    try {
      ws.close(code === 1005 || code === 1006 ? 1000 : code, reason);
    } catch {
      // already closed (auto-reply to close frames)
    }
  }

  override async webSocketError(ws: WebSocket): Promise<void> {
    this.#onSocketGone(ws);
  }

  #onSocketGone(ws: WebSocket): void {
    const identity = ws.deserializeAttachment() as SocketIdentity | null;
    if (identity?.kind !== "host") return;
    if (this.#hostSocket(ws) !== null) return; // a newer host connection is still open
    for (const [requestId, pending] of this.#pendingRequests) {
      clearTimeout(pending.timer);
      this.#pendingRequests.delete(requestId);
      pending.resolve({ ok: false, error: hostUnreachable() });
    }
    this.#broadcastToDevices({ t: "host", connected: false });
  }

  /** The open host socket, if any (ignoring `except`). Newest wins. */
  #hostSocket(except?: WebSocket): WebSocket | null {
    let best: WebSocket | null = null;
    let bestAt = -1;
    for (const ws of this.ctx.getWebSockets("host")) {
      if (ws === except || ws.readyState !== WebSocket.OPEN) continue;
      const identity = ws.deserializeAttachment() as HostIdentity | null;
      const at = identity?.connectedAt ?? 0;
      if (at >= bestAt) {
        best = ws;
        bestAt = at;
      }
    }
    return best;
  }

  #sendError(ws: WebSocket, message: string): void {
    ws.send(JSON.stringify({ t: "error", error: { code: "VALIDATION", message, retryable: false, details: {} } }));
  }

  #send(ws: WebSocket, message: unknown): boolean {
    try {
      ws.send(JSON.stringify(message));
      return true;
    } catch {
      return false;
    }
  }

  #broadcastToDevices(message: unknown, tag = "device"): void {
    const now = this.clock();
    const text = JSON.stringify(message);
    for (const ws of this.ctx.getWebSockets(tag)) {
      const identity = ws.deserializeAttachment() as DeviceIdentity | null;
      if (identity === null || identity.kind !== "device") continue;
      try {
        if (identity.expiresAt <= now) {
          ws.close(CLOSE_SESSION_EXPIRED, "Session expired");
          continue;
        }
        ws.send(text);
      } catch {
        // socket is closing; nothing to deliver
      }
    }
  }

  #notifyCommand(change: StateChange): void {
    const row = this.#mailbox.get(change.commandId);
    if (row === null) return;
    const view = toView(row);
    this.#broadcastToDevices(
      { t: "command", commandId: view.commandId, mailboxState: view.mailboxState, result: view.result },
      `device:${change.deviceId}`,
    );
  }

  #closeTagged(tag: string, code: number, reason: string): void {
    for (const ws of this.ctx.getWebSockets(tag)) {
      try {
        ws.close(code, reason);
      } catch {
        // already closing
      }
    }
  }

  // -------------------------------------------------------------------------
  // Mailbox: commands from devices
  // -------------------------------------------------------------------------

  async submitCommand(input: SubmitCommandInput): Promise<SubmitOutcome> {
    this.#bindRestaurant(input.restaurantId);
    const now = this.clock();
    this.#expireDue(now);

    let row = this.#mailbox.get(input.commandId);
    if (row !== null) {
      if (row.body_hash !== input.bodyHash) {
        return {
          ok: false,
          error: {
            code: "COMMAND_ID_REUSED",
            message: "This command id was already used for a different command",
            details: { commandId: input.commandId },
          },
        };
      }
      if (!isResubmittable(row)) {
        // Same command again (timeout retry, route switch): the existing entry.
        if (row.state === "queued" || row.state === "delivered") return this.#deliverAndWait(row);
        return { ok: true, entry: toView(row) };
      }
      // Answered with a non-business error (e.g. session expired): queue again below.
    }

    const epoch = this.#currentEpoch(input.cloudEpoch);
    if (epoch !== null && input.hostEpoch !== epoch) {
      // §4.1: not stored; the device shows the command for review.
      return {
        ok: false,
        error: {
          code: "EPOCH_CHANGED",
          message: "The POS was restored; review this order before sending it again",
          details: { currentEpoch: epoch },
        },
      };
    }

    row = this.#mailbox.insertQueued({
      commandId: input.commandId,
      bodyHash: input.bodyHash,
      bodyJson: JSON.stringify(input.command),
      deviceId: input.deviceId,
      staffId: input.staffId,
      sessionToken: input.sessionToken,
      hostEpoch: input.hostEpoch,
      now,
    });
    await this.#scheduleAlarm();
    return this.#deliverAndWait(row);
  }

  /** Delivers a queued/delivered entry if the host is connected and waits ≤ 8 s for its answer. */
  async #deliverAndWait(row: MailboxRow): Promise<SubmitOutcome> {
    const host = this.#hostSocket();
    if (host === null) return { ok: true, entry: toView(row) };
    if (row.state === "queued") {
      if (!this.#deliver(host, row)) return { ok: true, entry: toView(this.#mailbox.get(row.command_id) ?? row) };
    }
    await this.#waitForAnswer(row.command_id, HOST_WAIT_MS);
    const current = this.#mailbox.get(row.command_id);
    return { ok: true, entry: toView(current ?? row) };
  }

  /** Sends one command to the host and marks it delivered. */
  #deliver(host: WebSocket, row: MailboxRow): boolean {
    const sent = this.#send(host, {
      t: "command",
      command: JSON.parse(row.body_json) as unknown,
      sessionToken: row.session_token,
      deviceId: row.device_id,
    });
    if (sent && row.state === "queued") {
      this.#mailbox.markDelivered(row.command_id, this.clock());
      this.#notifyCommand({ commandId: row.command_id, deviceId: row.device_id });
    }
    return sent;
  }

  /**
   * On host (re)connect: queued commands oldest first; delivered-but-unanswered
   * ones are sent again while within their 30-minute limit (the host is
   * idempotent by command id + body hash). Older unanswered deliveries are not
   * re-run: the hub asks the host for the stored result instead.
   */
  #deliverPending(host: WebSocket): void {
    const now = this.clock();
    this.#expireDue(now);
    for (const row of this.#mailbox.pendingForHost()) {
      if (row.state === "queued" || row.received_at + MAILBOX_DELIVERY_TTL_MS > now) {
        this.#deliver(host, row);
      } else {
        void this.#lookupStaleDelivery(host, row);
      }
    }
  }

  async #lookupStaleDelivery(host: WebSocket, row: MailboxRow): Promise<void> {
    const outcome = await this.#relay(host, {
      kind: "command_lookup",
      deviceId: row.device_id,
      sessionToken: row.session_token,
      body: { commandId: row.command_id },
      lookupCommandId: row.command_id,
    });
    if (!outcome.ok) return; // try again on the next connection
    if (outcome.status === 200) {
      const result = CommandResult.safeParse(outcome.body);
      if (result.success && result.data.commandId === row.command_id) this.#onHostResult(result.data);
    } else if (outcome.status === 404) {
      // The host never committed it and it is past its limit: never run it now.
      for (const change of this.#mailbox.expireDelivered(row.command_id, this.clock())) {
        this.#wakeWaiters(change.commandId);
        this.#notifyCommand(change);
      }
      await this.#scheduleAlarm();
    }
  }

  #onHostResult(result: CommandResult): void {
    const row = this.#mailbox.markAnswered(result, this.clock());
    if (row === null) return; // unknown command or already answered: keep the first answer
    this.#wakeWaiters(row.command_id);
    this.#notifyCommand({ commandId: row.command_id, deviceId: row.device_id });
    void this.#scheduleAlarm();
  }

  #waitForAnswer(commandId: string, ms: number): Promise<void> {
    return new Promise((resolve) => {
      const waiters = this.#answerWaiters.get(commandId) ?? new Set<() => void>();
      const done = () => {
        clearTimeout(timer);
        waiters.delete(done);
        if (waiters.size === 0) this.#answerWaiters.delete(commandId);
        resolve();
      };
      const timer = setTimeout(done, ms);
      waiters.add(done);
      this.#answerWaiters.set(commandId, waiters);
    });
  }

  #wakeWaiters(commandId: string): void {
    const waiters = this.#answerWaiters.get(commandId);
    if (!waiters) return;
    for (const wake of [...waiters]) wake();
  }

  async getCommand(restaurantId: string, deviceId: string, commandId: string): Promise<MailboxView | null> {
    this.#bindRestaurant(restaurantId);
    this.#expireDue(this.clock());
    const row = this.#mailbox.get(commandId);
    // Own commands only: another device's command id looks like an unknown one.
    if (row === null || row.device_id !== deviceId) return null;
    return toView(row);
  }

  #expireDue(now: number): void {
    for (const change of this.#mailbox.expireDue(now)) {
      this.#wakeWaiters(change.commandId);
      this.#notifyCommand(change);
    }
  }

  async #scheduleAlarm(): Promise<void> {
    const next = this.#mailbox.nextDeadline();
    if (next === null) {
      await this.ctx.storage.deleteAlarm();
    } else {
      await this.ctx.storage.setAlarm(next);
    }
  }

  override async alarm(): Promise<void> {
    const now = this.clock();
    this.#expireDue(now);
    this.#mailbox.deleteOld(now);
    await this.#scheduleAlarm();
  }

  // -------------------------------------------------------------------------
  // Request relay (sealed_auth, snapshot, command_lookup)
  // -------------------------------------------------------------------------

  async relayRequest(input: RelayInput): Promise<RelayOutcome> {
    this.#bindRestaurant(input.restaurantId);
    const host = this.#hostSocket();
    if (host === null) return { ok: false, error: hostUnreachable() };
    return this.#relay(host, { ...input, lookupCommandId: null });
  }

  #relay(
    host: WebSocket,
    input: Omit<RelayInput, "restaurantId"> & { lookupCommandId: string | null },
  ): Promise<RelayOutcome> {
    const requestId = crypto.randomUUID();
    return new Promise<RelayOutcome>((resolve) => {
      const timer = setTimeout(() => {
        this.#pendingRequests.delete(requestId);
        resolve({
          ok: false,
          error: { code: "HOST_TIMEOUT", message: "The POS did not answer in time; ask again", details: {} },
        });
      }, HOST_WAIT_MS);
      this.#pendingRequests.set(requestId, { resolve, timer, lookupCommandId: input.lookupCommandId });
      const sent = this.#send(host, {
        t: "request",
        requestId,
        kind: input.kind,
        deviceId: input.deviceId,
        sessionToken: input.sessionToken,
        body: input.body,
      });
      if (!sent) {
        clearTimeout(timer);
        this.#pendingRequests.delete(requestId);
        resolve({ ok: false, error: hostUnreachable() });
      }
    });
  }

  #onHostResponse(requestId: string, status: number, body: unknown): void {
    const pending = this.#pendingRequests.get(requestId);
    if (!pending) return; // late answer after a timeout
    clearTimeout(pending.timer);
    this.#pendingRequests.delete(requestId);
    pending.resolve({ ok: true, status, body });
  }

  // -------------------------------------------------------------------------
  // Notifications from the Worker
  // -------------------------------------------------------------------------

  /** POST /host/epoch (or the implicit epoch 1): quarantine older commands. */
  async epochOpened(restaurantId: string, epoch: number): Promise<number> {
    this.#bindRestaurant(restaurantId);
    this.#currentEpoch(epoch);
    const changes = this.#mailbox.quarantineBefore(epoch, this.clock());
    for (const change of changes) {
      this.#wakeWaiters(change.commandId);
      this.#notifyCommand(change);
    }
    await this.#scheduleAlarm();
    return changes.length;
  }

  /** After an event batch is committed to D1. */
  async eventsCommitted(input: EventsCommittedInput): Promise<void> {
    this.#bindRestaurant(input.restaurantId);
    this.#currentEpoch(input.hostEpoch);
    const latest = { hostEpoch: input.hostEpoch, latestSequence: input.latestSequence };
    this.#mailbox.setMeta("latest", JSON.stringify(latest));
    for (const deviceId of input.revokedDevices) this.#closeTagged(`device:${deviceId}`, CLOSE_REVOKED, "Device revoked");
    for (const sid of input.revokedSessions) this.#closeTagged(`session:${sid}`, CLOSE_REVOKED, "Session revoked");
    for (const staffId of input.staffChanged) this.#closeTagged(`staff:${staffId}`, CLOSE_REVOKED, "Access changed");
    if (input.notifyDevices) this.#broadcastToDevices({ t: "events", ...latest });
  }

  /** POST /host/credential/rotate: sockets opened with the old credential close. */
  async hostCredentialRotated(restaurantId: string, oldCredentialHash: string): Promise<void> {
    this.#bindRestaurant(restaurantId);
    for (const ws of this.ctx.getWebSockets("host")) {
      const identity = ws.deserializeAttachment() as HostIdentity | null;
      if (identity?.credentialHash === oldCredentialHash) {
        try {
          ws.close(CLOSE_REVOKED, "Host credential rotated");
        } catch {
          // already closing
        }
      }
    }
  }

  /** Whether a host socket is open (diagnostics and tests). */
  async hostConnected(): Promise<boolean> {
    return this.#hostSocket() !== null;
  }
}
