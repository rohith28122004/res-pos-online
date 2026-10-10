import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import 'app_database.steps.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Installation,
    Sequences,
    RestaurantSettings,
    Staff,
    OwnerRecovery,
    TaxProfiles,
    Categories,
    MenuItems,
    ItemVariants,
    ItemModifiers,
    DiningTables,
    Orders,
    OrderLines,
    KitchenTickets,
    KitchenTicketLines,
    Shifts,
    ShiftClosures,
    CashMovements,
    Bills,
    BillLines,
    BillCharges,
    BillTaxComponents,
    Payments,
    Refunds,
    RefundLines,
    RefundCharges,
    RefundTaxComponents,
    RefundPayments,
    Expenses,
    PrinterProfiles,
    PrintJobs,
    PrintAttempts,
    AuditEvents,
    CompletedOperations,
    HostIdentity,
    PairedDevices,
    PairingCodes,
    StaffSessions,
    CommandReceipts,
    HostEvents,
    SyncCheckpoints,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// Bump together with a migration step and a schema dump
  /// (`dart run drift_dev make-migrations`). Never edit an old step.
  static const int latestSchemaVersion = 4;

  @override
  int get schemaVersion => latestSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    onUpgrade: (m, from, to) async {
      if (from > to) {
        throw StateError(
          'This database was created by a newer CaféDesk (schema $from). Install the newer app instead.',
        );
      }
      // Each step only adds; existing rows are never rewritten or wiped.
      await _steps(m, from, to);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static final OnUpgrade _steps = stepByStep(
    // v2: optional guest count on orders/bills, index for order-type reports.
    from1To2: (m, schema) async {
      await m.addColumn(schema.orders, schema.orders.guestCount);
      await m.addColumn(schema.bills, schema.bills.guestCount);
      await m.createIndex(schema.billsTypeDate);
    },
    // v3: email + password sign-in replaces PINs. Old PIN hashes stay in place
    // (unused); accounts from v2 have no password until the owner sets one.
    from2To3: (m, schema) async {
      await m.addColumn(schema.staff, schema.staff.email);
      await m.addColumn(schema.staff, schema.staff.passwordHash);
      await m.addColumn(schema.staff, schema.staff.mustChangePassword);
      await m.createIndex(schema.staffEmail);
    },
    // v4 (CaféDesk Online): connected mode — host identity, paired devices,
    // pairing codes, staff sessions, command receipts, event outbox, sync
    // checkpoints; kitchen tickets get a revision for remote status updates.
    from3To4: (m, schema) async {
      await m.addColumn(schema.kitchenTickets, schema.kitchenTickets.revision);
      await m.createTable(schema.hostIdentity);
      await m.createTable(schema.pairedDevices);
      await m.createTable(schema.pairingCodes);
      await m.createTable(schema.staffSessions);
      await m.createIndex(schema.staffSessionsStaff);
      await m.createIndex(schema.staffSessionsDevice);
      await m.createTable(schema.commandReceipts);
      await m.createIndex(schema.commandReceiptsReceived);
      await m.createTable(schema.hostEvents);
      await m.createIndex(schema.hostEventsEventId);
      await m.createIndex(schema.hostEventsCloudPending);
      await m.createTable(schema.syncCheckpoints);
    },
  );

  /// Allocates the next number of a named sequence. Must run inside the
  /// caller's transaction so a rollback also rolls back the allocation.
  Future<int> nextSequenceValue(String name) async {
    final row = await (select(sequences)..where((s) => s.name.equals(name))).getSingleOrNull();
    final value = row?.nextValue ?? 1;
    await into(sequences).insertOnConflictUpdate(
      SequencesCompanion.insert(name: name, nextValue: value + 1),
    );
    return value;
  }

  Future<int> peekSequenceValue(String name) async {
    final row = await (select(sequences)..where((s) => s.name.equals(name))).getSingleOrNull();
    return row?.nextValue ?? 1;
  }

  Future<void> writeAudit({
    required String id,
    required DateTime at,
    required String action,
    String? actorId,
    String? actorName,
    String? entityType,
    String? entityId,
    Map<String, Object?>? details,
    String? approvedBy,
  }) async {
    await into(auditEvents).insert(
      AuditEventsCompanion.insert(
        id: id,
        at: at.millisecondsSinceEpoch,
        action: action,
        actorId: Value(actorId),
        actorName: Value(actorName),
        entityType: Value(entityType),
        entityId: Value(entityId),
        detailsJson: Value(details == null ? null : jsonEncode(details)),
        approvedBy: Value(approvedBy),
      ),
    );
  }
}

/// Pragmas applied on every connection (drift may open a read pool).
void configureConnection(Database raw) {
  raw.execute('PRAGMA foreign_keys = ON');
  raw.execute('PRAGMA busy_timeout = 5000');
  raw.execute('PRAGMA journal_mode = WAL');
  // FULL: a committed sale must survive a power cut right after checkout.
  raw.execute('PRAGMA synchronous = FULL');
}

/// Opens [file] on a background isolate so queries never block the UI.
QueryExecutor openDatabaseFile(File file) => NativeDatabase.createInBackground(
  file,
  setup: configureConnection,
);

/// In-memory database for tests.
AppDatabase openInMemoryDatabase() => AppDatabase(
  NativeDatabase.memory(
    setup: (raw) {
      raw.execute('PRAGMA foreign_keys = ON');
    },
  ),
);
