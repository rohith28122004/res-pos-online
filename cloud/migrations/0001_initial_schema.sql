-- CaféDesk Online cloud — initial D1 schema (forward-only; never edit once
-- applied, add a new numbered migration instead).
--
-- Conventions
--  * Every row that belongs to a restaurant carries restaurant_id, and every
--    lookup path starts with it. The Worker derives restaurant_id from the
--    authenticated credential row, never from client input.
--  * Money is INTEGER paise. Times are INTEGER UTC epoch milliseconds.
--    Business dates are 'YYYY-MM-DD' strings stamped by the POS host.
--  * Secrets are never stored: credentials and enrollment codes are kept as
--    lower-case hex SHA-256 digests only.

-- ---------------------------------------------------------------------------
-- Restaurants, enrollment and credentials
-- ---------------------------------------------------------------------------

CREATE TABLE restaurants (
  id                      TEXT PRIMARY KEY,
  name                    TEXT NOT NULL,
  host_device_id          TEXT NOT NULL,
  app_version             TEXT NOT NULL,
  -- NULL until epoch 1 is opened (POST /host/epoch or the first event batch).
  current_epoch           INTEGER CHECK (current_epoch IS NULL OR current_epoch >= 1),
  -- Freshness for cloud reports.
  last_event_committed_at INTEGER,
  last_ingested_at        INTEGER,
  created_at              INTEGER NOT NULL
);

-- Single-use, expiring codes issued by the operator (npm run issue-enrollment-code).
CREATE TABLE enrollment_codes (
  code_hash     TEXT PRIMARY KEY,           -- sha256hex(normalized code)
  label         TEXT,
  created_at    INTEGER NOT NULL,
  expires_at    INTEGER NOT NULL,
  used_at       INTEGER,
  restaurant_id TEXT
);
CREATE INDEX enrollment_codes_expires ON enrollment_codes (expires_at);

-- Public keys the host registered at enrollment. The private keys never leave
-- the host's OS secure storage.
CREATE TABLE host_keys (
  restaurant_id      TEXT PRIMARY KEY REFERENCES restaurants (id),
  host_device_id     TEXT NOT NULL,
  signing_public_key TEXT NOT NULL,         -- Ed25519, 32 bytes b64url
  seal_public_key    TEXT NOT NULL,         -- X25519, 32 bytes b64url
  created_at         INTEGER NOT NULL
);

-- Host credentials (issued by the cloud) and device credentials (issued by the
-- host at pairing, replicated through device.paired events).
CREATE TABLE credentials (
  credential_hash TEXT PRIMARY KEY,          -- sha256hex(full credential string)
  kind            TEXT NOT NULL CHECK (kind IN ('host', 'device')),
  restaurant_id   TEXT NOT NULL REFERENCES restaurants (id),
  subject_id      TEXT NOT NULL,             -- host device id or device id
  created_at      INTEGER NOT NULL,
  revoked_at      INTEGER
);
CREATE INDEX credentials_subject ON credentials (restaurant_id, kind, subject_id);

-- Paired waiter / kitchen devices (from device.paired / device.revoked events).
CREATE TABLE devices (
  restaurant_id   TEXT NOT NULL REFERENCES restaurants (id),
  device_id       TEXT NOT NULL,
  role            TEXT NOT NULL CHECK (role IN ('waiter', 'kitchen')),
  name            TEXT NOT NULL,
  credential_hash TEXT NOT NULL,
  paired_at       INTEGER NOT NULL,
  revoked_at      INTEGER,
  updated_at      INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, device_id)
);
CREATE UNIQUE INDEX devices_credential_hash ON devices (credential_hash);

-- Staff sessions the host revoked (session.revoked events).
CREATE TABLE revoked_sessions (
  restaurant_id TEXT NOT NULL REFERENCES restaurants (id),
  session_id    TEXT NOT NULL,
  staff_id      TEXT NOT NULL,
  revoked_at    INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, session_id)
);

-- Latest role / disabled flag per staff member (staff.access_changed events).
CREATE TABLE staff_access (
  restaurant_id TEXT NOT NULL REFERENCES restaurants (id),
  staff_id      TEXT NOT NULL,
  role          TEXT NOT NULL,
  disabled      INTEGER NOT NULL CHECK (disabled IN (0, 1)),
  updated_at    INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, staff_id)
);

-- Fixed-window attempt counters (enrollment).
CREATE TABLE rate_limits (
  bucket       TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count        INTEGER NOT NULL
);
CREATE INDEX rate_limits_window ON rate_limits (window_start);

-- ---------------------------------------------------------------------------
-- Event ledger (immutable)
-- ---------------------------------------------------------------------------

CREATE TABLE epochs (
  restaurant_id  TEXT NOT NULL REFERENCES restaurants (id),
  epoch          INTEGER NOT NULL CHECK (epoch >= 1),
  start_sequence INTEGER NOT NULL CHECK (start_sequence >= 1),
  next_sequence  INTEGER NOT NULL,
  opened_at      INTEGER NOT NULL,
  reason         TEXT,
  PRIMARY KEY (restaurant_id, epoch),
  CHECK (next_sequence >= start_sequence)
);

CREATE TABLE events (
  restaurant_id    TEXT NOT NULL REFERENCES restaurants (id),
  host_epoch       INTEGER NOT NULL,
  sequence         INTEGER NOT NULL,
  event_id         TEXT NOT NULL,
  protocol_version INTEGER NOT NULL,
  type             TEXT NOT NULL,
  aggregate_type   TEXT NOT NULL,
  aggregate_id     TEXT NOT NULL,
  revision         INTEGER NOT NULL,
  committed_at     INTEGER NOT NULL,
  business_date    TEXT,
  -- The event exactly as the host sent it, in canonical JSON;
  -- content_hash = sha256hex(event_json).
  event_json       TEXT NOT NULL,
  content_hash     TEXT NOT NULL,
  ingested_at      INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, host_epoch, sequence)
);
CREATE UNIQUE INDEX events_event_id ON events (restaurant_id, event_id);
CREATE INDEX events_type ON events (restaurant_id, type, host_epoch, sequence);
CREATE INDEX events_aggregate ON events (restaurant_id, aggregate_type, aggregate_id);

-- ---------------------------------------------------------------------------
-- Report projections (rebuildable from the ledger; see src/projections/sql.ts)
-- src_epoch / src_seq identify the event that last wrote the row, so a replay
-- in any order converges on the newest snapshot.
-- ---------------------------------------------------------------------------

CREATE TABLE proj_bills (
  restaurant_id       TEXT NOT NULL,
  id                  TEXT NOT NULL,
  receipt_no          TEXT NOT NULL,
  order_id            TEXT NOT NULL,
  order_no            INTEGER NOT NULL,
  order_type          TEXT NOT NULL,
  business_date       TEXT NOT NULL,
  local_hour          INTEGER NOT NULL,
  created_at          INTEGER NOT NULL,
  shift_id            TEXT NOT NULL,
  item_count          INTEGER NOT NULL,
  items_gross_ex      INTEGER NOT NULL,
  items_discount_ex   INTEGER NOT NULL,
  items_net_ex        INTEGER NOT NULL,
  charges_net_ex      INTEGER NOT NULL,
  tax_total           INTEGER NOT NULL,
  rounding_adjustment INTEGER NOT NULL,
  total               INTEGER NOT NULL,
  change_total        INTEGER NOT NULL,
  src_epoch           INTEGER NOT NULL,
  src_seq             INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_bills_date ON proj_bills (restaurant_id, business_date);

CREATE TABLE proj_bill_lines (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  bill_id       TEXT NOT NULL,
  item_id       TEXT,
  item_name     TEXT NOT NULL,
  variant_name  TEXT,
  category_name TEXT,
  quantity      INTEGER NOT NULL,
  gross_ex      INTEGER NOT NULL,
  discount_ex   INTEGER NOT NULL,
  net_ex        INTEGER NOT NULL,
  tax           INTEGER NOT NULL,
  total         INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_bill_lines_bill ON proj_bill_lines (restaurant_id, bill_id);

CREATE TABLE proj_bill_charges (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  bill_id       TEXT NOT NULL,
  kind          TEXT NOT NULL,
  net_ex        INTEGER NOT NULL,
  tax           INTEGER NOT NULL,
  total         INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_bill_charges_bill ON proj_bill_charges (restaurant_id, bill_id);

CREATE TABLE proj_payments (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  bill_id       TEXT NOT NULL,
  method        TEXT NOT NULL,
  applied       INTEGER NOT NULL,
  tendered      INTEGER NOT NULL,
  change_given  INTEGER NOT NULL,
  business_date TEXT NOT NULL,
  shift_id      TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_payments_bill ON proj_payments (restaurant_id, bill_id);

CREATE TABLE proj_refunds (
  restaurant_id       TEXT NOT NULL,
  id                  TEXT NOT NULL,
  refund_no           TEXT NOT NULL,
  bill_id             TEXT NOT NULL,
  business_date       TEXT NOT NULL,
  local_hour          INTEGER NOT NULL,
  created_at          INTEGER NOT NULL,
  shift_id            TEXT,
  items_gross_ex      INTEGER NOT NULL,
  items_discount_ex   INTEGER NOT NULL,
  items_net_ex        INTEGER NOT NULL,
  charges_net_ex      INTEGER NOT NULL,
  tax_total           INTEGER NOT NULL,
  rounding_adjustment INTEGER NOT NULL,
  total               INTEGER NOT NULL,
  src_epoch           INTEGER NOT NULL,
  src_seq             INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_refunds_date ON proj_refunds (restaurant_id, business_date);
CREATE INDEX proj_refunds_bill ON proj_refunds (restaurant_id, bill_id);

CREATE TABLE proj_refund_lines (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  refund_id     TEXT NOT NULL,
  bill_line_id  TEXT NOT NULL,
  quantity      INTEGER NOT NULL,
  gross_ex      INTEGER NOT NULL,
  discount_ex   INTEGER NOT NULL,
  net_ex        INTEGER NOT NULL,
  tax           INTEGER NOT NULL,
  total         INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_refund_lines_refund ON proj_refund_lines (restaurant_id, refund_id);
CREATE INDEX proj_refund_lines_bill_line ON proj_refund_lines (restaurant_id, bill_line_id);

CREATE TABLE proj_refund_charges (
  restaurant_id  TEXT NOT NULL,
  id             TEXT NOT NULL,
  refund_id      TEXT NOT NULL,
  bill_charge_id TEXT NOT NULL,
  net_ex         INTEGER NOT NULL,
  tax            INTEGER NOT NULL,
  total          INTEGER NOT NULL,
  src_epoch      INTEGER NOT NULL,
  src_seq        INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_refund_charges_refund ON proj_refund_charges (restaurant_id, refund_id);

CREATE TABLE proj_refund_payments (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  refund_id     TEXT NOT NULL,
  method        TEXT NOT NULL,
  amount        INTEGER NOT NULL,
  business_date TEXT NOT NULL,
  shift_id      TEXT,
  created_at    INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_refund_payments_refund ON proj_refund_payments (restaurant_id, refund_id);

CREATE TABLE proj_expenses (
  restaurant_id    TEXT NOT NULL,
  id               TEXT NOT NULL,
  category         TEXT NOT NULL,
  amount           INTEGER NOT NULL,
  business_date    TEXT NOT NULL,
  paid_from_drawer INTEGER NOT NULL,
  shift_id         TEXT,
  created_at       INTEGER NOT NULL,
  voided_at        INTEGER,
  src_epoch        INTEGER NOT NULL,
  src_seq          INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_expenses_date ON proj_expenses (restaurant_id, business_date);

CREATE TABLE proj_cash_movements (
  restaurant_id TEXT NOT NULL,
  id            TEXT NOT NULL,
  shift_id      TEXT NOT NULL,
  direction     TEXT NOT NULL,
  amount        INTEGER NOT NULL,
  business_date TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  src_epoch     INTEGER NOT NULL,
  src_seq       INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_cash_movements_date ON proj_cash_movements (restaurant_id, business_date);

CREATE TABLE proj_shifts (
  restaurant_id  TEXT NOT NULL,
  id             TEXT NOT NULL,
  opened_at      INTEGER NOT NULL,
  opening_float  INTEGER NOT NULL,
  status         TEXT NOT NULL,
  business_date  TEXT NOT NULL,
  last_closed_at INTEGER,
  src_epoch      INTEGER NOT NULL,
  src_seq        INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, id)
);
CREATE INDEX proj_shifts_date ON proj_shifts (restaurant_id, business_date);

CREATE TABLE proj_order_cancellations (
  restaurant_id        TEXT NOT NULL,
  order_id             TEXT NOT NULL,
  order_no             INTEGER NOT NULL,
  order_type           TEXT NOT NULL,
  cancelled_at         INTEGER,
  cancel_business_date TEXT NOT NULL,
  src_epoch            INTEGER NOT NULL,
  src_seq              INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, order_id)
);
CREATE INDEX proj_order_cancellations_date ON proj_order_cancellations (restaurant_id, cancel_business_date);

-- ---------------------------------------------------------------------------
-- Encrypted backups (objects live in R2; this is the manifest index)
-- ---------------------------------------------------------------------------

CREATE TABLE backups (
  restaurant_id TEXT NOT NULL REFERENCES restaurants (id),
  backup_id     TEXT NOT NULL,
  r2_key        TEXT NOT NULL,
  sha256        TEXT NOT NULL,
  size_bytes    INTEGER NOT NULL,
  manifest_json TEXT NOT NULL,
  created_at    INTEGER NOT NULL,
  PRIMARY KEY (restaurant_id, backup_id)
);
CREATE INDEX backups_created ON backups (restaurant_id, created_at);
