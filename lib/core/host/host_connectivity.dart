import 'dart:async';
import 'dart:io';

import '../database/app_database.dart';
import '../security/secret_store.dart';
import '../service_context.dart';
import 'approvals.dart';
import 'cloud_connector.dart';
import 'command_dispatcher.dart';
import 'host_api.dart';
import 'host_keys.dart';
import 'lan_server.dart';

/// Whether this platform may serve phones. The POS host is a Windows PC
/// (CONNECTED_BUILD_SPEC §3); an Android POS stays a standalone till.
bool get platformCanHost => Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST');

/// A snapshot of the POS host's connections, for status displays.
class HostStatus {
  const HostStatus({
    this.lanRunning = false,
    this.liveDevices = 0,
    this.problem,
    this.cloudEnrolled = false,
    this.cloudConnected = false,
  });

  final bool lanRunning;

  /// Phones and kitchen displays with a live connection over the café Wi-Fi.
  final int liveDevices;
  final String? problem;
  final bool cloudEnrolled;
  final bool cloudConnected;

  /// Nothing is set up: this PC is a standalone till.
  bool get standalone => !lanRunning && problem == null && !cloudEnrolled;
}

/// Runs the POS host's LAN server and cloud connector while the POS is open.
/// Closing the app stops them: phones then show "POS not reachable".
class HostConnectivity {
  HostConnectivity(this.ctx, this.secrets);

  final ServiceContext ctx;
  final SecretStore secrets;

  HostApi? _api;
  LanServer? _lan;
  CloudConnector? _cloud;
  StreamSubscription<CloudStatus>? _cloudSub;
  String? _lanError;
  bool _started = false;
  final _changes = StreamController<void>.broadcast();

  AppDatabase get _db => ctx.db;

  HostApi? get api => _api;
  LanServer? get lan => _lan;
  CloudConnector? get cloud => _cloud;
  bool get lanRunning => _lan?.running ?? false;

  /// Why the LAN server is not running when it should be (port in use,
  /// missing keys, restore pending…), in plain words.
  String? get lanError => _lanError;

  /// Fires when the server starts or stops, a device connects or disconnects,
  /// or the cloud connection changes.
  Stream<void> get changes => _changes.stream;

  HostStatus get status {
    final cloud = _cloud?.currentStatus;
    return HostStatus(
      lanRunning: lanRunning,
      liveDevices: _lan?.connectedSockets ?? 0,
      problem: _lanError,
      cloudEnrolled: cloud?.enrolled ?? false,
      cloudConnected: cloud?.socketConnected ?? false,
    );
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _lanError = null;
    final identity = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (identity == null || !platformCanHost) {
      _changed();
      return;
    }
    if (identity.reconcileRequired) {
      _lanError = 'This POS was restored from a backup. Reconnect devices in Settings → Connected devices.';
      _changed();
      return;
    }
    final keys = await HostKeys.load(identity.hostDeviceId, identity.tlsCertPem, secrets);
    if (keys == null) {
      _lanError = 'The security keys for device connections are missing on this PC. Reset device connections.';
      _changed();
      return;
    }
    final api = HostApi(
      ctx: ctx,
      keys: keys,
      dispatcher: CommandDispatcher(ctx, approvals: ApprovalRegistry(ctx.clock)),
    );
    _api = api;
    if (identity.lanEnabled) {
      final lan = LanServer(api)..onSocketsChanged = _changed;
      try {
        await lan.start(port: identity.lanPort);
        _lan = lan;
      } on SocketException catch (e) {
        _lanError =
            'Could not open port ${identity.lanPort} for phones (${e.osError?.message ?? e.message}). '
            'Another program may be using it; choose another port.';
      }
    }
    if (identity.cloudUrl != null) {
      final cloud = CloudConnector(api: api, secrets: secrets);
      _cloud = cloud;
      _cloudSub = cloud.status.listen((_) => _changed());
      await cloud.start();
    }
    _changed();
  }

  Future<void> stop() async {
    _started = false;
    await _lan?.stop();
    _lan = null;
    await _cloudSub?.cancel();
    _cloudSub = null;
    await _cloud?.dispose();
    _cloud = null;
    _api = null;
    _changed();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  Future<void> dispose() async {
    await stop();
    await _changes.close();
  }
}
