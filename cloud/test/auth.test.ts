// Host / device credentials, staff session tokens and role permissions.
import { describe, expect, it } from "vitest";
import { b64urlEncode, sha256hex } from "../src/protocol/canonical";
import {
  api,
  command,
  deviceHeaders,
  event,
  json,
  jsonInit,
  newRestaurant,
  pairDevice,
  sendEvents,
  signToken,
  staffToken,
  type Device,
} from "./helpers";

const probe = (device: Device, token?: string) =>
  api("/v1/device/events?epoch=1&after=0", { headers: deviceHeaders(device, token) });

async function errorOf(res: Response): Promise<{ status: number; code: string }> {
  const body = await json(res);
  return { status: res.status, code: body.error?.code };
}

describe("host credential", () => {
  it("refuses a missing, malformed or wrong credential", async () => {
    const r = await newRestaurant();
    expect(await errorOf(await api("/v1/host/sync-state"))).toEqual({ status: 401, code: "UNAUTHENTICATED" });
    const wrongSecret = `cdh1.${r.restaurantId}.${r.hostDeviceId}.${b64urlEncode(new Uint8Array(32))}`;
    expect(await errorOf(await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${wrongSecret}` } }))).toEqual({
      status: 401,
      code: "UNAUTHENTICATED",
    });
    expect(
      await errorOf(await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${r.hostCredential}x` } })),
    ).toEqual({ status: 401, code: "UNAUTHENTICATED" });
    // A device credential is not a host credential.
    const device = await pairDevice(r);
    expect(await errorOf(await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${device.credential}` } }))).toEqual({
      status: 401,
      code: "UNAUTHENTICATED",
    });
  });
});

describe("device credential", () => {
  it("refuses a wrong secret and a revoked or re-paired device", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const { token } = await staffToken(r, device);
    expect((await probe(device, token)).status).toBe(200);

    const forged: Device = { ...device, credential: `cdd1.${device.deviceId}.${b64urlEncode(new Uint8Array(32))}` };
    expect(await errorOf(await probe(forged, token))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    // Re-pairing replaces the credential: the old one is revoked.
    const newCredential = `cdd1.${device.deviceId}.${b64urlEncode(crypto.getRandomValues(new Uint8Array(32)))}`;
    await sendEvents(r, [
      event(r, "device.paired", "device", device.deviceId, {
        deviceId: device.deviceId,
        role: "waiter",
        name: "waiter phone",
        credentialHash: await sha256hex(newCredential),
        pairedAt: Date.now(),
      }),
    ]);
    expect(await errorOf(await probe(device, token))).toEqual({ status: 401, code: "DEVICE_REVOKED" });
    const repaired: Device = { ...device, credential: newCredential };
    expect((await probe(repaired, token)).status).toBe(200);

    await sendEvents(r, [
      event(r, "device.revoked", "device", device.deviceId, { deviceId: device.deviceId, revokedAt: Date.now() }),
    ]);
    expect(await errorOf(await probe(repaired, token))).toEqual({ status: 401, code: "DEVICE_REVOKED" });
  });
});

describe("staff session token", () => {
  it("refuses expired, forged, tampered, over-long and other-device tokens", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const other = await pairDevice(r);
    const now = Math.floor(Date.now() / 1000);

    expect(await errorOf(await probe(device))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    const expired = await staffToken(r, device, { iat: now - 13 * 3600, exp: now - 3600 });
    expect(await errorOf(await probe(device, expired.token))).toEqual({ status: 401, code: "SESSION_EXPIRED" });

    // Signed by some other key (not the restaurant's host signing key).
    const otherKeys = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as CryptoKeyPair;
    const { claims } = await staffToken(r, device);
    const forged = await signToken(otherKeys.privateKey, claims);
    expect(await errorOf(await probe(device, forged))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    // Claims changed after signing (waiter → owner).
    const valid = await staffToken(r, device);
    const [, , signature] = valid.token.split(".");
    const tampered = `cds1.${b64urlEncode(new TextEncoder().encode(JSON.stringify({ ...valid.claims, role: "owner" })))}.${signature}`;
    expect(await errorOf(await probe(device, tampered))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    const tooLong = await staffToken(r, device, { iat: now, exp: now + 13 * 3600 });
    expect(await errorOf(await probe(device, tooLong.token))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    // A valid token of the other device.
    const othersToken = await staffToken(r, other);
    expect(await errorOf(await probe(device, othersToken.token))).toEqual({ status: 401, code: "UNAUTHENTICATED" });

    // A token from another epoch (before a restore).
    const oldEpoch = await staffToken(r, device, { ep: 2 });
    expect(await errorOf(await probe(device, oldEpoch.token))).toEqual({ status: 401, code: "SESSION_EXPIRED" });

    expect((await probe(device, valid.token)).status).toBe(200);
  });

  it("applies replicated session revocations and staff access changes", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const asha = await staffToken(r, device, { sub: "asha" });
    const ravi = await staffToken(r, device, { sub: "ravi" });
    const meena = await staffToken(r, device, { sub: "meena" });
    for (const t of [asha, ravi, meena]) expect((await probe(device, t.token)).status).toBe(200);

    await sendEvents(r, [
      event(r, "session.revoked", "staff_session", asha.claims.sid, {
        sid: asha.claims.sid,
        staffId: "asha",
        revokedAt: Date.now(),
      }),
      event(r, "staff.access_changed", "staff", "ravi", { staffId: "ravi", role: "waiter", disabled: true }),
      event(r, "staff.access_changed", "staff", "meena", { staffId: "meena", role: "cashier", disabled: false }),
    ]);
    expect(await errorOf(await probe(device, asha.token))).toEqual({ status: 401, code: "SESSION_EXPIRED" });
    expect(await errorOf(await probe(device, ravi.token))).toEqual({ status: 403, code: "STAFF_DISABLED" });
    // Meena's token still says waiter: she must sign in again to get her new role.
    expect(await errorOf(await probe(device, meena.token))).toEqual({ status: 401, code: "SESSION_EXPIRED" });
    const meenaAgain = await staffToken(r, device, { sub: "meena", role: "cashier" });
    expect((await probe(device, meenaAgain.token)).status).toBe(200);
  });
});

describe("roles and identity binding", () => {
  it("enforces the role table for each command action", async () => {
    const r = await newRestaurant();
    const waiterPhone = await pairDevice(r, "waiter");
    const kitchenTablet = await pairDevice(r, "kitchen");
    const waiter = await staffToken(r, waiterPhone, { sub: "w1", role: "waiter" });
    const kitchen = await staffToken(r, kitchenTablet, { sub: "k1", role: "kitchen" });
    const send = (device: Device, token: string, body: Record<string, unknown>) =>
      api("/v1/device/commands", jsonInit("POST", body, deviceHeaders(device, token)));
    const setStatus = (device: Device, staffId: string) =>
      command(r, device, staffId, {
        action: "ticket.set_status",
        aggregateId: "ticket-1",
        expectedRevision: 1,
        payload: { status: "preparing" },
      });

    // Waiter: may place orders, and may send ticket updates (the POS accepts
    // them only when the café has no kitchen).
    expect((await send(waiterPhone, waiter.token, command(r, waiterPhone, "w1"))).status).toBe(200);
    expect((await send(waiterPhone, waiter.token, setStatus(waiterPhone, "w1"))).status).toBe(200);
    // Kitchen: the reverse.
    expect((await send(kitchenTablet, kitchen.token, setStatus(kitchenTablet, "k1"))).status).toBe(200);
    expect(await errorOf(await send(kitchenTablet, kitchen.token, command(r, kitchenTablet, "k1")))).toEqual({
      status: 403,
      code: "FORBIDDEN",
    });
    // Owner on a kitchen tablet: all actions.
    const owner = await staffToken(r, kitchenTablet, { sub: "o1", role: "owner" });
    expect((await send(kitchenTablet, owner.token, command(r, kitchenTablet, "o1"))).status).toBe(200);
  });

  it("refuses a role on the wrong device kind", async () => {
    const r = await newRestaurant();
    const kitchenTablet = await pairDevice(r, "kitchen");
    const waiterOnKitchen = await staffToken(r, kitchenTablet, { role: "waiter" });
    expect(await errorOf(await probe(kitchenTablet, waiterOnKitchen.token))).toEqual({ status: 403, code: "FORBIDDEN" });
  });

  it("refuses commands whose restaurantId, deviceId or staffId do not match the credentials", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const other = await pairDevice(r);
    const { token, claims } = await staffToken(r, device);
    const send = (overrides: Record<string, unknown>) =>
      api("/v1/device/commands", jsonInit("POST", command(r, device, claims.sub, overrides), deviceHeaders(device, token)));
    expect(await errorOf(await send({ restaurantId: crypto.randomUUID() }))).toEqual({ status: 403, code: "FORBIDDEN" });
    expect(await errorOf(await send({ deviceId: other.deviceId }))).toEqual({ status: 403, code: "FORBIDDEN" });
    expect(await errorOf(await send({ staffId: "someone-else" }))).toEqual({ status: 403, code: "FORBIDDEN" });
  });

  it("serves cloud reports to owners and the host only", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const waiter = await staffToken(r, device);
    const owner = await staffToken(r, device, { sub: "o1", role: "owner" });
    const report = (headers: Record<string, string>) =>
      api("/v1/reports/summary?from=2026-10-05&to=2026-10-06", { headers });
    expect(await errorOf(await report(deviceHeaders(device, waiter.token)))).toEqual({ status: 403, code: "FORBIDDEN" });
    expect((await report(deviceHeaders(device, owner.token))).status).toBe(200);
    expect((await report({ Authorization: `Bearer ${r.hostCredential}` })).status).toBe(200);
    expect(await errorOf(await report({}))).toEqual({ status: 401, code: "UNAUTHENTICATED" });
  });
});
