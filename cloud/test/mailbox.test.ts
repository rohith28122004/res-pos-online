// RestaurantHub: durable command mailbox, host/device sockets and request relay.
import { evictDurableObject, runDurableObjectAlarm, runInDurableObject } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { RestaurantHub } from "../src/restaurant_hub/hub";
import {
  acceptAll,
  api,
  command,
  connectHost,
  deviceHeaders,
  event,
  hostHeaders,
  json,
  jsonInit,
  newRestaurant,
  openSocket,
  pairDevice,
  sendEvents,
  staffToken,
  type Device,
  type Restaurant,
} from "./helpers";

async function setup() {
  const r = await newRestaurant();
  const waiter = await pairDevice(r, "waiter");
  const { token, claims } = await staffToken(r, waiter);
  const submit = (body: Record<string, unknown>) =>
    api("/v1/device/commands", jsonInit("POST", body, deviceHeaders(waiter, token)));
  const lookup = (commandId: string, device: Device = waiter, t: string = token) =>
    api(`/v1/device/commands/${commandId}`, { headers: deviceHeaders(device, t) });
  return { r, waiter, token, staffId: claims.sub, submit, lookup };
}

function hubStub(r: Restaurant) {
  return env.HUB.get(env.HUB.idFromName(r.restaurantId));
}

describe("mailbox without a host connection", () => {
  it("queues the command — not accepted — and dedupes the same id + body", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const body = command(r, waiter, staffId);
    const res = await submit(body);
    expect(res.status).toBe(200);
    const queued = await json(res);
    expect(queued).toMatchObject({ commandId: body["commandId"], mailboxState: "queued" });
    expect(queued.result).toBeUndefined(); // queued is never a business acceptance

    // Same command again (timeout retry): the same entry, nothing new.
    const again = await json(await submit(body));
    expect(again).toEqual(queued);

    // Same id, different body → COMMAND_ID_REUSED.
    const changed = { ...body, payload: { ...(body["payload"] as object), guestCount: 3 } };
    const reused = await submit(changed);
    expect(reused.status).toBe(409);
    expect((await json(reused)).error).toMatchObject({ code: "COMMAND_ID_REUSED", retryable: false });

    const status = await json(await lookup(String(body["commandId"])));
    expect(status).toMatchObject({ commandId: body["commandId"], mailboxState: "queued", result: null });
  });

  it("refuses relayed requests with HOST_UNREACHABLE", async () => {
    const { waiter, token } = await setup();
    const res = await api(
      "/v1/device/requests",
      jsonInit("POST", { kind: "snapshot", body: { scope: "waiter" } }, deviceHeaders(waiter, token)),
    );
    expect(res.status).toBe(503);
    expect((await json(res)).error).toMatchObject({ code: "HOST_UNREACHABLE", retryable: true });
  });

  it("expires a command not delivered within 30 minutes and never delivers it", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const body = command(r, waiter, staffId);
    await (await submit(body)).arrayBuffer();
    const stub = hubStub(r);
    const start = Date.now();

    // 29 minutes: still queued.
    await runInDurableObject(stub, (hub: RestaurantHub) => {
      hub.clock = () => start + 29 * 60_000;
    });
    expect(await runDurableObjectAlarm(stub)).toBe(true);
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("queued");

    // 31 minutes: expired by the alarm.
    await runInDurableObject(stub, (hub: RestaurantHub) => {
      hub.clock = () => start + 31 * 60_000;
    });
    await runDurableObjectAlarm(stub);
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("expired");

    // A host that connects now receives nothing.
    const host = await connectHost(r);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(host.messages.filter((m) => m.t === "command")).toHaveLength(0);
    // Resubmitting returns the expired entry; it is not revived.
    expect((await json(await submit(body))).mailboxState).toBe("expired");
    host.close();
  });

  it("quarantines queued commands of an older epoch when a new epoch opens", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const body = command(r, waiter, staffId);
    await (await submit(body)).arrayBuffer();
    const deviceSocket = await openSocket("/v1/device/socket", deviceHeaders(waiter, (await staffToken(r, waiter)).token));

    const open = await api("/v1/host/epoch", jsonInit("POST", { epoch: 2, startSequence: 1, reason: "restore" }, hostHeaders(r)));
    expect((await json(open)).quarantinedCommands).toBe(1);
    // Sessions of the old epoch are no longer valid; sign in again for epoch 2.
    const epoch2Token = (await staffToken(r, waiter, { ep: 2 })).token;
    expect((await json(await lookup(String(body["commandId"]), waiter, epoch2Token))).mailboxState).toBe("quarantined");
    const note = await deviceSocket.next((m) => m.t === "command" && m.commandId === body["commandId"]);
    expect(note.mailboxState).toBe("quarantined");

    // The host never gets it.
    const host = await connectHost(r);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(host.messages.filter((m) => m.t === "command")).toHaveLength(0);

    // A command still stamped with the old epoch is refused (not stored).
    const stale = await api(
      "/v1/device/commands",
      jsonInit("POST", command(r, waiter, staffId), deviceHeaders(waiter, (await staffToken(r, waiter, { ep: 1 })).token)),
    );
    expect(stale.status).toBe(401); // the epoch-1 session itself is no longer valid
    await stale.arrayBuffer();
    r.epoch = 2;
    const tokenEp2 = (await staffToken(r, waiter)).token;
    const oldEpochCommand = await api(
      "/v1/device/commands",
      jsonInit("POST", command(r, waiter, staffId, { hostEpoch: 1 }), deviceHeaders(waiter, tokenEp2)),
    );
    expect(oldEpochCommand.status).toBe(409);
    expect((await json(oldEpochCommand)).error).toMatchObject({ code: "EPOCH_CHANGED", details: { currentEpoch: 2 } });
    host.close();
    deviceSocket.close();
  });

  it("keeps the mailbox in Durable Object storage across eviction", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const body = command(r, waiter, staffId);
    await (await submit(body)).arrayBuffer();
    // Evict the object: in-memory state is gone, storage remains.
    await evictDurableObject(hubStub(r));
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("queued");
    const host = await connectHost(r);
    const delivered = await host.next((m) => m.t === "command");
    expect(delivered.command).toEqual(body);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect((await json(await lookup(String(body["commandId"])))).result.state).toBe("accepted");
    host.close();
  });

  it("re-sends an unanswered delivery to the next host connection within 30 minutes", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const body = command(r, waiter, staffId);
    await (await submit(body)).arrayBuffer();
    const silent = await connectHost(r, null);
    await silent.next((m) => m.t === "command");
    silent.close();
    await silent.waitClosed();
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("delivered");
    // The host is idempotent by commandId + bodyHash, so sending it again is safe.
    const host = await connectHost(r);
    expect((await host.next((m) => m.t === "command")).command).toEqual(body);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("answered");
    host.close();
  });

  it("does not re-run an unanswered delivery older than 30 minutes; it asks the host instead", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const recent = command(r, waiter, staffId);
    const old = command(r, waiter, staffId);
    await (await submit(old)).arrayBuffer();
    // A host takes both and disconnects without answering.
    const silent = await connectHost(r, null);
    await silent.next((m) => m.t === "command" && m.command.commandId === old["commandId"]);
    await (await submit(recent)).arrayBuffer(); // waits ≤ 8 s while connected
    silent.close();
    await silent.waitClosed();
    expect((await json(await lookup(String(old["commandId"])))).mailboxState).toBe("delivered");

    // 31 minutes after the first one was received.
    const stub = hubStub(r);
    const start = Date.now();
    await runInDurableObject(stub, (hub: RestaurantHub) => {
      hub.clock = () => start + 31 * 60_000;
    });
    const host = await connectHost(r, null);
    host.ws.addEventListener("message", (e) => {
      const msg = JSON.parse(e.data as string);
      if (msg.t === "request" && msg.kind === "command_lookup") {
        // The host never committed it.
        host.send({ t: "response", requestId: msg.requestId, status: 404, body: { error: { code: "NOT_FOUND" } } });
      }
    });
    const lookupRequest = await host.next((m) => m.t === "request");
    expect(lookupRequest).toMatchObject({ kind: "command_lookup", body: { commandId: old["commandId"] } });
    await new Promise((resolve) => setTimeout(resolve, 300));
    // The old command was not re-run; it is expired now.
    expect(host.messages.filter((m) => m.t === "command" && m.command.commandId === old["commandId"])).toHaveLength(0);
    expect((await json(await lookup(String(old["commandId"])))).mailboxState).toBe("expired");
    host.close();
  });
});

describe("mailbox with the host connected", () => {
  it("delivers to the host socket and relays the host result back to the device", async () => {
    const { r, waiter, token, staffId, submit, lookup } = await setup();
    const deviceSocket = await openSocket("/v1/device/socket", deviceHeaders(waiter, token));
    expect(await deviceSocket.next((m) => m.t === "host")).toEqual({ t: "host", connected: false });
    const host = await connectHost(r);
    expect(await deviceSocket.next((m) => m.t === "host" && m.connected === true)).toBeTruthy();

    const body = command(r, waiter, staffId);
    const res = await json(await submit(body));
    expect(res.mailboxState).toBe("answered");
    expect(res.result).toMatchObject({ commandId: body["commandId"], state: "accepted", resultId: "order-1" });

    // The host got the exact command, the session token and the device id.
    const delivered = await host.next((m) => m.t === "command");
    expect(delivered.command).toEqual(body);
    expect(delivered.deviceId).toBe(waiter.deviceId);
    expect(delivered.sessionToken).toBe(token);

    const note = await deviceSocket.next((m) => m.t === "command" && m.mailboxState === "answered");
    expect(note.result.state).toBe("accepted");
    expect((await json(await lookup(String(body["commandId"])))).result.state).toBe("accepted");

    // The same command again returns the stored answer; the host sees no second delivery.
    expect((await json(await submit(body))).result.state).toBe("accepted");
    expect(host.messages.filter((m) => m.t === "command")).toHaveLength(1);
    host.close();
    deviceSocket.close();
  });

  it("delivers commands queued while the host was away, oldest first, when it connects", async () => {
    const { r, waiter, staffId, submit } = await setup();
    const first = command(r, waiter, staffId);
    const second = command(r, waiter, staffId);
    await (await submit(first)).arrayBuffer();
    await (await submit(second)).arrayBuffer();

    const host = await connectHost(r);
    await host.next((m) => m.t === "command" && m.command.commandId === second["commandId"]);
    const order = host.messages.filter((m) => m.t === "command").map((m) => m.command.commandId);
    expect(order).toEqual([first["commandId"], second["commandId"]]);
    host.close();
  });

  it("keeps a business rejection as the answer, and lets an auth rejection be resubmitted", async () => {
    const { r, waiter, staffId, submit } = await setup();
    let reply = "TABLE_OCCUPIED";
    const host = await connectHost(r, (cmd) => ({
      commandId: cmd.commandId,
      state: "rejected",
      hostEpoch: r.epoch,
      eventSequence: 0,
      result: null,
      error: { code: reply, message: "no", retryable: false, details: {} },
    }));
    const business = command(r, waiter, staffId);
    expect((await json(await submit(business))).result.error.code).toBe("TABLE_OCCUPIED");
    expect((await json(await submit(business))).result.error.code).toBe("TABLE_OCCUPIED");
    expect(host.messages.filter((m) => m.t === "command")).toHaveLength(1);

    reply = "SESSION_EXPIRED";
    const auth = command(r, waiter, staffId);
    expect((await json(await submit(auth))).result.error.code).toBe("SESSION_EXPIRED");
    reply = "CONFLICT";
    // After signing in again the identical command is queued and delivered again.
    expect((await json(await submit(auth))).result.error.code).toBe("CONFLICT");
    expect(host.messages.filter((m) => m.t === "command" && m.command.commandId === auth["commandId"])).toHaveLength(2);
    host.close();
  });

  it("returns mailboxState delivered when the host does not answer within 8 s", async () => {
    const { r, waiter, staffId, submit, lookup } = await setup();
    const host = await connectHost(r, null); // receives, never answers
    const body = command(r, waiter, staffId);
    const started = Date.now();
    const res = await json(await submit(body));
    expect(res.mailboxState).toBe("delivered");
    expect(res.result).toBeUndefined();
    expect(Date.now() - started).toBeGreaterThanOrEqual(7_000);

    // A late answer is still recorded.
    host.send({
      t: "result",
      result: { ...acceptAll(r)({ commandId: body["commandId"] }) },
    });
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect((await json(await lookup(String(body["commandId"])))).mailboxState).toBe("answered");
    host.close();
  });

  it("relays sealed_auth and snapshot requests to the host and returns its response", async () => {
    const { waiter, token, r } = await setup();
    const host = await connectHost(r, null);
    host.ws.addEventListener("message", (e) => {
      const msg = JSON.parse(e.data as string);
      if (msg.t !== "request") return;
      const body =
        msg.kind === "sealed_auth"
          ? { sessionToken: "cds1.x.y", expiresAt: 1, staff: { staffId: "s", name: "Asha", role: "waiter" } }
          : { hostEpoch: 1, cursor: 3, kind: msg.kind, sessionToken: msg.sessionToken, deviceId: msg.deviceId };
      host.send({ t: "response", requestId: msg.requestId, status: 200, body });
    });

    const sealed = {
      v: 1,
      alg: "X25519-HKDF-SHA256-A256GCM",
      epk: "A".repeat(42) + "A",
      nonce: "AAAAAAAAAAAAAAAA",
      ct: "B".repeat(40),
    };
    // sealed_auth needs only the device credential.
    const auth = await api(
      "/v1/device/requests",
      jsonInit("POST", { kind: "sealed_auth", body: { sealed } }, { "X-CafeDesk-Device": waiter.credential }),
    );
    expect(auth.status).toBe(200);
    expect((await json(auth)).staff.role).toBe("waiter");

    const snap = await api(
      "/v1/device/requests",
      jsonInit("POST", { kind: "snapshot", body: { scope: "waiter" } }, deviceHeaders(waiter, token)),
    );
    expect(await json(snap)).toEqual({ hostEpoch: 1, cursor: 3, kind: "snapshot", sessionToken: token, deviceId: waiter.deviceId });

    // A waiter may not read the kitchen snapshot.
    const kitchen = await api(
      "/v1/device/requests",
      jsonInit("POST", { kind: "snapshot", body: { scope: "kitchen" } }, deviceHeaders(waiter, token)),
    );
    expect(kitchen.status).toBe(403);
    await kitchen.arrayBuffer();
    host.close();
  });

  it("answers HOST_TIMEOUT when the host does not respond to a relayed request", async () => {
    const { waiter, token, r } = await setup();
    const host = await connectHost(r, null);
    const res = await api(
      "/v1/device/requests",
      jsonInit("POST", { kind: "command_lookup", body: { commandId: "c1" } }, deviceHeaders(waiter, token)),
    );
    expect(res.status).toBe(504);
    expect((await json(res)).error).toMatchObject({ code: "HOST_TIMEOUT", retryable: true });
    host.close();
  });

  it("a newer host connection replaces the older one", async () => {
    const { r } = await setup();
    const first = await connectHost(r);
    const second = await connectHost(r);
    const closed = await first.waitClosed();
    expect(closed.code).toBe(4000);
    expect(await runInDurableObject(hubStub(r), (hub: RestaurantHub) => hub.hostConnected())).toBe(true);
    second.close();
  });

  it("notifies device sockets after events are ingested and closes revoked devices", async () => {
    const { r, waiter, token } = await setup();
    const socket = await openSocket("/v1/device/socket", deviceHeaders(waiter, token));
    await socket.next((m) => m.t === "host");
    // On connect the hub tells the device how far the ledger goes (the pairing event).
    expect(await socket.next((m) => m.t === "events")).toEqual({ t: "events", hostEpoch: 1, latestSequence: 1 });
    const t = crypto.randomUUID();
    await sendEvents(r, [event(r, "ticket.updated", "kitchen_ticket", t, { ticketId: t, status: "ready", revision: 2 })]);
    expect(await socket.next((m) => m.t === "events" && m.latestSequence === 2)).toEqual({
      t: "events",
      hostEpoch: 1,
      latestSequence: 2,
    });

    await sendEvents(r, [event(r, "device.revoked", "device", waiter.deviceId, { deviceId: waiter.deviceId, revokedAt: Date.now() })]);
    expect((await socket.waitClosed()).code).toBe(4001);
  });
});
