/// CaféDesk Online protocol v1 types (docs/PROTOCOL.md). Shared by the POS
/// host, the device sync engine and the tests.
library;

import 'canonical_json.dart';

abstract final class ProtocolVersion {
  static const current = 1;
  static const min = 1;
  static const max = 1;

  static bool supported(int v) => v >= min && v <= max;
}

/// Structured error codes (docs/PROTOCOL.md §4.5).
abstract final class ErrorCode {
  static const updateRequired = 'UPDATE_REQUIRED';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const sessionExpired = 'SESSION_EXPIRED';
  static const deviceRevoked = 'DEVICE_REVOKED';
  static const forbidden = 'FORBIDDEN';
  static const staffDisabled = 'STAFF_DISABLED';
  static const validation = 'VALIDATION';
  static const tooLarge = 'TOO_LARGE';
  static const rateLimited = 'RATE_LIMITED';
  static const epochChanged = 'EPOCH_CHANGED';
  static const commandIdReused = 'COMMAND_ID_REUSED';
  static const staleRevision = 'STALE_REVISION';
  static const tableOccupied = 'TABLE_OCCUPIED';
  static const orderClosed = 'ORDER_CLOSED';
  static const priceChanged = 'PRICE_CHANGED';
  static const itemUnavailable = 'ITEM_UNAVAILABLE';
  static const approvalRequired = 'APPROVAL_REQUIRED';
  static const transitionNotAllowed = 'TRANSITION_NOT_ALLOWED';
  static const conflict = 'CONFLICT';
  static const notFound = 'NOT_FOUND';
  static const hostUnreachable = 'HOST_UNREACHABLE';
  static const hostTimeout = 'HOST_TIMEOUT';
  static const expired = 'EXPIRED';
  static const quarantined = 'QUARANTINED';
  static const internal = 'INTERNAL';

  /// Failures a device retries automatically with the same command.
  static const retryable = {hostUnreachable, hostTimeout, rateLimited};

  static int httpStatus(String code) => switch (code) {
    updateRequired => 426,
    unauthenticated || sessionExpired || deviceRevoked => 401,
    forbidden || staffDisabled => 403,
    validation => 400,
    tooLarge => 413,
    rateLimited => 429,
    epochChanged || commandIdReused || conflict => 409,
    notFound => 404,
    hostUnreachable => 503,
    hostTimeout => 504,
    _ => 500,
  };
}

/// A protocol-level failure with a stable code. Business rejections become a
/// stored `rejected` result; the rest are transport/authorization errors.
class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message, {this.details});

  final String code;
  final String message;
  final Map<String, Object?>? details;

  bool get retryable => ErrorCode.retryable.contains(code);

  Map<String, Object?> toJson() => {
    'code': code,
    'message': message,
    'retryable': retryable,
    'details': details,
  };

  static ProtocolException fromJson(Map<String, Object?> j) => ProtocolException(
    j['code']! as String,
    (j['message'] as String?) ?? '',
    details: (j['details'] as Map?)?.cast<String, Object?>(),
  );

  @override
  String toString() => '$code: $message';
}

// ---- Validation helpers ----------------------------------------------------

final _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

ProtocolException _invalid(String what) => ProtocolException(ErrorCode.validation, what);

String requireId(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is! String || !_idPattern.hasMatch(v)) throw _invalid('$key must be an id');
  return v;
}

String? optionalId(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || !_idPattern.hasMatch(v)) throw _invalid('$key must be an id');
  return v;
}

int requireInt(Map<String, Object?> j, String key, {int min = -maxSafeInteger, int max = maxSafeInteger}) {
  final v = j[key];
  if (v is! int || v < min || v > max) throw _invalid('$key must be a whole number between $min and $max');
  return v;
}

int? optionalInt(Map<String, Object?> j, String key, {int min = -maxSafeInteger, int max = maxSafeInteger}) {
  if (j[key] == null) return null;
  return requireInt(j, key, min: min, max: max);
}

String requireString(Map<String, Object?> j, String key, {int maxLength = 200}) {
  final v = j[key];
  if (v is! String || v.isEmpty || v.length > maxLength) {
    throw _invalid('$key must be text up to $maxLength characters');
  }
  return v;
}

String? optionalString(Map<String, Object?> j, String key, {int maxLength = 200}) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String || v.length > maxLength) throw _invalid('$key must be text up to $maxLength characters');
  return v.isEmpty ? null : v;
}

Map<String, Object?> requireObject(Map<String, Object?> j, String key) {
  final v = j[key];
  if (v is! Map) throw _invalid('$key must be an object');
  return v.cast<String, Object?>();
}

List<Object?> requireList(Map<String, Object?> j, String key, {int maxLength = 100}) {
  final v = j[key];
  if (v is! List) throw _invalid('$key must be a list');
  if (v.length > maxLength) {
    throw ProtocolException(ErrorCode.tooLarge, '$key has more than $maxLength entries');
  }
  return v.cast<Object?>();
}

// ---- Commands ---------------------------------------------------------------

abstract final class CommandAction {
  static const orderPlace = 'order.place';
  static const orderAdd = 'order.add';
  static const orderChangeQuantity = 'order.change_quantity';
  static const orderSendToKitchen = 'order.send_to_kitchen';
  static const ticketSetStatus = 'ticket.set_status';

  static const all = {orderPlace, orderAdd, orderChangeQuantity, orderSendToKitchen, ticketSetStatus};
}

/// The command envelope (docs/PROTOCOL.md §4.1). [json] is kept exactly as
/// received so the body hash covers every field.
class Command {
  Command._(this.json);

  final Map<String, Object?> json;

  int get protocolVersion => json['protocolVersion']! as int;
  String get commandId => json['commandId']! as String;
  String get restaurantId => json['restaurantId']! as String;
  String get deviceId => json['deviceId']! as String;
  String get staffId => json['staffId']! as String;
  int get hostEpoch => json['hostEpoch']! as int;
  String get action => json['action']! as String;
  String? get aggregateId => json['aggregateId'] as String?;
  int? get expectedRevision => json['expectedRevision'] as int?;
  int get issuedAt => json['issuedAt']! as int;
  Map<String, Object?> get payload => (json['payload']! as Map).cast<String, Object?>();

  /// sha256hex of the canonical JSON of the whole envelope.
  String get bodyHash => canonicalHash(json);

  static const _fields = {
    'protocolVersion',
    'commandId',
    'restaurantId',
    'deviceId',
    'staffId',
    'hostEpoch',
    'action',
    'aggregateId',
    'expectedRevision',
    'issuedAt',
    'payload',
  };

  /// Validates the envelope. Unknown fields are refused so two hosts can never
  /// disagree about what a body hash covers.
  static Command parse(Object? raw) {
    if (raw is! Map) throw _invalid('A command must be a JSON object');
    final j = raw.cast<String, Object?>();
    final version = j['protocolVersion'];
    if (version is! int) throw _invalid('protocolVersion is required');
    if (!ProtocolVersion.supported(version)) {
      throw ProtocolException(
        ErrorCode.updateRequired,
        'Update CaféDesk Online on this device',
        details: {'min': ProtocolVersion.min, 'max': ProtocolVersion.max},
      );
    }
    for (final k in j.keys) {
      if (!_fields.contains(k)) throw _invalid('Unknown command field "$k"');
    }
    requireId(j, 'commandId');
    requireId(j, 'restaurantId');
    requireId(j, 'deviceId');
    requireId(j, 'staffId');
    requireInt(j, 'hostEpoch', min: 1);
    final action = requireString(j, 'action', maxLength: 40);
    if (!CommandAction.all.contains(action)) {
      throw ProtocolException(
        ErrorCode.updateRequired,
        'This POS does not know the action "$action". Update CaféDesk Online on the POS.',
        details: {'min': ProtocolVersion.min, 'max': ProtocolVersion.max},
      );
    }
    optionalId(j, 'aggregateId');
    optionalInt(j, 'expectedRevision', min: 1);
    requireInt(j, 'issuedAt', min: 0);
    requireObject(j, 'payload');
    // Floats, lone surrogates or non-string keys anywhere in the body.
    try {
      canonicalJson(j);
    } on FormatException catch (e) {
      throw _invalid('Invalid command body: ${e.message}');
    }
    return Command._(j);
  }

  static Map<String, Object?> build({
    required String commandId,
    required String restaurantId,
    required String deviceId,
    required String staffId,
    required int hostEpoch,
    required String action,
    String? aggregateId,
    int? expectedRevision,
    required int issuedAt,
    required Map<String, Object?> payload,
  }) => {
    'protocolVersion': ProtocolVersion.current,
    'commandId': commandId,
    'restaurantId': restaurantId,
    'deviceId': deviceId,
    'staffId': staffId,
    'hostEpoch': hostEpoch,
    'action': action,
    'aggregateId': aggregateId,
    'expectedRevision': expectedRevision,
    'issuedAt': issuedAt,
    'payload': payload,
  };
}

abstract final class ResultState {
  static const accepted = 'accepted';
  static const rejected = 'rejected';
}

/// What the host decided (docs/PROTOCOL.md §4.2).
class CommandResult {
  const CommandResult({
    required this.commandId,
    required this.state,
    required this.hostEpoch,
    this.resultId,
    this.revision,
    this.eventSequence = 0,
    this.acceptedAt,
    this.result,
    this.error,
  });

  final String commandId;
  final String state;
  final int hostEpoch;
  final String? resultId;
  final int? revision;
  final int eventSequence;
  final int? acceptedAt;
  final Map<String, Object?>? result;
  final ProtocolException? error;

  bool get accepted => state == ResultState.accepted;

  Map<String, Object?> toJson() => {
    'commandId': commandId,
    'state': state,
    'resultId': resultId,
    'revision': revision,
    'hostEpoch': hostEpoch,
    'eventSequence': eventSequence,
    'acceptedAt': acceptedAt,
    'result': result,
    'error': error?.toJson(),
  };

  static CommandResult fromJson(Map<String, Object?> j) => CommandResult(
    commandId: j['commandId']! as String,
    state: j['state']! as String,
    hostEpoch: j['hostEpoch']! as int,
    resultId: j['resultId'] as String?,
    revision: j['revision'] as int?,
    eventSequence: (j['eventSequence'] as int?) ?? 0,
    acceptedAt: j['acceptedAt'] as int?,
    result: (j['result'] as Map?)?.cast<String, Object?>(),
    error: j['error'] == null ? null : ProtocolException.fromJson((j['error']! as Map).cast<String, Object?>()),
  );
}

// ---- Events -----------------------------------------------------------------

abstract final class EventType {
  static const orderUpdated = 'order.updated';
  static const ticketUpdated = 'ticket.updated';
  static const menuChanged = 'menu.changed';
  static const tablesChanged = 'tables.changed';
  static const billFinalized = 'bill.finalized';
  static const refundCreated = 'refund.created';
  static const expenseRecorded = 'expense.recorded';
  static const expenseVoided = 'expense.voided';
  static const shiftUpdated = 'shift.updated';
  static const cashMovementRecorded = 'cash_movement.recorded';
  static const devicePaired = 'device.paired';
  static const deviceRevoked = 'device.revoked';
  static const sessionRevoked = 'session.revoked';
  static const staffAccessChanged = 'staff.access_changed';

  /// After a restore: every financial row the POS still has was re-sent in this
  /// epoch, so the cloud drops report rows of older epochs (§5.4).
  static const hostRestored = 'host.restored';

  /// Types sent to paired devices; everything else is cloud-only.
  static const deviceAudience = {orderUpdated, ticketUpdated, menuChanged, tablesChanged};
}

abstract final class EventAudience {
  static const devices = 'devices';
  static const cloud = 'cloud';
}
