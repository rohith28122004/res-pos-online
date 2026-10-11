// Request limits, protocol versions and command validation at the edge.
import { describe, expect, it } from "vitest";
import { api, command, deviceHeaders, json, jsonInit, newRestaurant, pairDevice, staffToken } from "./helpers";

async function setup() {
  const r = await newRestaurant();
  const device = await pairDevice(r);
  const { token, claims } = await staffToken(r, device);
  const send = (body: unknown) => api("/v1/device/commands", jsonInit("POST", body, deviceHeaders(device, token)));
  return { r, device, token, staffId: claims.sub, send };
}

describe("limits and versions", () => {
  it("refuses device bodies over 256 KiB with 413 TOO_LARGE", async () => {
    const { r, device, staffId, send } = await setup();
    const big = command(r, device, staffId, { padding: "x".repeat(256 * 1024) });
    const res = await send(big);
    expect(res.status).toBe(413);
    expect((await json(res)).error).toMatchObject({ code: "TOO_LARGE", details: { maxBytes: 262144 } });
  });

  it("refuses more than 50 lines with 413 and accepts 50", async () => {
    const { r, device, staffId, send } = await setup();
    const line = { itemId: "coffee", variantId: null, modifierIds: [], quantity: 1, note: null, expectedUnitPrice: 4500 };
    const payload = (n: number) => ({ orderType: "takeaway", lines: Array.from({ length: n }, () => line), sendToKitchen: true });
    const tooMany = await send(command(r, device, staffId, { payload: payload(51) }));
    expect(tooMany.status).toBe(413);
    expect((await json(tooMany)).error).toMatchObject({ code: "TOO_LARGE", details: { maxLines: 50 } });
    const ok = await send(command(r, device, staffId, { payload: payload(50) }));
    expect(ok.status).toBe(200);
    await ok.arrayBuffer();
  });

  it("answers 426 UPDATE_REQUIRED for unsupported versions and unknown actions", async () => {
    const { r, device, token, staffId, send } = await setup();
    for (const body of [
      command(r, device, staffId, { protocolVersion: 2 }),
      command(r, device, staffId, { protocolVersion: 0 }),
      command(r, device, staffId, { action: "bill.checkout" }),
    ]) {
      const res = await send(body);
      expect(res.status).toBe(426);
      expect((await json(res)).error).toMatchObject({ code: "UPDATE_REQUIRED", details: { min: 1, max: 1 } });
    }
    const relay = await api(
      "/v1/device/requests",
      jsonInit("POST", { protocolVersion: 9, kind: "snapshot", body: { scope: "waiter" } }, deviceHeaders(device, token)),
    );
    expect(relay.status).toBe(426);
    await relay.arrayBuffer();
  });

  it("validates command envelopes and action rules", async () => {
    const { r, device, staffId, send } = await setup();
    const bad: Array<Record<string, unknown>> = [
      { commandId: "has spaces" },
      { issuedAt: 1.5 },
      { aggregateId: "order-1" }, // order.place takes aggregateId null
      { payload: { orderType: "dine_in", lines: [{ itemId: "x", quantity: 100, expectedUnitPrice: 1 }], sendToKitchen: true } },
      { payload: { orderType: "dine_in", lines: [{ itemId: "x", quantity: 1, expectedUnitPrice: 1, note: "n".repeat(141) }], sendToKitchen: true } },
      { action: "order.change_quantity", aggregateId: "order-1", expectedRevision: null, payload: { lineId: "l1", quantity: 1 } },
      { action: "ticket.set_status", aggregateId: "t1", expectedRevision: 2, payload: { status: "pending" } },
    ];
    for (const overrides of bad) {
      const res = await send(command(r, device, staffId, overrides));
      expect(res.status, JSON.stringify(overrides)).toBe(400);
      expect((await json(res)).error.code).toBe("VALIDATION");
    }
    const missingVersion = command(r, device, staffId);
    delete missingVersion["protocolVersion"];
    const res = await send(missingVersion);
    expect(res.status).toBe(400);
    await res.arrayBuffer();
    const notJson = await api("/v1/device/commands", {
      method: "POST",
      headers: { ...deviceHeaders(device, (await staffToken(r, device)).token), "Content-Type": "application/json" },
      body: "{",
    });
    expect(notJson.status).toBe(400);
    await notJson.arrayBuffer();
  });

  it("returns structured errors for unknown routes", async () => {
    const res = await api("/v1/nope");
    expect(res.status).toBe(404);
    expect(await json(res)).toEqual({
      error: { code: "NOT_FOUND", message: "No such route", retryable: false, details: {} },
    });
    expect(res.headers.get("Cache-Control")).toBe("no-store");
  });
});
