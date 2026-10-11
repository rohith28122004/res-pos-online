// Protocol constants shared by the Worker and the RestaurantHub Durable Object
// (docs/PROTOCOL.md).

export const MIN_PROTOCOL_VERSION = 1;
export const MAX_PROTOCOL_VERSION = 1;

const KIB = 1024;

/** §2: request bodies from devices (and other small requests). */
export const MAX_REQUEST_BYTES = 256 * KIB;
/** §2: event batches from the host. */
export const MAX_EVENT_BATCH_BYTES = 1024 * KIB;
/** §8: events per batch. */
export const MAX_EVENTS_PER_BATCH = 500;
/** §4.4: lines per command. */
export const MAX_LINES_PER_COMMAND = 50;
/** Host → hub WebSocket messages (results, relayed responses). */
export const MAX_HOST_MESSAGE_BYTES = 1024 * KIB;

/** §8.1: the hub waits this long for the host to answer. */
export const HOST_WAIT_MS = 8_000;
/** §8.1: a command not delivered within this time of receivedAt expires. */
export const MAILBOX_DELIVERY_TTL_MS = 30 * 60 * 1000;
/** §8.1: answered / expired / quarantined entries are kept this long. */
export const MAILBOX_RETENTION_MS = 7 * 24 * 60 * 60 * 1000;

/** §3.2: staff session token lifetime (seconds). */
export const SESSION_MAX_LIFETIME_S = 12 * 60 * 60;

/** Enrollment attempts per client address per window. */
export const ENROLL_RATE_LIMIT = 5;
export const ENROLL_RATE_WINDOW_MS = 60_000;

export const STAFF_ROLES = ["owner", "cashier", "waiter", "kitchen"] as const;
export type StaffRole = (typeof STAFF_ROLES)[number];

export const DEVICE_KINDS = ["waiter", "kitchen"] as const;
export type DeviceKind = (typeof DEVICE_KINDS)[number];

export const COMMAND_ACTIONS = [
  "order.place",
  "order.add",
  "order.change_quantity",
  "order.send_to_kitchen",
  "ticket.set_status",
] as const;
export type CommandAction = (typeof COMMAND_ACTIONS)[number];

/** §5.2: event types devices may read (the rest are for the cloud only). */
export const DEVICE_AUDIENCE_EVENT_TYPES = [
  "order.updated",
  "ticket.updated",
  "menu.changed",
  "tables.changed",
  "settings.changed",
] as const;

export const RELAY_KINDS = ["sealed_auth", "snapshot", "command_lookup"] as const;
export type RelayKind = (typeof RELAY_KINDS)[number];

export const MAILBOX_STATES = ["queued", "delivered", "answered", "expired", "quarantined"] as const;
export type MailboxState = (typeof MAILBOX_STATES)[number];
