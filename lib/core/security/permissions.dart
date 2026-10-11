/// Local roles and permissions. Services call [Actor.require] /
/// [requireApproval] themselves; hiding a button is never the only check.
library;

import '../errors/app_exception.dart';

enum StaffRole {
  owner,
  cashier,
  kitchen,

  /// Takes orders on a paired phone and sends them to the kitchen. Cannot take
  /// payment, refund, give discounts without owner approval, manage staff or
  /// see sales reports.
  waiter;

  static StaffRole parse(String v) =>
      StaffRole.values.firstWhere((r) => r.name == v, orElse: () => throw ValidationException('Unknown role "$v"'));

  String get label => switch (this) {
    StaffRole.owner => 'Admin',
    StaffRole.cashier => 'Cashier',
    StaffRole.kitchen => 'Kitchen',
    StaffRole.waiter => 'Waiter',
  };
}

enum Permission {
  takeOrders,
  checkout,
  viewBills,
  reprint,
  ownShift,
  recordExpense,
  kitchenTickets,
  viewPrintQueue,
  refund,
  manageMenu,
  manageTables,
  manageStaff,
  manageSettings,
  managePrinters,
  viewReports,
  exportData,
  backup,
  restore,
  viewAudit,
  voidExpense,

  /// Line or bill discounts within the cashier limit without approval.
  discount,

  /// Pair, rename and revoke waiter/kitchen devices; connect the cloud relay.
  manageDevices,
}

const Map<StaffRole, Set<Permission>> rolePermissions = {
  StaffRole.owner: {...Permission.values},
  StaffRole.cashier: {
    Permission.takeOrders,
    Permission.checkout,
    Permission.viewBills,
    Permission.reprint,
    Permission.ownShift,
    Permission.recordExpense,
    Permission.viewPrintQueue,
    Permission.kitchenTickets,
    Permission.discount,
  },
  StaffRole.kitchen: {Permission.kitchenTickets},
  StaffRole.waiter: {Permission.takeOrders},
};

/// The signed-in staff member performing an action.
class Actor {
  const Actor({required this.staffId, required this.name, required this.role, this.mustChangePassword = false});

  final String staffId;
  final String name;
  final StaffRole role;

  /// Signed in with a password the owner chose; the app asks for a new one
  /// before anything else.
  final bool mustChangePassword;

  Actor withPasswordChanged() => Actor(staffId: staffId, name: name, role: role);

  bool can(Permission p) => rolePermissions[role]!.contains(p);

  void require(Permission p) {
    if (!can(p)) {
      throw PermissionDeniedException('${role.label} accounts cannot do this (${_describe(p)}).');
    }
  }

  bool get isOwner => role == StaffRole.owner;

  static String _describe(Permission p) => switch (p) {
    Permission.takeOrders => 'take orders',
    Permission.checkout => 'take payment',
    Permission.viewBills => 'view bills',
    Permission.reprint => 'reprint receipts',
    Permission.ownShift => 'open or close shifts',
    Permission.recordExpense => 'record expenses',
    Permission.kitchenTickets => 'use kitchen tickets',
    Permission.viewPrintQueue => 'view print jobs',
    Permission.refund => 'issue refunds',
    Permission.manageMenu => 'edit the menu',
    Permission.manageTables => 'edit tables',
    Permission.manageStaff => 'manage staff',
    Permission.manageSettings => 'change settings',
    Permission.managePrinters => 'configure printers',
    Permission.viewReports => 'view sales reports',
    Permission.exportData => 'export data',
    Permission.backup => 'create backups',
    Permission.restore => 'restore backups',
    Permission.viewAudit => 'view the audit trail',
    Permission.voidExpense => 'void expenses',
    Permission.discount => 'give discounts',
    Permission.manageDevices => 'manage connected devices',
  };
}

/// Proof that an owner entered their password for a specific action. Issued only
/// by AuthService after verifying it; services re-check that [ownerId] is an
/// enabled owner and that the approval is fresh.
class OwnerApproval {
  const OwnerApproval({required this.ownerId, required this.ownerName, required this.issuedAt});

  final String ownerId;
  final String ownerName;
  final DateTime issuedAt;

  static const validity = Duration(minutes: 5);

  bool isFreshAt(DateTime nowUtc) => !nowUtc.isBefore(issuedAt) && nowUtc.difference(issuedAt) <= validity;
}
