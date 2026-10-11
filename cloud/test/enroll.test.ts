// Enrollment: single-use, expiring, hashed codes; rate limit; host credential.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { sha256hex } from "../src/protocol/canonical";
import { api, enrollBody, freshIp, hostHeaders, issueCode, json, jsonInit, newRestaurant } from "./helpers";

describe("GET /v1/health", () => {
  it("reports the supported protocol versions", async () => {
    const res = await api("/v1/health");
    expect(res.status).toBe(200);
    expect(await json(res)).toEqual({ ok: true, minProtocolVersion: 1, maxProtocolVersion: 1 });
  });
});

describe("POST /v1/enroll", () => {
  it("creates the restaurant and returns a host credential whose hash alone is stored", async () => {
    const code = await issueCode();
    const { body } = await enrollBody(code);
    const res = await api("/v1/enroll", jsonInit("POST", body, { "CF-Connecting-IP": freshIp() }));
    expect(res.status).toBe(201);
    const out = await json(res);
    expect(out.restaurantId).toBe(body.restaurantId); // the host's own ID is kept
    expect(out.hostCredential).toMatch(new RegExp(`^cdh1\\.${out.restaurantId}\\.${body.hostDeviceId}\\.[A-Za-z0-9_-]{43}$`));

    const stored = await env.DB.prepare("SELECT * FROM credentials WHERE restaurant_id = ?1").bind(out.restaurantId).all();
    expect(stored.results).toHaveLength(1);
    expect(stored.results[0]!["credential_hash"]).toBe(await sha256hex(out.hostCredential));
    expect(JSON.stringify(stored.results)).not.toContain(out.hostCredential.split(".")[3]);

    const restaurant = await env.DB.prepare("SELECT name, host_device_id, current_epoch FROM restaurants WHERE id = ?1")
      .bind(out.restaurantId)
      .first();
    expect(restaurant).toEqual({ name: "Test Café", host_device_id: body.hostDeviceId, current_epoch: null });

    // The credential works.
    const state = await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${out.hostCredential}` } });
    expect(state.status).toBe(200);
    expect(await json(state)).toEqual({ currentEpoch: null, epochs: [] });
  });

  it("accepts a code typed in lower case with spaces, and only once", async () => {
    const code = await issueCode();
    const typed = code.toLowerCase().replace(/-/g, " ");
    const first = await api("/v1/enroll", jsonInit("POST", (await enrollBody(typed)).body, { "CF-Connecting-IP": freshIp() }));
    expect(first.status).toBe(201);
    const second = await api("/v1/enroll", jsonInit("POST", (await enrollBody(code)).body, { "CF-Connecting-IP": freshIp() }));
    expect(second.status).toBe(401);
    expect((await json(second)).error).toMatchObject({ code: "UNAUTHENTICATED", retryable: false });
  });

  it("refuses an expired code and an unknown code", async () => {
    const expired = await issueCode({ now: Date.now() - 7_200_000, expiresInMs: 3_600_000 });
    const res = await api("/v1/enroll", jsonInit("POST", (await enrollBody(expired)).body, { "CF-Connecting-IP": freshIp() }));
    expect(res.status).toBe(401);
    const unknown = await api(
      "/v1/enroll",
      jsonInit("POST", (await enrollBody("ABCD-EFGH-JKMN-PQRS")).body, { "CF-Connecting-IP": freshIp() }),
    );
    expect(unknown.status).toBe(401);
    // Nothing was created for either attempt.
    const used = await env.DB.prepare("SELECT used_at FROM enrollment_codes WHERE used_at IS NOT NULL AND expires_at < ?1")
      .bind(Date.now())
      .all();
    expect(used.results).toHaveLength(0);
  });

  it("never attaches a second host to an existing restaurant (409 CONFLICT, code not consumed)", async () => {
    const r = await newRestaurant();
    const code = await issueCode();
    const { body } = await enrollBody(code);
    const res = await api(
      "/v1/enroll",
      jsonInit("POST", { ...body, restaurantId: r.restaurantId }, { "CF-Connecting-IP": freshIp() }),
    );
    expect(res.status).toBe(409);
    expect((await json(res)).error).toMatchObject({ code: "CONFLICT", details: { restaurantId: r.restaurantId } });
    // Only the original host credential and keys exist for that restaurant.
    const creds = await env.DB.prepare("SELECT COUNT(*) AS n FROM credentials WHERE restaurant_id = ?1")
      .bind(r.restaurantId)
      .first();
    expect(creds).toEqual({ n: 1 });
    const keys = await env.DB.prepare("SELECT signing_public_key FROM host_keys WHERE restaurant_id = ?1")
      .bind(r.restaurantId)
      .first();
    expect(keys).toEqual({ signing_public_key: r.signingPublicKey });
    // The code is still usable for a new restaurant.
    const ok = await api("/v1/enroll", jsonInit("POST", body, { "CF-Connecting-IP": freshIp() }));
    expect(ok.status).toBe(201);
    await ok.arrayBuffer();
    // Without a valid code the caller learns nothing about the restaurant.
    const noCode = await api(
      "/v1/enroll",
      jsonInit("POST", { ...(await enrollBody("ABCD-EFGH-JKMN-PQRS")).body, restaurantId: r.restaurantId }, {
        "CF-Connecting-IP": freshIp(),
      }),
    );
    expect(noCode.status).toBe(401);
    await noCode.arrayBuffer();
  });

  it("rate-limits attempts per client address", async () => {
    const ip = freshIp();
    const statuses: number[] = [];
    for (let i = 0; i < 6; i++) {
      const res = await api("/v1/enroll", jsonInit("POST", (await enrollBody("ABCD-EFGH-JKMN-PQRS")).body, { "CF-Connecting-IP": ip }));
      statuses.push(res.status);
      if (res.status === 429) {
        const body = await json(res);
        expect(body.error.code).toBe("RATE_LIMITED");
        expect(body.error.retryable).toBe(true);
        expect(body.error.details.retryAfterMs).toBeGreaterThan(0);
        expect(res.headers.get("Retry-After")).not.toBeNull();
      } else {
        await res.arrayBuffer();
      }
    }
    expect(statuses).toEqual([401, 401, 401, 401, 401, 429]);
    // Even a valid code is refused while limited.
    const code = await issueCode();
    const limited = await api("/v1/enroll", jsonInit("POST", (await enrollBody(code)).body, { "CF-Connecting-IP": ip }));
    expect(limited.status).toBe(429);
  });

  it("validates the request and refuses unsupported protocol versions", async () => {
    const code = await issueCode();
    const { body } = await enrollBody(code);
    const badKey = await api(
      "/v1/enroll",
      jsonInit("POST", { ...body, hostSigningPublicKey: "short" }, { "CF-Connecting-IP": freshIp() }),
    );
    expect(badKey.status).toBe(400);
    expect((await json(badKey)).error.code).toBe("VALIDATION");
    const newer = await api("/v1/enroll", jsonInit("POST", { ...body, protocolVersion: 2 }, { "CF-Connecting-IP": freshIp() }));
    expect(newer.status).toBe(426);
    expect((await json(newer)).error).toMatchObject({ code: "UPDATE_REQUIRED", details: { min: 1, max: 1 } });
    // The code is still unused after refused requests.
    const ok = await api("/v1/enroll", jsonInit("POST", body, { "CF-Connecting-IP": freshIp() }));
    expect(ok.status).toBe(201);
  });
});

describe("POST /v1/host/credential/rotate", () => {
  it("issues a new credential and the old one stops working", async () => {
    const r = await newRestaurant();
    const res = await api("/v1/host/credential/rotate", { method: "POST", headers: hostHeaders(r) });
    expect(res.status).toBe(200);
    const { hostCredential } = await json(res);
    expect(hostCredential).not.toBe(r.hostCredential);
    const old = await api("/v1/host/sync-state", { headers: hostHeaders(r) });
    expect(old.status).toBe(401);
    await old.arrayBuffer();
    const fresh = await api("/v1/host/sync-state", { headers: { Authorization: `Bearer ${hostCredential}` } });
    expect(fresh.status).toBe(200);
    await fresh.arrayBuffer();
  });
});
