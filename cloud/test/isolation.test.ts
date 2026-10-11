// Cross-restaurant isolation: restaurant A's credentials can never read or
// write restaurant B's events, commands, reports, backups or sockets.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { b64urlEncode, sha256hex, sha256hexBytes } from "../src/protocol/canonical";
import {
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
  postEvents,
  sendEvents,
  signToken,
  staffToken,
} from "./helpers";

async function twoRestaurants() {
  const a = await newRestaurant();
  const b = await newRestaurant();
  const deviceA = await pairDevice(a, "waiter");
  const deviceB = await pairDevice(b, "waiter");
  const tokenA = (await staffToken(a, deviceA)).token;
  const tokenB = (await staffToken(b, deviceB)).token;
  return { a, b, deviceA, deviceB, tokenA, tokenB };
}

function expense(r: Awaited<ReturnType<typeof newRestaurant>>, amount: number) {
  const id = crypto.randomUUID();
  return event(r, "expense.recorded", "expense", id, {
    expense: {
      id,
      category: "Rent",
      amount,
      businessDate: "2026-10-05",
      paidFromDrawer: false,
      shiftId: null,
      createdAt: 1,
      voidedAt: null,
    },
  });
}

describe("cross-restaurant isolation", () => {
  it("a host credential cannot be pointed at another restaurant", async () => {
    const { a, b } = await twoRestaurants();
    const secret = a.hostCredential.split(".")[3];
    const spoofed = `cdh1.${b.restaurantId}.${b.hostDeviceId}.${secret}`;
    const res = await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${spoofed}` } });
    expect(res.status).toBe(401);
    await res.arrayBuffer();
  });

  it("events: each host writes only its own ledger; devices read only their own", async () => {
    const { a, b, deviceA, tokenA } = await twoRestaurants();
    const ticketB = crypto.randomUUID();
    await sendEvents(b, [event(b, "ticket.updated", "kitchen_ticket", ticketB, { ticketId: ticketB, status: "pending", revision: 1 })]);
    // A's host posting "B's" sequence numbers only extends A's ledger.
    const ticketA = crypto.randomUUID();
    await sendEvents(a, [event(a, "ticket.updated", "kitchen_ticket", ticketA, { ticketId: ticketA, status: "pending", revision: 1 })]);

    const page = await json(await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceA, tokenA) }));
    const ids = page.events.map((e: { aggregateId: string }) => e.aggregateId);
    expect(ids).toEqual([ticketA]);
    const ledgerB = await env.DB.prepare("SELECT aggregate_id FROM events WHERE restaurant_id = ?1 AND type = 'ticket.updated'")
      .bind(b.restaurantId)
      .all();
    expect(ledgerB.results).toEqual([{ aggregate_id: ticketB }]);
  });

  it("a host cannot register another restaurant's device credential", async () => {
    const { a, b, deviceB, tokenB } = await twoRestaurants();
    const res = await postEvents(a, [
      event(a, "device.paired", "device", deviceB.deviceId, {
        deviceId: deviceB.deviceId,
        role: "waiter",
        name: "stolen",
        credentialHash: await sha256hex(deviceB.credential),
        pairedAt: 1,
      }),
    ]);
    expect(res.status).toBe(400);
    await res.arrayBuffer();
    // A's host reusing B's device id with a fresh credential creates A's own device only.
    a.nextSeq -= 1;
    const mine = `cdd1.${deviceB.deviceId}.${b64urlEncode(crypto.getRandomValues(new Uint8Array(32)))}`;
    await sendEvents(a, [
      event(a, "device.paired", "device", deviceB.deviceId, {
        deviceId: deviceB.deviceId,
        role: "waiter",
        name: "same id, other restaurant",
        credentialHash: await sha256hex(mine),
        pairedAt: 1,
      }),
    ]);
    const rows = await env.DB.prepare("SELECT restaurant_id, name FROM devices WHERE device_id = ?1 ORDER BY name")
      .bind(deviceB.deviceId)
      .all();
    expect(rows.results).toHaveLength(2);
    // B's device keeps working with B's credential, inside B only.
    const page = await json(await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceB, tokenB) }));
    expect(page.latestSequence).toBe(b.nextSeq - 1);
    // A's same-id device is A's: a token signed by B's key does not work on it.
    const sameIdInA = { ...deviceB, credential: mine };
    const res2 = await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(sameIdInA, tokenB) });
    expect(res2.status).toBe(401);
    await res2.arrayBuffer();
  });

  it("device credentials and session tokens are bound to their own restaurant", async () => {
    const { a, b, deviceA, deviceB, tokenA, tokenB } = await twoRestaurants();
    // A's session token on B's device (and vice versa) is refused.
    expect((await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceB, tokenA) })).status).toBe(401);
    expect((await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceA, tokenB) })).status).toBe(401);
    // A token claiming B's restaurant but signed by A's host key is refused on A's device.
    const claims = (await staffToken(a, deviceA)).claims;
    const crossed = await signToken(a.signingKey, { ...claims, rid: b.restaurantId });
    expect((await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceA, crossed) })).status).toBe(401);
    // B's own pair still works.
    expect((await api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(deviceB, tokenB) })).status).toBe(200);
  });

  it("commands: B cannot see or reuse A's command, and A cannot address B", async () => {
    const { a, b, deviceA, deviceB, tokenA, tokenB } = await twoRestaurants();
    const staffA = "staff-waiter";
    const cmd = command(a, deviceA, staffA);
    expect((await api("/v1/device/commands", jsonInit("POST", cmd, deviceHeaders(deviceA, tokenA)))).status).toBe(200);

    // B's device cannot look it up.
    const lookup = await api(`/v1/device/commands/${cmd["commandId"]}`, { headers: deviceHeaders(deviceB, tokenB) });
    expect(lookup.status).toBe(404);
    await lookup.arrayBuffer();
    // A's device sending a command that names B's restaurant is refused.
    const toB = command(b, deviceA, staffA);
    const res = await api("/v1/device/commands", jsonInit("POST", toB, deviceHeaders(deviceA, tokenA)));
    expect(res.status).toBe(403);
    await res.arrayBuffer();
    // B's mailbox never saw A's command: B's host connects and receives nothing.
    const hostB = await connectHost(b);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(hostB.messages.filter((m) => m.t === "command")).toHaveLength(0);
    hostB.close();
  });

  it("reports are computed from the caller's own restaurant only", async () => {
    const { a, b, deviceA } = await twoRestaurants();
    await sendEvents(a, [expense(a, 11100)]);
    await sendEvents(b, [expense(b, 22200)]);
    const owner = (await staffToken(a, deviceA, { sub: "owner-a", role: "owner" })).token;
    const viaDevice = await json(
      await api("/v1/reports/summary?from=2026-10-05&to=2026-10-06", { headers: deviceHeaders(deviceA, owner) }),
    );
    const viaHost = await json(await api("/v1/reports/summary?from=2026-10-05&to=2026-10-06", { headers: hostHeaders(b) }));
    expect(viaDevice.cards.expenses).toBe(11100);
    expect(viaHost.cards.expenses).toBe(22200);
  });

  it("backups and media of B are invisible to A", async () => {
    const { a, b, deviceA } = await twoRestaurants();
    const archive = crypto.getRandomValues(new Uint8Array(1000));
    const digest = await sha256hexBytes(archive);
    const manifest = b64urlEncode(new TextEncoder().encode(JSON.stringify({ hostEpoch: 1 })));
    const put = await api("/v1/host/backups/backup-1", {
      method: "PUT",
      headers: { ...hostHeaders(b), "X-Content-SHA256": digest, "X-Manifest": manifest },
      body: archive,
    });
    expect(put.status).toBe(201);
    await put.arrayBuffer();

    const listA = await json(await api("/v1/host/backups", { headers: hostHeaders(a) }));
    expect(listA.backups).toEqual([]);
    const getA = await api("/v1/host/backups/backup-1", { headers: hostHeaders(a) });
    expect(getA.status).toBe(404);
    await getA.arrayBuffer();
    // Devices have no backup routes at all.
    const deviceTry = await api("/v1/host/backups/backup-1", { headers: { "X-CafeDesk-Device": deviceA.credential } });
    expect(deviceTry.status).toBe(401);
    await deviceTry.arrayBuffer();

    const png = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]);
    const media = await api("/v1/host/media/coffee.png", {
      method: "PUT",
      headers: { ...hostHeaders(b), "Content-Type": "image/png" },
      body: png,
    });
    expect(media.status).toBe(201);
    await media.arrayBuffer();
    const fromA = await api("/v1/device/media/coffee.png", { headers: { "X-CafeDesk-Device": deviceA.credential } });
    expect(fromA.status).toBe(404);
    await fromA.arrayBuffer();
    const keys = await env.BUCKET.list({ prefix: `restaurants/${a.restaurantId}/` });
    expect(keys.objects).toHaveLength(0);
  });

  it("sockets: B's devices never hear A's notifications or host", async () => {
    const { a, b, deviceB, tokenB } = await twoRestaurants();
    const socketB = await openSocket("/v1/device/socket", deviceHeaders(deviceB, tokenB));
    await socketB.next((m) => m.t === "host");
    const hostA = await connectHost(a);
    const t = crypto.randomUUID();
    await sendEvents(a, [event(a, "ticket.updated", "kitchen_ticket", t, { ticketId: t, status: "ready", revision: 1 })]);
    await new Promise((resolve) => setTimeout(resolve, 200));
    expect(socketB.messages.filter((m) => m.t === "host" && m.connected === true)).toHaveLength(0);
    expect(socketB.messages.filter((m) => m.t === "events" && m.latestSequence > 1)).toHaveLength(0);
    socketB.close();
    hostA.close();
    // B's hub never learned about A's host.
    const hubB = env.HUB.get(env.HUB.idFromName(b.restaurantId));
    expect(await hubB.hostConnected()).toBe(false);
  });
});
