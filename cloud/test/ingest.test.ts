// Event ingest: contiguity, duplicates, content mismatch, gaps, epochs, limits,
// and the device-facing event feed.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { canonicalJson, sha256hex } from "../src/protocol/canonical";
import {
  api,
  deviceHeaders,
  event,
  hostHeaders,
  json,
  jsonInit,
  newRestaurant,
  pairDevice,
  postEvents,
  sendEvents,
  staffToken,
  type Event,
  type Restaurant,
} from "./helpers";

function ticket(r: Restaurant, status = "pending"): Event {
  const id = crypto.randomUUID();
  return event(r, "ticket.updated", "kitchen_ticket", id, { ticketId: id, status, revision: 1 });
}

function menuChanged(r: Restaurant): Event {
  return event(r, "menu.changed", "menu", "menu", {});
}

function expense(r: Restaurant, amount = 15000): Event {
  const id = crypto.randomUUID();
  return event(r, "expense.recorded", "expense", id, {
    expense: {
      id,
      category: "Milk & dairy",
      amount,
      note: null,
      createdBy: "s1",
      createdByName: "Asha",
      createdAt: 1_760_000_000_000,
      businessDate: "2026-10-05",
      paidFromDrawer: true,
      shiftId: "shift-1",
      voidedAt: null,
      voidedBy: null,
      voidReason: null,
    },
  });
}

describe("POST /v1/host/events", () => {
  it("opens epoch 1 implicitly, appends contiguous events and acknowledges after commit", async () => {
    const r = await newRestaurant();
    r.nextSeq = 5; // the host's outbox may start later than 1
    const batch = [ticket(r), menuChanged(r), expense(r)];
    const out = await sendEvents(r, batch);
    expect(out).toEqual({ ackedThrough: { hostEpoch: 1, sequence: 7 }, appended: 3, duplicates: 0 });

    const rows = await env.DB.prepare(
      "SELECT sequence, event_id, content_hash, event_json FROM events WHERE restaurant_id = ?1 ORDER BY sequence",
    )
      .bind(r.restaurantId)
      .all<{ sequence: number; event_id: string; content_hash: string; event_json: string }>();
    expect(rows.results.map((x) => x.sequence)).toEqual([5, 6, 7]);
    for (const [i, row] of rows.results.entries()) {
      // The ledger keeps the canonical event; its hash is the contentHash.
      expect(row.event_json).toBe(canonicalJson(batch[i]));
      expect(row.content_hash).toBe(await sha256hex(row.event_json));
    }
    const state = await json(await api("/v1/host/sync-state", { headers: hostHeaders(r) }));
    expect(state).toEqual({ currentEpoch: 1, epochs: [{ epoch: 1, startSequence: 5, nextSequence: 8 }] });
  });

  it("skips identical duplicates (also mixed with new events) and refuses changed content", async () => {
    const r = await newRestaurant();
    const first = [ticket(r), ticket(r)];
    await sendEvents(r, first);

    // Exact resend: a no-op that still acknowledges.
    expect(await sendEvents(r, first)).toEqual({ ackedThrough: { hostEpoch: 1, sequence: 2 }, appended: 0, duplicates: 2 });

    // Resend of seq 2 plus a new seq 3.
    const third = ticket(r);
    expect(await sendEvents(r, [first[1]!, third])).toEqual({
      ackedThrough: { hostEpoch: 1, sequence: 3 },
      appended: 1,
      duplicates: 1,
    });

    // Same (epoch, sequence), different content.
    const changed = { ...first[0]!, payload: { ...first[0]!.payload, status: "ready" } };
    const res = await postEvents(r, [changed]);
    expect(res.status).toBe(409);
    expect((await json(res)).error).toMatchObject({
      code: "CONTENT_MISMATCH",
      details: { hostEpoch: 1, sequence: 1 },
    });
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE restaurant_id = ?1").bind(r.restaurantId).first();
    expect(count).toEqual({ n: 3 });
  });

  it("refuses a reused eventId at a new sequence", async () => {
    const r = await newRestaurant();
    const a = ticket(r);
    await sendEvents(r, [a]);
    const b = { ...ticket(r), eventId: a.eventId };
    const res = await postEvents(r, [b]);
    expect(res.status).toBe(409);
    expect((await json(res)).error.code).toBe("CONTENT_MISMATCH");
  });

  it("reports a gap with the expected next sequence and writes nothing", async () => {
    const r = await newRestaurant();
    await sendEvents(r, [ticket(r), ticket(r)]);
    r.nextSeq = 5;
    const res = await postEvents(r, [ticket(r)]);
    expect(res.status).toBe(409);
    expect((await json(res)).error).toMatchObject({ code: "GAP", details: { expectedNext: 3 } });
    const state = await json(await api("/v1/host/sync-state", { headers: hostHeaders(r) }));
    expect(state.epochs[0].nextSequence).toBe(3);
  });

  it("refuses a batch that is not consecutive inside itself", async () => {
    const r = await newRestaurant();
    const a = ticket(r);
    r.nextSeq += 1;
    const c = ticket(r);
    const res = await postEvents(r, [a, c]);
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("VALIDATION");
  });

  it("changes epoch only through POST /v1/host/epoch and quarantines the old one", async () => {
    const r = await newRestaurant();
    await sendEvents(r, [ticket(r), ticket(r), ticket(r)]);

    // A batch for epoch 2 before it is opened.
    const early = await postEvents(r, [{ ...ticket(r), hostEpoch: 2 }], 2);
    expect(early.status).toBe(409);
    expect((await json(early)).error).toMatchObject({ code: "EPOCH_CHANGED", details: { currentEpoch: 1 } });

    // Restore: epoch 2 starts again at sequence 2 (the restored outbox position).
    const open = await api("/v1/host/epoch", jsonInit("POST", { epoch: 2, startSequence: 2, reason: "restore" }, hostHeaders(r)));
    expect(open.status).toBe(200);
    expect(await json(open)).toMatchObject({
      currentEpoch: 2,
      epochs: [
        { epoch: 1, startSequence: 1, nextSequence: 4 },
        { epoch: 2, startSequence: 2, nextSequence: 2 },
      ],
    });
    // Repeating the same request is idempotent; a different start is refused.
    const again = await api("/v1/host/epoch", jsonInit("POST", { epoch: 2, startSequence: 2, reason: "restore" }, hostHeaders(r)));
    expect(again.status).toBe(200);
    await again.arrayBuffer();
    const other = await api("/v1/host/epoch", jsonInit("POST", { epoch: 2, startSequence: 9, reason: "x" }, hostHeaders(r)));
    expect(other.status).toBe(409);
    await other.arrayBuffer();
    const older = await api("/v1/host/epoch", jsonInit("POST", { epoch: 1, startSequence: 1, reason: "x" }, hostHeaders(r)));
    expect(older.status).toBe(409);
    await older.arrayBuffer();

    // Old-epoch events are refused now.
    const stale = await postEvents(r, [{ ...ticket(r), hostEpoch: 1 }], 1);
    expect(stale.status).toBe(409);
    expect((await json(stale)).error).toMatchObject({ code: "EPOCH_CHANGED", details: { currentEpoch: 2 } });

    // New-epoch events start at the declared start sequence; (2, 2) is a new identity.
    r.epoch = 2;
    r.nextSeq = 2;
    expect(await sendEvents(r, [ticket(r)])).toMatchObject({ ackedThrough: { hostEpoch: 2, sequence: 2 }, appended: 1 });
  });

  it("refuses epoch > 1 as the first epoch unless opened explicitly", async () => {
    const r = await newRestaurant();
    r.epoch = 3;
    const res = await postEvents(r, [ticket(r)]);
    expect(res.status).toBe(409);
    expect((await json(res)).error).toMatchObject({ code: "EPOCH_CHANGED", details: { currentEpoch: null } });
  });

  it("validates envelopes, payloads, integers and protocol versions", async () => {
    const r = await newRestaurant();
    const fraction = expense(r);
    (fraction.payload["expense"] as Record<string, unknown>)["amount"] = 150.5;
    r.nextSeq = 1;
    let res = await postEvents(r, [fraction]);
    expect(res.status).toBe(400);
    expect((await json(res)).error.code).toBe("VALIDATION");

    r.nextSeq = 1;
    const wrongAggregate = { ...expense(r), aggregateId: "someone-else" };
    res = await postEvents(r, [wrongAggregate]);
    expect(res.status).toBe(400);
    await res.arrayBuffer();

    r.nextSeq = 1;
    res = await postEvents(r, [{ ...ticket(r), protocolVersion: 2 }]);
    expect(res.status).toBe(426);
    expect((await json(res)).error).toMatchObject({ code: "UPDATE_REQUIRED", details: { min: 1, max: 1 } });

    // Nothing was stored by any refused batch.
    const count = await env.DB.prepare("SELECT COUNT(*) AS n FROM events WHERE restaurant_id = ?1").bind(r.restaurantId).first();
    expect(count).toEqual({ n: 0 });
  });

  it("enforces 500 events and 1 MiB per batch", async () => {
    const r = await newRestaurant();
    const many = Array.from({ length: 501 }, () => menuChanged(r));
    let res = await postEvents(r, many);
    expect(res.status).toBe(413);
    expect((await json(res)).error.code).toBe("TOO_LARGE");

    r.nextSeq = 1;
    const big = Array.from({ length: 5 }, () => event(r, "menu.changed", "menu", "menu", { note: "x".repeat(250_000) }));
    res = await postEvents(r, big);
    expect(res.status).toBe(413);
    await res.arrayBuffer();

    // 500 events is fine, in one transaction.
    r.nextSeq = 1;
    const ok = Array.from({ length: 500 }, () => ticket(r));
    expect(await sendEvents(r, ok)).toMatchObject({ ackedThrough: { hostEpoch: 1, sequence: 500 }, appended: 500 });
  });
});

describe("GET /v1/device/events", () => {
  it("returns device-audience events only, with a cursor that skips cloud-only events", async () => {
    const r = await newRestaurant();
    const waiter = await pairDevice(r, "waiter"); // seq 1 (cloud only)
    const t = ticket(r); // seq 2
    const t2 = ticket(r); // seq 3
    await sendEvents(r, [t, t2, expense(r), expense(r), menuChanged(r), expense(r)]); // 2..7
    const { token } = await staffToken(r, waiter);

    // A full page: `through` stops at the last event returned.
    let res = await api("/v1/device/events?epoch=1&after=0&limit=2", { headers: deviceHeaders(waiter, token) });
    expect(res.status).toBe(200);
    let page = await json(res);
    expect(page.events.map((e: Event) => e.sequence)).toEqual([2, 3]);
    expect(page.events[0]).toEqual(t);
    expect(page).toEqual({ hostEpoch: 1, events: [t, t2], through: 3, latestSequence: 7, snapshotRequired: false });

    // The last page: cloud-only events are skipped and `through` reaches the latest sequence.
    res = await api(`/v1/device/events?epoch=1&after=${page.through}&limit=2`, { headers: deviceHeaders(waiter, token) });
    page = await json(res);
    expect(page.events.map((e: Event) => e.type)).toEqual(["menu.changed"]);
    expect(page.through).toBe(7);

    // A cursor ahead of the cloud (the cloud has not ingested that far yet) keeps its place.
    res = await api("/v1/device/events?epoch=1&after=9", { headers: deviceHeaders(waiter, token) });
    expect(await json(res)).toEqual({ hostEpoch: 1, events: [], through: 9, latestSequence: 7, snapshotRequired: false });

    // A cursor from another epoch needs a snapshot.
    res = await api("/v1/device/events?epoch=7&after=0", { headers: deviceHeaders(waiter, token) });
    expect(await json(res)).toMatchObject({ snapshotRequired: true, events: [], hostEpoch: 1 });

    res = await api("/v1/device/events?epoch=1", { headers: deviceHeaders(waiter, token) });
    expect(res.status).toBe(400);
    await res.arrayBuffer();
  });

  it("passes settings changes (kitchen on/off) to devices", async () => {
    const r = await newRestaurant();
    const waiter = await pairDevice(r, "waiter"); // seq 1 (cloud only)
    const changed = event(r, "settings.changed", "settings", "restaurant", {}); // seq 2
    await sendEvents(r, [changed]);
    const { token } = await staffToken(r, waiter);
    const res = await api("/v1/device/events?epoch=1&after=1", { headers: deviceHeaders(waiter, token) });
    expect((await json(res)).events).toEqual([changed]);
  });
});
