// ignore_for_file: recursive_getters
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../database/app_database.dart' show configureConnection;

part 'client_database.g.dart';

/// One row: which POS this phone is paired with, and how to reach it.
/// The device credential and session tokens are NOT here (secure storage).
@DataClassName('ClientLinkRow')
class ClientLink extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get deviceId => text()();

  /// 'waiter' or 'kitchen'.
  TextColumn get role => text()();
  TextColumn get deviceName => text()();
  TextColumn get restaurantId => text()();
  TextColumn get restaurantName => text()();
  TextColumn get hostDeviceId => text()();
  IntColumn get hostEpoch => integer()();
  TextColumn get hostAddressesJson => text()();
  IntColumn get hostPort => integer()();
  TextColumn get certSha256 => text()();
  TextColumn get signingPublicKey => text()();
  TextColumn get sealPublicKey => text()();
  TextColumn get cloudUrl => text().nullable()();
  IntColumn get pairedAt => integer()();

  /// Event cursor: last host epoch/sequence applied to the cache.
  IntColumn get cursorEpoch => integer().withDefault(const Constant(0))();
  IntColumn get cursorSequence => integer().withDefault(const Constant(0))();

  /// When the cache was last confirmed current by the host (LAN or cloud).
  IntColumn get lastLiveAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {singleton};
}

/// The staff member signed in on this phone (token in secure storage).
@DataClassName('ClientSessionRow')
class ClientSessions extends Table {
  IntColumn get singleton => integer().withDefault(const Constant(1)).check(singleton.equals(1))();
  TextColumn get staffId => text()();
  TextColumn get name => text()();
  TextColumn get role => text()();
  IntColumn get expiresAt => integer()();

  @override
  Set<Column> get primaryKey => {singleton};
}

/// Commands created on this phone. The body is stored exactly as first built,
/// so retries over any route send the same command id and body.
@DataClassName('PendingCommandRow')
@TableIndex(name: 'pending_commands_staff_state', columns: {#staffId, #state})
class PendingCommands extends Table {
  TextColumn get commandId => text()();
  TextColumn get staffId => text()();
  TextColumn get action => text()();
  TextColumn get aggregateId => text().nullable()();
  TextColumn get bodyJson => text()();

  /// Short human description ("T4: 2 items").
  TextColumn get summary => text()();

  /// queued → sending → accepted | rejected | needs_review | discarded.
  TextColumn get state => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer().withDefault(const Constant(0))();

  /// 'lan' or 'cloud' (last route tried) and, for the cloud, the mailbox state.
  TextColumn get lastRoute => text().nullable()();
  TextColumn get mailboxState => text().nullable()();
  TextColumn get resultJson => text().nullable()();
  TextColumn get errorCode => text().nullable()();
  TextColumn get errorMessage => text().nullable()();

  @override
  Set<Column> get primaryKey => {commandId};
}

/// An order being put together on this phone, not yet sent.
@DataClassName('DraftRow')
@TableIndex(name: 'drafts_staff', columns: {#staffId})
class Drafts extends Table {
  TextColumn get id => text()();
  TextColumn get staffId => text()();

  /// 'dine_in' or 'takeaway'.
  TextColumn get orderType => text()();
  TextColumn get tableId => text().nullable()();
  TextColumn get tableLabel => text().nullable()();

  /// Set when adding to an order the POS already accepted.
  TextColumn get orderId => text().nullable()();
  IntColumn get guestCount => integer().nullable()();
  TextColumn get linesJson => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Cached read data from the host: `menu`, `tables`, `order:<id>`,
/// `ticket:<id>`, plus snapshot metadata.
@DataClassName('CacheEntryRow')
@TableIndex(name: 'cache_entries_kind', columns: {#kind})
class CacheEntries extends Table {
  TextColumn get key => text()();
  TextColumn get kind => text()();
  TextColumn get json => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Kitchen tickets that already sounded the alarm on this device.
@DataClassName('TicketAlertRow')
class TicketAlerts extends Table {
  TextColumn get ticketId => text()();
  IntColumn get alertedAt => integer()();

  /// False when recorded silently (already on the board when first loaded).
  BoolColumn get sounded => boolean()();

  @override
  Set<Column> get primaryKey => {ticketId};
}

@DriftDatabase(tables: [ClientLink, ClientSessions, PendingCommands, Drafts, CacheEntries, TicketAlerts])
class ClientDatabase extends _$ClientDatabase {
  ClientDatabase(super.executor);

  static const int latestSchemaVersion = 1;

  @override
  int get schemaVersion => latestSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from > to) {
        throw StateError('This device data was created by a newer CaféDesk Online. Install the newer app instead.');
      }
      // Version 1 is the first schema. With version 2, run
      // `dart run drift_dev make-migrations` and add a `stepByStep(from1To2: …)`.
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

ClientDatabase openClientDatabase(File file) =>
    ClientDatabase(NativeDatabase.createInBackground(file, setup: configureConnection));

ClientDatabase openInMemoryClientDatabase() => ClientDatabase(NativeDatabase.memory(setup: configureConnection));
