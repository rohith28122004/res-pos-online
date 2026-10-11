import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';
import 'protocol.dart';

/// Claims of a host-signed staff session token (docs/PROTOCOL.md §3.2).
class SessionClaims {
  const SessionClaims({
    required this.sessionId,
    required this.restaurantId,
    required this.deviceId,
    required this.staffId,
    required this.name,
    required this.role,
    required this.hostEpoch,
    required this.issuedAt,
    required this.expiresAt,
  });

  final String sessionId;
  final String restaurantId;
  final String deviceId;
  final String staffId;
  final String name;
  final String role;
  final int hostEpoch;

  /// Seconds since the epoch.
  final int issuedAt;
  final int expiresAt;

  Map<String, Object?> toJson() => {
    'v': 1,
    'sid': sessionId,
    'rid': restaurantId,
    'did': deviceId,
    'sub': staffId,
    'name': name,
    'role': role,
    'ep': hostEpoch,
    'iat': issuedAt,
    'exp': expiresAt,
  };

  static SessionClaims fromJson(Map<String, Object?> j) {
    if (j['v'] != 1) throw const ProtocolException(ErrorCode.unauthenticated, 'Unknown session token version');
    try {
      return SessionClaims(
        sessionId: j['sid']! as String,
        restaurantId: j['rid']! as String,
        deviceId: j['did']! as String,
        staffId: j['sub']! as String,
        name: j['name']! as String,
        role: j['role']! as String,
        hostEpoch: j['ep']! as int,
        issuedAt: j['iat']! as int,
        expiresAt: j['exp']! as int,
      );
    } on Object {
      throw const ProtocolException(ErrorCode.unauthenticated, 'Malformed session token');
    }
  }
}

/// `cds1.<b64url(claims)>.<b64url(Ed25519 signature)>`.
abstract final class SessionToken {
  static const prefix = 'cds1';
  static final _ed = Ed25519();

  static Future<String> sign(SessionClaims claims, SimpleKeyPair signingKey) async {
    final head = '$prefix.${b64url(utf8.encode(canonicalJson(claims.toJson())))}';
    final sig = await _ed.sign(ascii.encode(head), keyPair: signingKey);
    return '$head.${b64url(sig.bytes)}';
  }

  /// Verifies the signature only; callers then check device, restaurant,
  /// expiry and revocation. Throws `UNAUTHENTICATED` on any problem.
  static Future<SessionClaims> verify(String token, List<int> signingPublicKey) async {
    final parts = token.split('.');
    if (parts.length != 3 || parts[0] != prefix) {
      throw const ProtocolException(ErrorCode.unauthenticated, 'Not a session token');
    }
    final head = '${parts[0]}.${parts[1]}';
    List<int> sigBytes;
    Map<String, Object?> json;
    try {
      sigBytes = b64urlDecode(parts[2]);
      json = (jsonDecode(utf8.decode(b64urlDecode(parts[1]))) as Map).cast<String, Object?>();
    } on Object {
      throw const ProtocolException(ErrorCode.unauthenticated, 'Malformed session token');
    }
    final ok = await _ed.verify(
      ascii.encode(head),
      signature: Signature(sigBytes, publicKey: SimplePublicKey(signingPublicKey, type: KeyPairType.ed25519)),
    );
    if (!ok) throw const ProtocolException(ErrorCode.unauthenticated, 'Session token signature is not valid');
    return SessionClaims.fromJson(json);
  }
}
