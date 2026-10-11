// Test helpers: enrol restaurants, pair devices, sign staff sessions, build
// events and talk to the Worker through its real fetch handler (local D1, R2
// and Durable Object bindings from wrangler.jsonc).

import { env, exports } from "cloudflare:workers";
import { b64urlEncode, sha256hex } from "../src/protocol/canonical";
import { generateEnrollmentCode, hashEnrollmentCode, normalizeEnrollmentCode } from "../src/protocol/enrollment_code";

export const BASE = "https://cloud.test";

let ipCounter = 0;
/** A fresh client address per call, so enrollment rate limits never interfere between tests. */
export function freshIp(): string {
  ipCounter += 1;
  return `198.51.${Math.floor(ipCounter / 250)}.${ipCounter % 250}`;
}

export function api(path: string, init: RequestInit = {}): Promise<Response> {
  return exports.default.fetch(`${BASE}${path}`, init);
}

export async function json<T = any>(response: Response): Promise<T> {
  return (await response.json()) as T;
}

export function jsonInit(method: string, body: unknown, headers: Record<string, string> = {}): RequestInit {
  return { method, headers: { "Content-Type": "application/json", ...headers }, body: JSON.stringify(body) };
}

export async function issueCode(options: { expiresInMs?: number; now?: number } = {}): Promise<string> {
  const now = options.now ?? Date.now();
  const code = generateEnrollmentCode();
  const hash = await hashEnrollmentCode(normalizeEnrollmentCode(code)!);
  await env.DB.prepare("INSERT INTO enrollment_codes (code_hash, label, created_at, expires_at) VALUES (?1, 'test', ?2, ?3)")
    .bind(hash, now, now + (options.expiresInMs ?? 3_600_000))
    .run();
  return code;
}

export interface Restaurant {
  restaurantId: string;
  hostDeviceId: string;
  hostCredential: string;
  signingKey: CryptoKey;
  signingPublicKey: string;
  epoch: number;
  nextSeq: number;
}

export async function enrollBody(code: string, publicKey?: string) {
  const keys = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
  const raw = (await crypto.subtle.exportKey("raw", keys.publicKey)) as ArrayBuffer;
  return {
    keys,
    signingPublicKey: publicKey ?? b64urlEncode(raw),
    body: {
      protocolVersion: 1,
      enrollmentCode: code,
      restaurantId: crypto.randomUUID(),
      restaurantName: "Test Café",
      hostDeviceId: crypto.randomUUID(),
      hostSigningPublicKey: publicKey ?? b64urlEncode(raw),
      hostSealPublicKey: b64urlEncode(crypto.getRandomValues(new Uint8Array(32))),
      appVersion: "1.0.0-test",
    },
  };
}

export async function newRestaurant(): Promise<Restaurant> {
  const code = await issueCode();
  const { keys, signingPublicKey, body } = await enrollBody(code);
  const res = await api("/v1/enroll", jsonInit("POST", body, { "CF-Connecting-IP": freshIp() }));
  if (res.status !== 201) throw new Error(`enroll failed: ${res.status} ${await res.text()}`);
  const out = await json<{ restaurantId: string; hostCredential: string }>(res);
  return {
    restaurantId: out.restaurantId,
    hostDeviceId: body.hostDeviceId,
    hostCredential: out.hostCredential,
    signingKey: keys.privateKey,
    signingPublicKey,
    epoch: 1,
    nextSeq: 1,
  };
}

export function hostHeaders(r: Restaurant): Record<string, string> {
  return { Authorization: `Bearer ${r.hostCredential}` };
}

export interface Event {
  protocolVersion: number;
  eventId: string;
  hostEpoch: number;
  sequence: number;
  type: string;
  aggregateType: string;
  aggregateId: string;
  revision: number;
  committedAtUtc: number;
  businessDate: string | null;
  payload: Record<string, unknown>;
}

/** The next event of the restaurant's host (sequence advances). */
export function event(
  r: Restaurant,
  type: string,
  aggregateType: string,
  aggregateId: string,
  payload: Record<string, unknown>,
  options: { businessDate?: string | null; revision?: number; committedAt?: number } = {},
): Event {
  const e: Event = {
    protocolVersion: 1,
    eventId: crypto.randomUUID(),
    hostEpoch: r.epoch,
    sequence: r.nextSeq,
    type,
    aggregateType,
    aggregateId,
    revision: options.revision ?? 1,
    committedAtUtc: options.committedAt ?? 1_760_000_000_000 + r.nextSeq,
    businessDate: options.businessDate === undefined ? "2026-10-05" : options.businessDate,
    payload,
  };
  r.nextSeq += 1;
  return e;
}

export function postEvents(r: Restaurant, events: Event[], hostEpoch = r.epoch): Promise<Response> {
  return api("/v1/host/events", jsonInit("POST", { hostEpoch, events }, hostHeaders(r)));
}

export async function sendEvents(r: Restaurant, events: Event[]): Promise<any> {
  const res = await postEvents(r, events);
  if (res.status !== 200) throw new Error(`events failed: ${res.status} ${await res.text()}`);
  return json(res);
}

export interface Device {
  deviceId: string;
  credential: string;
  role: "waiter" | "kitchen";
}

export async function pairDevice(r: Restaurant, role: "waiter" | "kitchen" = "waiter"): Promise<Device> {
  const deviceId = crypto.randomUUID();
  const credential = `cdd1.${deviceId}.${b64urlEncode(crypto.getRandomValues(new Uint8Array(32)))}`;
  await sendEvents(r, [
    event(r, "device.paired", "device", deviceId, {
      deviceId,
      role,
      name: `${role} phone`,
      credentialHash: await sha256hex(credential),
      pairedAt: Date.now(),
    }),
  ]);
  return { deviceId, credential, role };
}

export interface Claims {
  v: number;
  sid: string;
  rid: string;
  did: string;
  sub: string;
  name: string;
  role: string;
  ep: number;
  iat: number;
  exp: number;
}

export async function signToken(key: CryptoKey, claims: object): Promise<string> {
  const head = `cds1.${b64urlEncode(new TextEncoder().encode(JSON.stringify(claims)))}`;
  const signature = await crypto.subtle.sign({ name: "Ed25519" }, key, new TextEncoder().encode(head));
  return `${head}.${b64urlEncode(signature)}`;
}

export async function staffToken(
  r: Restaurant,
  device: Device,
  overrides: Partial<Claims> = {},
): Promise<{ token: string; claims: Claims }> {
  const iat = Math.floor(Date.now() / 1000) - 60;
  const claims: Claims = {
    v: 1,
    sid: crypto.randomUUID(),
    rid: r.restaurantId,
    did: device.deviceId,
    sub: `staff-${device.role}`,
    name: "Asha",
    role: device.role,
    ep: r.epoch,
    iat,
    exp: iat + 12 * 3600,
    ...overrides,
  };
  return { token: await signToken(r.signingKey, claims), claims };
}

export function deviceHeaders(device: Device, token?: string): Record<string, string> {
  return token
    ? { "X-CafeDesk-Device": device.credential, Authorization: `Bearer ${token}` }
    : { "X-CafeDesk-Device": device.credential };
}

export function command(
  r: Restaurant,
  device: Device,
  staffId: string,
  overrides: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    protocolVersion: 1,
    commandId: crypto.randomUUID(),
    restaurantId: r.restaurantId,
    deviceId: device.deviceId,
    staffId,
    hostEpoch: r.epoch,
    action: "order.place",
    aggregateId: null,
    expectedRevision: null,
    issuedAt: Date.now(),
    payload: {
      orderType: "dine_in",
      tableId: "t4",
      guestCount: 2,
      lines: [{ itemId: "coffee", variantId: null, modifierIds: [], quantity: 2, note: null, expectedUnitPrice: 4500 }],
      sendToKitchen: true,
    },
    ...overrides,
  };
}

// ---------------------------------------------------------------------------
// WebSocket client for tests
// ---------------------------------------------------------------------------

export class SocketClient {
  readonly messages: any[] = [];
  closed: { code: number; reason: string } | null = null;
  readonly #waiters: Array<() => void> = [];
  readonly ws: WebSocket;

  constructor(ws: WebSocket) {
    this.ws = ws;
    ws.accept();
    ws.addEventListener("message", (e) => {
      this.messages.push(JSON.parse(e.data as string));
      this.#wake();
    });
    ws.addEventListener("close", (e) => {
      this.closed = { code: e.code, reason: e.reason };
      this.#wake();
    });
  }

  #wake(): void {
    for (const w of this.#waiters.splice(0)) w();
  }

  /** Resolves with the first message (received so far or later) matching `predicate`. */
  async next(predicate: (m: any) => boolean, timeoutMs = 4000): Promise<any> {
    const deadline = Date.now() + timeoutMs;
    for (;;) {
      const found = this.messages.find(predicate);
      if (found) return found;
      if (Date.now() > deadline) throw new Error(`No matching message; got ${JSON.stringify(this.messages)}`);
      await new Promise<void>((resolve) => {
        this.#waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
  }

  async waitClosed(timeoutMs = 4000): Promise<{ code: number; reason: string }> {
    const deadline = Date.now() + timeoutMs;
    while (!this.closed) {
      if (Date.now() > deadline) throw new Error("Socket did not close");
      await new Promise<void>((resolve) => {
        this.#waiters.push(resolve);
        setTimeout(resolve, 50);
      });
    }
    return this.closed;
  }

  send(message: unknown): void {
    this.ws.send(JSON.stringify(message));
  }

  close(): void {
    try {
      this.ws.close(1000, "done");
    } catch {
      // already closed
    }
  }
}

export async function openSocket(path: string, headers: Record<string, string>): Promise<SocketClient> {
  const res = await api(path, { headers: { Upgrade: "websocket", ...headers } });
  if (res.status !== 101 || !res.webSocket) throw new Error(`socket refused: ${res.status} ${await res.text()}`);
  return new SocketClient(res.webSocket);
}

/** A fake POS host on the relay socket that answers commands with `answer`. */
export async function connectHost(
  r: Restaurant,
  answer: ((cmd: any) => Record<string, unknown> | null) | null = acceptAll(r),
): Promise<SocketClient> {
  const host = await openSocket("/v1/host/socket", hostHeaders(r));
  if (answer) {
    host.ws.addEventListener("message", (e) => {
      const msg = JSON.parse(e.data as string);
      if (msg.t === "command") {
        const result = answer(msg.command);
        if (result) host.send({ t: "result", result });
      }
    });
  }
  return host;
}

export function acceptAll(r: Restaurant) {
  let seq = 1000;
  return (cmd: any) => ({
    commandId: cmd.commandId,
    state: "accepted",
    resultId: "order-1",
    revision: 1,
    hostEpoch: r.epoch,
    eventSequence: ++seq,
    acceptedAt: Date.now(),
    result: { orderId: "order-1", orderNo: 12, orderRef: "T4 · #12", revision: 1, estimatedTotal: 9000 },
    error: null,
  });
}
