// The durable command mailbox of one restaurant (docs/PROTOCOL.md §8.1), kept
// in the RestaurantHub's SQLite storage so it survives eviction and hibernation.
//
//   queued ──deliver──▶ delivered ──host result──▶ answered
//     │                    │
//     ├─30 min, never delivered──▶ expired
//     └─(older epoch opened)──────▶ quarantined ◀── delivered, unanswered
//
// A mailbox entry is relay bookkeeping only. Business acceptance exists solely
// as a host result with state "accepted" stored in `result_json`.

import {
  MAILBOX_DELIVERY_TTL_MS,
  MAILBOX_RETENTION_MS,
  type MailboxState,
} from "../protocol/constants";
import type { CommandResult } from "../protocol/schemas";

export type MailboxRow = {
  command_id: string;
  body_hash: string;
  body_json: string;
  device_id: string;
  staff_id: string;
  session_token: string;
  host_epoch: number;
  received_at: number;
  state: MailboxState;
  state_changed_at: number;
  delivered_at: number | null;
  answered_at: number | null;
  result_json: string | null;
};

/** What devices see (never the stored body or session token). */
export interface MailboxView {
  commandId: string;
  mailboxState: MailboxState;
  receivedAt: number;
  deliveredAt: number | null;
  answeredAt: number | null;
  /** Present only when the host answered. */
  result: CommandResult | null;
}

export interface StateChange {
  commandId: string;
  deviceId: string;
}

/**
 * Host errors that are not business outcomes (§4.3/§4.5: not stored in the
 * host's receipt). A mailbox entry answered with one of these may be queued
 * again by resubmitting the identical command, e.g. after signing in again.
 */
const RESUBMITTABLE_ERRORS: ReadonlySet<string> = new Set([
  "UNAUTHENTICATED",
  "SESSION_EXPIRED",
  "DEVICE_REVOKED",
  "FORBIDDEN",
  "STAFF_DISABLED",
  "UPDATE_REQUIRED",
  "RATE_LIMITED",
  "EPOCH_CHANGED",
  "COMMAND_ID_REUSED",
  "INTERNAL",
]);

export function toView(row: MailboxRow): MailboxView {
  return {
    commandId: row.command_id,
    mailboxState: row.state,
    receivedAt: row.received_at,
    deliveredAt: row.delivered_at,
    answeredAt: row.answered_at,
    result: row.result_json === null ? null : (JSON.parse(row.result_json) as CommandResult),
  };
}

export function isResubmittable(row: MailboxRow): boolean {
  if (row.state !== "answered" || row.result_json === null) return false;
  const result = JSON.parse(row.result_json) as CommandResult;
  return result.state === "rejected" && RESUBMITTABLE_ERRORS.has(result.error?.code ?? "");
}

export class Mailbox {
  readonly #sql: SqlStorage;

  constructor(sql: SqlStorage) {
    this.#sql = sql;
    sql.exec(`
      CREATE TABLE IF NOT EXISTS mailbox (
        command_id       TEXT PRIMARY KEY,
        body_hash        TEXT NOT NULL,
        body_json        TEXT NOT NULL,
        device_id        TEXT NOT NULL,
        staff_id         TEXT NOT NULL,
        session_token    TEXT NOT NULL,
        host_epoch       INTEGER NOT NULL,
        received_at      INTEGER NOT NULL,
        state            TEXT NOT NULL CHECK (state IN ('queued','delivered','answered','expired','quarantined')),
        state_changed_at INTEGER NOT NULL,
        delivered_at     INTEGER,
        answered_at      INTEGER,
        result_json      TEXT
      );
      CREATE INDEX IF NOT EXISTS mailbox_state ON mailbox (state, received_at);
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
    `);
  }

  get(commandId: string): MailboxRow | null {
    return this.#sql.exec<MailboxRow>("SELECT * FROM mailbox WHERE command_id = ?", commandId).toArray()[0] ?? null;
  }

  insertQueued(entry: {
    commandId: string;
    bodyHash: string;
    bodyJson: string;
    deviceId: string;
    staffId: string;
    sessionToken: string;
    hostEpoch: number;
    now: number;
  }): MailboxRow {
    // Replaces a resubmittable answered entry (same id, same body).
    this.#sql.exec(
      `INSERT OR REPLACE INTO mailbox
         (command_id, body_hash, body_json, device_id, staff_id, session_token, host_epoch,
          received_at, state, state_changed_at, delivered_at, answered_at, result_json)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'queued', ?, NULL, NULL, NULL)`,
      entry.commandId,
      entry.bodyHash,
      entry.bodyJson,
      entry.deviceId,
      entry.staffId,
      entry.sessionToken,
      entry.hostEpoch,
      entry.now,
      entry.now,
    );
    return this.get(entry.commandId)!;
  }

  /** Commands to (re)send to a freshly connected host, oldest first. */
  pendingForHost(): MailboxRow[] {
    return this.#sql
      .exec<MailboxRow>(
        "SELECT * FROM mailbox WHERE state IN ('queued', 'delivered') ORDER BY received_at, rowid",
      )
      .toArray();
  }

  markDelivered(commandId: string, now: number): void {
    this.#sql.exec(
      `UPDATE mailbox SET state = 'delivered', state_changed_at = ?2, delivered_at = COALESCE(delivered_at, ?2)
        WHERE command_id = ?1 AND state = 'queued'`,
      commandId,
      now,
    );
  }

  /**
   * Stores the host's result. The host is the authority: its answer is kept
   * even for an entry the mailbox had given up on (expired / quarantined).
   * The first answer wins; a repeated answer changes nothing.
   */
  markAnswered(result: CommandResult, now: number): MailboxRow | null {
    const changed = this.#sql
      .exec<{ command_id: string }>(
        `UPDATE mailbox SET state = 'answered', state_changed_at = ?2, answered_at = ?2,
                result_json = ?3, session_token = ''
          WHERE command_id = ?1 AND state <> 'answered'
          RETURNING command_id`,
        result.commandId,
        now,
        JSON.stringify(result),
      )
      .toArray();
    return changed.length > 0 ? this.get(result.commandId) : null;
  }

  /** Queued commands past the 30-minute delivery limit become expired. */
  expireDue(now: number): StateChange[] {
    return this.#sql
      .exec<{ command_id: string; device_id: string }>(
        `UPDATE mailbox SET state = 'expired', state_changed_at = ?1, session_token = ''
          WHERE state = 'queued' AND received_at + ?2 <= ?1
          RETURNING command_id, device_id`,
        now,
        MAILBOX_DELIVERY_TTL_MS,
      )
      .toArray()
      .map((r) => ({ commandId: r.command_id, deviceId: r.device_id }));
  }

  /** A delivered command the host never committed (lookup said 404) and that is past its limit. */
  expireDelivered(commandId: string, now: number): StateChange[] {
    return this.#sql
      .exec<{ command_id: string; device_id: string }>(
        `UPDATE mailbox SET state = 'expired', state_changed_at = ?2, session_token = ''
          WHERE command_id = ?1 AND state = 'delivered'
          RETURNING command_id, device_id`,
        commandId,
        now,
      )
      .toArray()
      .map((r) => ({ commandId: r.command_id, deviceId: r.device_id }));
  }

  /** §8 POST /host/epoch: unanswered commands of older epochs need review. */
  quarantineBefore(epoch: number, now: number): StateChange[] {
    return this.#sql
      .exec<{ command_id: string; device_id: string }>(
        `UPDATE mailbox SET state = 'quarantined', state_changed_at = ?2, session_token = ''
          WHERE state IN ('queued', 'delivered') AND host_epoch < ?1
          RETURNING command_id, device_id`,
        epoch,
        now,
      )
      .toArray()
      .map((r) => ({ commandId: r.command_id, deviceId: r.device_id }));
  }

  /** Results are kept 7 days; unanswered deliveries are dropped after 7 days too. */
  deleteOld(now: number): void {
    this.#sql.exec(
      `DELETE FROM mailbox
        WHERE (state IN ('answered', 'expired', 'quarantined') AND state_changed_at + ?2 <= ?1)
           OR (state = 'delivered' AND received_at + ?2 <= ?1)`,
      now,
      MAILBOX_RETENTION_MS,
    );
  }

  /** When the next expiry or clean-up is due, or null if nothing is pending. */
  nextDeadline(): number | null {
    const row = this.#sql
      .exec<{ next: number | null }>(
        `SELECT MIN(t) AS next FROM (
           SELECT MIN(received_at) + ?1 AS t FROM mailbox WHERE state = 'queued'
           UNION ALL
           SELECT MIN(received_at) + ?2 FROM mailbox WHERE state = 'delivered'
           UNION ALL
           SELECT MIN(state_changed_at) + ?2 FROM mailbox WHERE state IN ('answered', 'expired', 'quarantined')
         )`,
        MAILBOX_DELIVERY_TTL_MS,
        MAILBOX_RETENTION_MS,
      )
      .one();
    return row.next;
  }

  getMeta(key: string): string | null {
    const row = this.#sql.exec<{ value: string }>("SELECT value FROM meta WHERE key = ?", key).toArray()[0];
    return row?.value ?? null;
  }

  setMeta(key: string, value: string): void {
    this.#sql.exec("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)", key, value);
  }
}
