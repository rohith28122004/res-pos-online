import '../../features/devices/application/device_service.dart';
import '../database/app_database.dart';
import '../protocol/protocol.dart';
import '../protocol/sealed.dart';
import '../service_context.dart';
import 'approvals.dart';
import 'command_dispatcher.dart';
import 'host_keys.dart';
import 'session_service.dart';
import 'snapshots.dart';

/// Counts failures per client; refuses after [limit] in [window].
class FailureLimiter {
  FailureLimiter({this.limit = 5, this.window = const Duration(minutes: 1)});

  final int limit;
  final Duration window;
  final _failures = <String, List<DateTime>>{};

  Duration? blockedFor(String key, DateTime now) {
    final list = _failures[key]?..removeWhere((t) => now.difference(t) > window);
    if (list == null || list.length < limit) return null;
    return window - now.difference(list.first);
  }

  void fail(String key, DateTime now) => _failures.putIfAbsent(key, () => []).add(now);
  void succeed(String key) => _failures.remove(key);
}

/// Everything the POS host answers to devices, independent of the route: the
/// LAN server and the cloud relay connector both call this, so a request
/// behaves the same whichever way it arrived (docs/PROTOCOL.md).
class HostApi {
  HostApi({
    required this.ctx,
    required this.keys,
    required this.dispatcher,
    HostSessions? sessions,
    DeviceService? devices,
    HostReads? reads,
  }) : sessions = sessions ?? HostSessions(ctx),
       devices = devices ?? DeviceService(ctx),
       reads = reads ?? HostReads(ctx);

  final ServiceContext ctx;
  final HostKeys keys;
  final CommandDispatcher dispatcher;
  final HostSessions sessions;
  final DeviceService devices;
  final HostReads reads;

  ApprovalRegistry get approvals => dispatcher.approvals;
  AppDatabase get _db => ctx.db;

  static const _sealedReplayWindow = Duration(minutes: 10);

  final _limiter = FailureLimiter();
  final _seenRequestIds = <String, DateTime>{};

  Future<HostIdentityRow> identity() async {
    final identity = await _db.select(_db.hostIdentity).getSingleOrNull();
    if (identity == null) {
      throw const ProtocolException(ErrorCode.forbidden, 'This POS is not set up for connected devices');
    }
    if (identity.reconcileRequired) {
      throw const ProtocolException(
        ErrorCode.epochChanged,
        'The POS was restored from a backup. The owner must reconnect devices on the POS first.',
      );
    }
    return identity;
  }

  /// LAN: device credential header + bearer token.
  Future<RemoteCaller> authenticate(String? deviceHeader, String? authorization) async {
    final id = await identity();
    final device = await sessions.authenticateDevice(deviceHeader);
    return sessions.authenticateSession(device, authorization, id);
  }

  /// Cloud relay: the cloud already checked the device credential; the host
  /// checks again that the device exists and is not revoked, and verifies the
  /// session token itself (host-signed, bound to that device).
  Future<(PairedDeviceRow, RemoteCaller?)> authenticateRelayed(String deviceId, String? sessionToken) async {
    final id = await identity();
    final device = await (_db.select(_db.pairedDevices)..where((d) => d.id.equals(deviceId))).getSingleOrNull();
    if (device == null) throw const ProtocolException(ErrorCode.unauthenticated, 'Unknown device');
    if (device.revokedAt != null) {
      throw const ProtocolException(ErrorCode.deviceRevoked, 'This device was removed from the POS. Pair it again.');
    }
    if (sessionToken == null) return (device, null);
    return (device, await sessions.authenticateSession(device, 'Bearer $sessionToken', id));
  }

  void checkLimit(String clientKey) {
    final wait = _limiter.blockedFor(clientKey, ctx.now());
    if (wait != null) {
      throw ProtocolException(
        ErrorCode.rateLimited,
        'Too many attempts. Wait a minute and try again.',
        details: {'retryAfterMs': wait.inMilliseconds},
      );
    }
  }

  Future<Map<String, Object?>> pair(Object? body, {required String clientKey}) async {
    checkLimit(clientKey);
    final id = await identity();
    if (body is! Map) throw const ProtocolException(ErrorCode.validation, 'Expected a JSON object');
    final j = body.cast<String, Object?>();
    final version = j['protocolVersion'];
    if (version is! int || !ProtocolVersion.supported(version)) {
      throw const ProtocolException(
        ErrorCode.updateRequired,
        'Update CaféDesk Online on this device',
        details: {'min': ProtocolVersion.min, 'max': ProtocolVersion.max},
      );
    }
    final PairingResult result;
    try {
      result = await devices.redeem(
        code: requireString(j, 'pairingCode', maxLength: 100),
        deviceName: requireString(j, 'deviceName', maxLength: 40),
        platform: optionalString(j, 'platform', maxLength: 40),
        appVersion: optionalString(j, 'appVersion', maxLength: 40),
      );
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.unauthenticated) _limiter.fail(clientKey, ctx.now());
      rethrow;
    }
    _limiter.succeed(clientKey);
    return {
      'deviceId': result.deviceId,
      'deviceCredential': result.credential,
      'role': result.role,
      'restaurantId': id.restaurantId,
      'hostDeviceId': id.hostDeviceId,
      'hostEpoch': id.hostEpoch,
      'hostSigningPublicKey': id.signingPublicKey,
      'hostSealPublicKey': id.sealPublicKey,
      'cloudUrl': id.cloudUrl,
      'restaurantName': (await ctx.settings()).name,
    };
  }

  /// Opens and runs a sealed request (sign-in or owner approval).
  Future<Map<String, Object?>> sealed(PairedDeviceRow device, Object? sealedBox, {required String clientKey}) async {
    checkLimit(clientKey);
    final id = await identity();
    final req = await Sealed.open(sealedBox, hostSealKey: keys.sealKey, deviceId: device.id);
    final requestId = requireId(req, 'requestId');
    final now = ctx.now();
    _seenRequestIds.removeWhere((_, t) => now.difference(t) > _sealedReplayWindow);
    if (_seenRequestIds.containsKey(requestId)) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This request was already used');
    }
    _seenRequestIds[requestId] = now;
    final email = requireString(req, 'email', maxLength: 254);
    final password = requireString(req, 'password', maxLength: 128);
    try {
      switch (req['kind']) {
        case 'sign_in':
          final s = await sessions.signIn(device, email, password, id, keys);
          _limiter.succeed(clientKey);
          return {
            'sessionToken': s.token,
            'expiresAt': s.expiresAt,
            'staff': {'staffId': s.actor.staffId, 'name': s.actor.name, 'role': s.actor.role.name},
          };
        case 'approve':
          final approval = await sessions.approve(email, password);
          final approvalId = approvals.grant(approval, device.id);
          _limiter.succeed(clientKey);
          return {
            'approvalId': approvalId,
            'ownerName': approval.ownerName,
            'expiresAt': approval.issuedAt.millisecondsSinceEpoch + const Duration(minutes: 5).inMilliseconds,
          };
        default:
          throw const ProtocolException(ErrorCode.validation, 'Unknown sealed request');
      }
    } on ProtocolException catch (e) {
      if (e.code == ErrorCode.unauthenticated) _limiter.fail(clientKey, ctx.now());
      rethrow;
    }
  }

  Future<Map<String, Object?>> snapshot(RemoteCaller caller, String? requested) async {
    final scope = caller.deviceRole == DeviceRole.kitchen ? 'kitchen' : 'waiter';
    if ((requested ?? scope) != scope) {
      throw const ProtocolException(ErrorCode.forbidden, 'This device cannot read that view');
    }
    return reads.snapshot(scope);
  }

  Future<CommandResult> command(RemoteCaller caller, Object? body) => dispatcher.handle(caller, body);

  Future<CommandResult> lookup(RemoteCaller caller, String commandId) async {
    final found = await dispatcher.lookup(caller, commandId);
    if (found == null) throw const ProtocolException(ErrorCode.notFound, 'The POS has no record of this command');
    return found;
  }

  Future<Map<String, Object?>> events(int epoch, int after, {int limit = 200}) =>
      reads.eventsAfter(epoch, after, limit: limit.clamp(1, 500));

  Future<void> signOut(RemoteCaller caller) => sessions.signOut(caller);
}
