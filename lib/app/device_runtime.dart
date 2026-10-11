import 'dart:io';

import 'package:meta/meta.dart';

import '../core/security/secret_store.dart';
import '../core/sync/client_database.dart';
import '../core/sync/cloud_route.dart';
import '../core/sync/device_sync.dart';
import '../core/time/business_time.dart';
import 'runtime.dart';

/// A waiter phone or kitchen display: its own small database and the sync
/// engine. It never opens the POS database.
class DeviceRuntime {
  DeviceRuntime._(this.db, this.sync);

  final ClientDatabase db;
  final DeviceSync sync;

  static Future<DeviceRuntime> open(AppPaths paths, {SecretStore? secrets, Clock clock = const SystemClock()}) async {
    final db = openClientDatabase(paths.deviceDatabaseFile);
    await db.customSelect('SELECT 1').get();
    final sync = DeviceSync(
      db: db,
      secrets: secrets ?? SecureSecretStore(),
      clock: clock,
      cloudRouteFactory: (link) => CloudRoute(Uri.parse(link.cloudUrl!)),
    );
    return DeviceRuntime._(db, sync);
  }

  /// Wraps an already-open database and engine (widget tests).
  @visibleForTesting
  factory DeviceRuntime.forTesting(ClientDatabase db, DeviceSync sync) => DeviceRuntime._(db, sync);

  static String get platformName => Platform.operatingSystem;

  Future<void> dispose() async {
    await sync.dispose();
    await db.close();
  }
}
