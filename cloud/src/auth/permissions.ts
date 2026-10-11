// Roles and what they may do remotely (docs/PROTOCOL.md §3.3).

import { ApiError } from "../http/errors";
import type { CommandAction, DeviceKind, StaffRole } from "../protocol/constants";

const ALL_ACTIONS: readonly CommandAction[] = [
  "order.place",
  "order.add",
  "order.change_quantity",
  "order.send_to_kitchen",
  "ticket.set_status",
];

const ROLE_ACTIONS: Record<StaffRole, ReadonlySet<CommandAction>> = {
  owner: new Set(ALL_ACTIONS),
  cashier: new Set(ALL_ACTIONS),
  // ticket.set_status: only when the café has no kitchen (waiters prepare
  // orders). The POS knows that setting and refuses it otherwise.
  waiter: new Set<CommandAction>([
    "order.place",
    "order.add",
    "order.change_quantity",
    "order.send_to_kitchen",
    "ticket.set_status",
  ]),
  kitchen: new Set<CommandAction>(["ticket.set_status"]),
};

const ROLE_DEVICE_KINDS: Record<StaffRole, ReadonlySet<DeviceKind>> = {
  owner: new Set<DeviceKind>(["waiter", "kitchen"]),
  cashier: new Set<DeviceKind>(["waiter", "kitchen"]),
  waiter: new Set<DeviceKind>(["waiter"]),
  kitchen: new Set<DeviceKind>(["kitchen"]),
};

const ROLE_SNAPSHOT_SCOPES: Record<StaffRole, ReadonlySet<DeviceKind>> = {
  owner: new Set<DeviceKind>(["waiter", "kitchen"]),
  cashier: new Set<DeviceKind>(["waiter", "kitchen"]),
  waiter: new Set<DeviceKind>(["waiter"]),
  kitchen: new Set<DeviceKind>(["kitchen"]),
};

/** A role may only be used on the device kinds listed for it. */
export function requireRoleFitsDevice(role: StaffRole, deviceKind: DeviceKind): void {
  if (!ROLE_DEVICE_KINDS[role].has(deviceKind)) {
    throw new ApiError("FORBIDDEN", `The ${role} role cannot be used on a ${deviceKind} device`);
  }
}

export function requireActionAllowed(role: StaffRole, action: CommandAction): void {
  if (!ROLE_ACTIONS[role].has(action)) {
    throw new ApiError("FORBIDDEN", `The ${role} role may not send ${action}`, { action });
  }
}

export function requireSnapshotScope(role: StaffRole, scope: DeviceKind): void {
  if (!ROLE_SNAPSHOT_SCOPES[role].has(scope)) {
    throw new ApiError("FORBIDDEN", `The ${role} role may not read the ${scope} snapshot`, { scope });
  }
}

/** Cloud reports: owner sessions only (the host credential is checked separately). */
export function requireReportsRole(role: StaffRole): void {
  if (role !== "owner") throw new ApiError("FORBIDDEN", "Only owners can read cloud reports");
}
