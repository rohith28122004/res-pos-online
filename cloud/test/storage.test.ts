// Private R2 backups (SHA-256 verified, manifest in D1) and menu media.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { b64urlDecode, b64urlEncode, sha256hexBytes } from "../src/protocol/canonical";
import { api, hostHeaders, json, newRestaurant, pairDevice } from "./helpers";

const manifestHeader = (m: unknown) => b64urlEncode(new TextEncoder().encode(JSON.stringify(m)));

describe("encrypted backups", () => {
  it("stores a verified archive privately under the restaurant and serves it back", async () => {
    const r = await newRestaurant();
    const archive = crypto.getRandomValues(new Uint8Array(4096));
    const sha = await sha256hexBytes(archive);
    const manifest = { hostEpoch: 1, schemaVersion: 4, createdAt: 1760000000000, cipher: "A256GCM" };
    const put = await api("/v1/host/backups/b-2026-10-11", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": sha.toUpperCase(), "X-Manifest": manifestHeader(manifest) },
      body: archive,
    });
    expect(put.status).toBe(201);
    expect(await json(put)).toMatchObject({ created: true, backup: { backupId: "b-2026-10-11", sha256: sha, size: 4096, manifest } });

    const object = await env.BUCKET.get(`restaurants/${r.restaurantId}/backups/b-2026-10-11.cdenc`);
    expect(object).not.toBeNull();
    expect(new Uint8Array(await object!.arrayBuffer())).toEqual(archive);

    const list = await json(await api("/v1/host/backups", { headers: hostHeaders(r) }));
    expect(list.backups).toHaveLength(1);

    const get = await api("/v1/host/backups/b-2026-10-11", { headers: hostHeaders(r) });
    expect(get.status).toBe(200);
    expect(get.headers.get("X-Content-SHA256")).toBe(sha);
    expect(JSON.parse(new TextDecoder().decode(b64urlDecode(get.headers.get("X-Manifest")!)!))).toEqual(manifest);
    expect(new Uint8Array(await get.arrayBuffer())).toEqual(archive);

    // Same id + same hash again: idempotent. Same id + other content: refused.
    const again = await api("/v1/host/backups/b-2026-10-11", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": sha, "X-Manifest": manifestHeader(manifest) },
      body: archive,
    });
    expect(again.status).toBe(200);
    expect((await json(again)).created).toBe(false);
    const other = crypto.getRandomValues(new Uint8Array(10));
    const conflict = await api("/v1/host/backups/b-2026-10-11", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": await sha256hexBytes(other), "X-Manifest": manifestHeader({}) },
      body: other,
    });
    expect(conflict.status).toBe(409);
    await conflict.arrayBuffer();
  });

  it("rejects a body that does not match X-Content-SHA256 and stores nothing", async () => {
    const r = await newRestaurant();
    const archive = crypto.getRandomValues(new Uint8Array(2048));
    const wrong = await sha256hexBytes(new Uint8Array([1, 2, 3]));
    const res = await api("/v1/host/backups/b1", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": wrong, "X-Manifest": manifestHeader({ hostEpoch: 1 }) },
      body: archive,
    });
    expect(res.status).toBe(400);
    const error = (await json(res)).error;
    expect(error.code).toBe("VALIDATION");
    expect(error.details).toEqual({ expected: wrong, actual: await sha256hexBytes(archive) });
    expect(await env.BUCKET.head(`restaurants/${r.restaurantId}/backups/b1.cdenc`)).toBeNull();
    expect((await json(await api("/v1/host/backups", { headers: hostHeaders(r) }))).backups).toEqual([]);
  });

  it("requires the headers and enforces the size limit", async () => {
    const r = await newRestaurant();
    const body = new Uint8Array(16);
    const noSha = await api("/v1/host/backups/b2", { method: "PUT", headers: { ...hostHeaders(r), "X-Manifest": manifestHeader({}) }, body });
    expect(noSha.status).toBe(400);
    await noSha.arrayBuffer();
    const badManifest = await api("/v1/host/backups/b2", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": await sha256hexBytes(body), "X-Manifest": "not-json" },
      body,
    });
    expect(badManifest.status).toBe(400);
    await badManifest.arrayBuffer();
    // The test configuration sets MAX_BACKUP_BYTES to 1 MiB.
    const big = new Uint8Array(1024 * 1024 + 1);
    const tooBig = await api("/v1/host/backups/b3", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": await sha256hexBytes(big), "X-Manifest": manifestHeader({}) },
      body: big,
    });
    expect(tooBig.status).toBe(413);
    expect((await json(tooBig)).error.code).toBe("TOO_LARGE");
    const badId = await api("/v1/host/backups/..%2Fother", {
      method: "PUT",
      headers: { ...hostHeaders(r), "X-Content-SHA256": await sha256hexBytes(body), "X-Manifest": manifestHeader({}) },
      body,
    });
    expect(badId.status).toBe(400);
    await badId.arrayBuffer();
  });
});

describe("menu media", () => {
  it("lets the host upload, list and delete, and the restaurant's devices download", async () => {
    const r = await newRestaurant();
    const device = await pairDevice(r);
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
    const put = await api("/v1/host/media/item-coffee.jpg", {
      method: "PUT",
      headers: { ...hostHeaders(r), "Content-Type": "image/jpeg", "X-Content-SHA256": await sha256hexBytes(jpeg) },
      body: jpeg,
    });
    expect(put.status).toBe(201);
    await put.arrayBuffer();

    const wrongType = await api("/v1/host/media/item-tea.jpg", {
      method: "PUT",
      headers: { ...hostHeaders(r), "Content-Type": "text/html" },
      body: jpeg,
    });
    expect(wrongType.status).toBe(400);
    await wrongType.arrayBuffer();

    const list = await json(await api("/v1/host/media", { headers: hostHeaders(r) }));
    expect(list.media).toMatchObject([{ name: "item-coffee.jpg", size: 7 }]);

    const get = await api("/v1/device/media/item-coffee.jpg", { headers: { "X-CafeDesk-Device": device.credential } });
    expect(get.status).toBe(200);
    expect(get.headers.get("Content-Type")).toBe("image/jpeg");
    expect(new Uint8Array(await get.arrayBuffer())).toEqual(jpeg);

    const anonymous = await api("/v1/device/media/item-coffee.jpg");
    expect(anonymous.status).toBe(401);
    await anonymous.arrayBuffer();

    const del = await api("/v1/host/media/item-coffee.jpg", { method: "DELETE", headers: hostHeaders(r) });
    expect(del.status).toBe(200);
    await del.arrayBuffer();
    const gone = await api("/v1/device/media/item-coffee.jpg", { headers: { "X-CafeDesk-Device": device.credential } });
    expect(gone.status).toBe(404);
    await gone.arrayBuffer();
  });
});
