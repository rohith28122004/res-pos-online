// POST /v1/host/events — durable, ordered, idempotent event ingest
// (docs/PROTOCOL.md §5, §8).
//
// * Events must be in the restaurant's current epoch and contiguous from the
//   epoch's stored next_sequence. Epoch 1 opens implicitly at the first event's
//   sequence; later epochs are opened with POST /host/epoch.
// * Events below next_sequence are duplicates: identical contentHash → skipped,
//   different → 409 CONTENT_MISMATCH. A jump ahead → 409 GAP {expectedNext}.
// * Ledger rows, device-registry changes and projections are written in ONE D1
//   batch (a transaction). ackedThrough is returned only after it commits.
// * Two concurrent batches cannot both append: the ledger primary key rejects
//   the loser, whose whole batch rolls back; it is re-evaluated from scratch.

import type { HostAuth } from "../auth/credentials";
import { checkProtocolVersion, isPlainObject } from "../http/body";
import { ApiError } from "../http/errors";
import { CanonicalJsonError, canonicalJson, sha256hex } from "../protocol/canonical";
import { DEVICE_AUDIENCE_EVENT_TYPES, MAX_EVENTS_PER_BATCH } from "../protocol/constants";
import {
  DevicePaired,
  DeviceRevoked,
  EventBatch,
  EventEnvelope,
  SessionRevoked,
  StaffAccessChanged,
  parseOrThrow,
  validateEventPayload,
} from "../protocol/schemas";
import { PROJECTION_STATEMENTS } from "../projections/sql";
import { bulkStatements } from "./bulk";

export interface AckedThrough {
  hostEpoch: number;
  sequence: number;
}

export interface IngestOutcome {
  ackedThrough: AckedThrough | null;
  appended: number;
  duplicates: number;
  /** For the RestaurantHub notification after commit. */
  notify: {
    epochOpened: number | null;
    latestSequence: number;
    hostEpoch: number;
    deviceAudience: boolean;
    revokedDevices: string[];
    revokedSessions: string[];
    staffChanged: string[];
  } | null;
}

interface PreparedEvent {
  envelope: EventEnvelope;
  eventJson: string;
  contentHash: string;
}

interface EpochState {
  current_epoch: number | null;
  start_sequence: number | null;
  next_sequence: number | null;
}

const MAX_ATTEMPTS = 3;

const DEVICE_AUDIENCE: ReadonlySet<string> = new Set(DEVICE_AUDIENCE_EVENT_TYPES);

async function prepareEvents(body: unknown): Promise<{ hostEpoch: number; events: PreparedEvent[] }> {
  if (!isPlainObject(body)) throw new ApiError("VALIDATION", "Body must be a JSON object");
  checkProtocolVersion(body["protocolVersion"], false);
  if (Array.isArray(body["events"]) && body["events"].length > MAX_EVENTS_PER_BATCH) {
    throw new ApiError("TOO_LARGE", `At most ${MAX_EVENTS_PER_BATCH} events per batch`, {
      maxEvents: MAX_EVENTS_PER_BATCH,
    });
  }
  const batch = parseOrThrow(EventBatch, body, "event batch");
  // Version first: an unsupported version is refused before anything else.
  for (const raw of batch.events) {
    if (!isPlainObject(raw)) throw new ApiError("VALIDATION", "Every event must be a JSON object");
    checkProtocolVersion(raw["protocolVersion"], true);
  }
  const events: PreparedEvent[] = [];
  for (const raw of batch.events) {
    const envelope = parseOrThrow(EventEnvelope, raw, "event");
    if (envelope.hostEpoch !== batch.hostEpoch) {
      throw new ApiError("VALIDATION", `Event #${envelope.sequence} is not in epoch ${batch.hostEpoch}`);
    }
    validateEventPayload(envelope);
    let eventJson: string;
    try {
      eventJson = canonicalJson(raw);
    } catch (error) {
      if (error instanceof CanonicalJsonError) throw new ApiError("VALIDATION", error.message);
      throw error;
    }
    events.push({ envelope, eventJson, contentHash: await sha256hex(eventJson) });
  }
  const eventIds = new Set<string>();
  events.forEach((event, i) => {
    const previous = events[i - 1];
    if (previous && event.envelope.sequence !== previous.envelope.sequence + 1) {
      throw new ApiError("VALIDATION", "Events in a batch must be in order with consecutive sequences");
    }
    if (eventIds.has(event.envelope.eventId)) {
      throw new ApiError("VALIDATION", `eventId ${event.envelope.eventId} appears twice in the batch`);
    }
    eventIds.add(event.envelope.eventId);
  });
  return { hostEpoch: batch.hostEpoch, events };
}

/** Folds the device-registry events of the appended range, in sequence order. */
function foldRegistry(events: readonly PreparedEvent[]) {
  const paired = new Map<string, DevicePaired & { revokedAt: number | null }>();
  const revoked = new Map<string, number>();
  const sessions: Array<{ sid: string; staffId: string; revokedAt: number }> = [];
  const staff = new Map<string, { staffId: string; role: string; disabled: boolean }>();
  for (const { envelope } of events) {
    switch (envelope.type) {
      case "device.paired": {
        const p = DevicePaired.parse(envelope.payload);
        paired.set(p.deviceId, { ...p, revokedAt: null });
        revoked.delete(p.deviceId);
        break;
      }
      case "device.revoked": {
        const p = DeviceRevoked.parse(envelope.payload);
        const pending = paired.get(p.deviceId);
        if (pending) pending.revokedAt = p.revokedAt;
        else revoked.set(p.deviceId, p.revokedAt);
        break;
      }
      case "session.revoked": {
        const p = SessionRevoked.parse(envelope.payload);
        sessions.push({ sid: p.sid, staffId: p.staffId, revokedAt: p.revokedAt });
        break;
      }
      case "staff.access_changed": {
        const p = StaffAccessChanged.parse(envelope.payload);
        staff.set(p.staffId, { staffId: p.staffId, role: p.role, disabled: p.disabled });
        break;
      }
    }
  }
  const pairedRows = [...paired.values()].map((p) => ({
    deviceId: p.deviceId,
    role: p.role,
    name: p.name,
    credentialHash: p.credentialHash,
    pairedAt: p.pairedAt,
    revokedAt: p.revokedAt,
  }));
  const revokedRows = [...revoked].map(([deviceId, revokedAt]) => ({ deviceId, revokedAt }));
  return { pairedRows, revokedRows, sessions, staffRows: [...staff.values()] };
}

function registryStatements(
  db: D1Database,
  restaurantId: string,
  now: number,
  registry: ReturnType<typeof foldRegistry>,
): D1PreparedStatement[] {
  const { pairedRows, revokedRows, sessions, staffRows } = registry;
  const statements: D1PreparedStatement[] = [];
  if (pairedRows.length > 0) {
    // A re-paired device's previous credential stops working.
    statements.push(
      ...bulkStatements(
        db,
        `UPDATE credentials SET revoked_at = ?2
          WHERE restaurant_id = ?1 AND kind = 'device' AND revoked_at IS NULL
            AND subject_id IN (SELECT json_extract(value, '$.deviceId') FROM json_each(?3))
            AND credential_hash NOT IN (SELECT json_extract(value, '$.credentialHash') FROM json_each(?3))`,
        [restaurantId, now],
        pairedRows,
      ),
      ...bulkStatements(
        db,
        `INSERT INTO credentials (credential_hash, kind, restaurant_id, subject_id, created_at, revoked_at)
         SELECT json_extract(value, '$.credentialHash'), 'device', ?1, json_extract(value, '$.deviceId'), ?2,
                json_extract(value, '$.revokedAt')
           FROM json_each(?3) WHERE true
         ON CONFLICT (credential_hash) DO UPDATE SET revoked_at = excluded.revoked_at
          WHERE credentials.kind = 'device' AND credentials.restaurant_id = excluded.restaurant_id
            AND credentials.subject_id = excluded.subject_id`,
        [restaurantId, now],
        pairedRows,
      ),
      ...bulkStatements(
        db,
        `INSERT INTO devices (restaurant_id, device_id, role, name, credential_hash, paired_at, revoked_at, updated_at)
         SELECT ?1, json_extract(value, '$.deviceId'), json_extract(value, '$.role'), json_extract(value, '$.name'),
                json_extract(value, '$.credentialHash'), json_extract(value, '$.pairedAt'),
                json_extract(value, '$.revokedAt'), ?2
           FROM json_each(?3) WHERE true
         ON CONFLICT (restaurant_id, device_id) DO UPDATE SET
           role = excluded.role, name = excluded.name, credential_hash = excluded.credential_hash,
           paired_at = excluded.paired_at, revoked_at = excluded.revoked_at, updated_at = excluded.updated_at`,
        [restaurantId, now],
        pairedRows,
      ),
    );
  }
  if (revokedRows.length > 0) {
    statements.push(
      ...bulkStatements(
        db,
        `UPDATE devices
            SET revoked_at = (SELECT json_extract(value, '$.revokedAt') FROM json_each(?3)
                               WHERE json_extract(value, '$.deviceId') = devices.device_id),
                updated_at = ?2
          WHERE restaurant_id = ?1
            AND device_id IN (SELECT json_extract(value, '$.deviceId') FROM json_each(?3))`,
        [restaurantId, now],
        revokedRows,
      ),
      ...bulkStatements(
        db,
        `UPDATE credentials SET revoked_at = ?2
          WHERE restaurant_id = ?1 AND kind = 'device' AND revoked_at IS NULL
            AND subject_id IN (SELECT json_extract(value, '$.deviceId') FROM json_each(?3))`,
        [restaurantId, now],
        revokedRows,
      ),
    );
  }
  if (sessions.length > 0) {
    statements.push(
      ...bulkStatements(
        db,
        `INSERT INTO revoked_sessions (restaurant_id, session_id, staff_id, revoked_at)
         SELECT ?1, json_extract(value, '$.sid'), json_extract(value, '$.staffId'), json_extract(value, '$.revokedAt')
           FROM json_each(?2) WHERE true
         ON CONFLICT (restaurant_id, session_id) DO NOTHING`,
        [restaurantId],
        sessions,
      ),
    );
  }
  if (staffRows.length > 0) {
    statements.push(
      ...bulkStatements(
        db,
        `INSERT INTO staff_access (restaurant_id, staff_id, role, disabled, updated_at)
         SELECT ?1, json_extract(value, '$.staffId'), json_extract(value, '$.role'),
                json_extract(value, '$.disabled'), ?2
           FROM json_each(?3) WHERE true
         ON CONFLICT (restaurant_id, staff_id) DO UPDATE SET
           role = excluded.role, disabled = excluded.disabled, updated_at = excluded.updated_at`,
        [restaurantId, now],
        staffRows,
      ),
    );
  }
  return statements;
}

function isConstraintRace(error: unknown): boolean {
  return error instanceof Error && /UNIQUE constraint failed|PRIMARY KEY/i.test(error.message);
}

export async function ingestEvents(db: D1Database, host: HostAuth, body: unknown, now: number): Promise<IngestOutcome> {
  const { hostEpoch, events } = await prepareEvents(body);
  const rid = host.restaurantId;

  for (let attempt = 1; ; attempt++) {
    const state = await db
      .prepare(
        `SELECT r.current_epoch, e.start_sequence, e.next_sequence
           FROM restaurants AS r LEFT JOIN epochs AS e ON e.restaurant_id = r.id AND e.epoch = ?2
          WHERE r.id = ?1`,
      )
      .bind(rid, hostEpoch)
      .first<EpochState>();
    if (!state) throw new ApiError("INTERNAL", "Restaurant row missing");

    // --- epoch -----------------------------------------------------------
    let openImplicitly = false;
    if (state.current_epoch === null) {
      if (hostEpoch !== 1) {
        throw new ApiError("EPOCH_CHANGED", "Open this epoch with POST /v1/host/epoch first", { currentEpoch: null });
      }
      if (events.length === 0) return { ackedThrough: null, appended: 0, duplicates: 0, notify: null };
      openImplicitly = true;
    } else if (hostEpoch !== state.current_epoch) {
      throw new ApiError(
        "EPOCH_CHANGED",
        hostEpoch < state.current_epoch
          ? "This epoch is closed; the cloud already moved to a newer epoch"
          : "Open this epoch with POST /v1/host/epoch first",
        { currentEpoch: state.current_epoch },
      );
    }
    const start = openImplicitly ? events[0]!.envelope.sequence : state.start_sequence!;
    const next = openImplicitly ? start : state.next_sequence!;
    const acked = (through: number): AckedThrough | null =>
      through >= start ? { hostEpoch, sequence: through } : null;

    if (events.length === 0) return { ackedThrough: acked(next - 1), appended: 0, duplicates: 0, notify: null };

    // --- duplicates and gap --------------------------------------------------
    const duplicates = events.filter((e) => e.envelope.sequence < next);
    const fresh = events.filter((e) => e.envelope.sequence >= next);
    if (events[0]!.envelope.sequence < start) {
      throw new ApiError("VALIDATION", `Epoch ${hostEpoch} starts at sequence ${start}`, { startSequence: start });
    }
    if (fresh.length > 0 && fresh[0]!.envelope.sequence !== next) {
      throw new ApiError("GAP", `Expected sequence ${next} next`, { expectedNext: next, hostEpoch });
    }
    if (duplicates.length > 0) {
      const stored = await db
        .prepare(
          `SELECT sequence, content_hash FROM events
            WHERE restaurant_id = ?1 AND host_epoch = ?2 AND sequence BETWEEN ?3 AND ?4`,
        )
        .bind(rid, hostEpoch, duplicates[0]!.envelope.sequence, duplicates[duplicates.length - 1]!.envelope.sequence)
        .all<{ sequence: number; content_hash: string }>();
      const hashes = new Map(stored.results.map((r) => [r.sequence, r.content_hash]));
      for (const event of duplicates) {
        const storedHash = hashes.get(event.envelope.sequence);
        if (storedHash === undefined) throw new ApiError("INTERNAL", "Ledger row missing below next_sequence");
        if (storedHash !== event.contentHash) {
          throw new ApiError("CONTENT_MISMATCH", "An event with this sequence was already stored with other content", {
            hostEpoch,
            sequence: event.envelope.sequence,
            eventId: event.envelope.eventId,
          });
        }
      }
    }
    if (fresh.length === 0) {
      return { ackedThrough: acked(next - 1), appended: 0, duplicates: duplicates.length, notify: null };
    }

    // A new (epoch, sequence) whose eventId is already stored is a different event.
    const clash = await db
      .prepare(
        `SELECT event_id, host_epoch, sequence FROM events
          WHERE restaurant_id = ?1 AND event_id IN (SELECT value FROM json_each(?2)) LIMIT 1`,
      )
      .bind(rid, JSON.stringify(fresh.map((e) => e.envelope.eventId)))
      .first<{ event_id: string; host_epoch: number; sequence: number }>();
    if (clash) {
      throw new ApiError("CONTENT_MISMATCH", "This eventId was already stored for another event", {
        eventId: clash.event_id,
        storedAt: { hostEpoch: clash.host_epoch, sequence: clash.sequence },
      });
    }

    // --- device registry checks ----------------------------------------------
    const registry = foldRegistry(fresh);
    if (registry.pairedRows.length > 0) {
      const owners = await db
        .prepare(
          `SELECT credential_hash, restaurant_id, subject_id, kind FROM credentials
            WHERE credential_hash IN (SELECT value FROM json_each(?1))`,
        )
        .bind(JSON.stringify(registry.pairedRows.map((p) => p.credentialHash)))
        .all<{ credential_hash: string; restaurant_id: string; subject_id: string; kind: string }>();
      for (const owner of owners.results) {
        const row = registry.pairedRows.find((p) => p.credentialHash === owner.credential_hash);
        if (owner.kind !== "device" || owner.restaurant_id !== rid || owner.subject_id !== row?.deviceId) {
          throw new ApiError("VALIDATION", "credentialHash is already registered to another device");
        }
      }
    }

    // --- one transactional batch ---------------------------------------------
    const first = fresh[0]!.envelope.sequence;
    const last = fresh[fresh.length - 1]!.envelope.sequence;
    const statements: D1PreparedStatement[] = [];
    if (openImplicitly) {
      statements.push(
        db
          .prepare(
            `INSERT INTO epochs (restaurant_id, epoch, start_sequence, next_sequence, opened_at, reason)
             VALUES (?1, 1, ?2, ?2, ?3, 'opened by the first event batch')`,
          )
          .bind(rid, start, now),
        db.prepare("UPDATE restaurants SET current_epoch = 1 WHERE id = ?1 AND current_epoch IS NULL").bind(rid),
      );
    }
    statements.push(
      ...bulkStatements(
        db,
        `INSERT INTO events (restaurant_id, host_epoch, sequence, event_id, protocol_version, type, aggregate_type,
                             aggregate_id, revision, committed_at, business_date, event_json, content_hash, ingested_at)
         SELECT ?1, ?2, json_extract(value, '$.sequence'), json_extract(value, '$.eventId'),
                json_extract(value, '$.protocolVersion'), json_extract(value, '$.type'),
                json_extract(value, '$.aggregateType'), json_extract(value, '$.aggregateId'),
                json_extract(value, '$.revision'), json_extract(value, '$.committedAtUtc'),
                json_extract(value, '$.businessDate'), json_extract(value, '$.eventJson'),
                json_extract(value, '$.contentHash'), ?3
           FROM json_each(?4)`,
        [rid, hostEpoch, now],
        fresh.map(({ envelope, eventJson, contentHash }) => ({
          sequence: envelope.sequence,
          eventId: envelope.eventId,
          protocolVersion: envelope.protocolVersion,
          type: envelope.type,
          aggregateType: envelope.aggregateType,
          aggregateId: envelope.aggregateId,
          revision: envelope.revision,
          committedAtUtc: envelope.committedAtUtc,
          businessDate: envelope.businessDate,
          eventJson,
          contentHash,
        })),
      ),
      db
        .prepare(
          `UPDATE epochs SET next_sequence = ?3
            WHERE restaurant_id = ?1 AND epoch = ?2 AND next_sequence = ?4`,
        )
        .bind(rid, hostEpoch, last + 1, next),
      ...registryStatements(db, rid, now, registry),
      ...PROJECTION_STATEMENTS.map((sql) => db.prepare(sql).bind(rid, hostEpoch, first, last)),
      db
        .prepare(
          `UPDATE restaurants
              SET last_ingested_at = ?2,
                  last_event_committed_at = MAX(COALESCE(last_event_committed_at, 0), ?3)
            WHERE id = ?1`,
        )
        .bind(rid, now, Math.max(...fresh.map((e) => e.envelope.committedAtUtc))),
    );

    try {
      await db.batch(statements);
    } catch (error) {
      if (isConstraintRace(error) && attempt < MAX_ATTEMPTS) continue; // a concurrent batch won; re-evaluate
      throw error;
    }

    return {
      ackedThrough: { hostEpoch, sequence: last },
      appended: fresh.length,
      duplicates: duplicates.length,
      notify: {
        epochOpened: openImplicitly ? 1 : null,
        hostEpoch,
        latestSequence: last,
        deviceAudience: fresh.some((e) => DEVICE_AUDIENCE.has(e.envelope.type)),
        // Revoked devices and re-paired ones (their old credential stopped working).
        revokedDevices: [
          ...registry.revokedRows.map((r) => r.deviceId),
          ...registry.pairedRows.map((p) => p.deviceId),
        ],
        revokedSessions: registry.sessions.map((s) => s.sid),
        staffChanged: registry.staffRows.map((s) => s.staffId),
      },
    };
  }
}
