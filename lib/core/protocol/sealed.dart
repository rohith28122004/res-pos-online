import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'canonical_json.dart';
import 'protocol.dart';

/// Sealed requests (docs/PROTOCOL.md §6): a device encrypts a small JSON
/// object (sign-in or owner approval with a password) to the host's X25519
/// seal key, so the password is readable only by the POS host — not by the
/// cloud relay and not by anyone on the café Wi-Fi.
abstract final class Sealed {
  static const alg = 'X25519-HKDF-SHA256-A256GCM';
  static const _info = 'cafedesk-seal-v1';

  static final _x25519 = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  static Future<SecretKey> _key(List<int> shared, List<int> epk, List<int> hostPublic) =>
      _hkdf.deriveKey(secretKey: SecretKey(shared), nonce: [...epk, ...hostPublic], info: utf8.encode(_info));

  static List<int> _aad(String deviceId) => utf8.encode('$_info|$deviceId');

  /// Device side.
  static Future<Map<String, Object?>> seal(
    Map<String, Object?> plaintext, {
    required List<int> hostSealPublicKey,
    required String deviceId,
  }) async {
    final eph = await _x25519.newKeyPair();
    final epk = (await eph.extractPublicKey()).bytes;
    final shared = await _x25519.sharedSecretKey(
      keyPair: eph,
      remotePublicKey: SimplePublicKey(hostSealPublicKey, type: KeyPairType.x25519),
    );
    final key = await _key(await shared.extractBytes(), epk, hostSealPublicKey);
    final nonce = _aes.newNonce();
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(plaintext)),
      secretKey: key,
      nonce: nonce,
      aad: _aad(deviceId),
    );
    return {
      'v': 1,
      'alg': alg,
      'epk': b64url(epk),
      'nonce': b64url(nonce),
      'ct': b64url([...box.cipherText, ...box.mac.bytes]),
    };
  }

  /// Host side. Throws `UNAUTHENTICATED` if the box was not made for this
  /// host and device or was tampered with.
  static Future<Map<String, Object?>> open(
    Object? sealed, {
    required SimpleKeyPair hostSealKey,
    required String deviceId,
  }) async {
    if (sealed is! Map || sealed['v'] != 1 || sealed['alg'] != alg) {
      throw const ProtocolException(ErrorCode.validation, 'Not a sealed request');
    }
    try {
      final epk = b64urlDecode(sealed['epk']! as String);
      final nonce = b64urlDecode(sealed['nonce']! as String);
      final ct = b64urlDecode(sealed['ct']! as String);
      if (epk.length != 32 || nonce.length != 12 || ct.length < 16) throw const FormatException();
      final hostPublic = (await hostSealKey.extractPublicKey()).bytes;
      final shared = await _x25519.sharedSecretKey(
        keyPair: hostSealKey,
        remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519),
      );
      final key = await _key(await shared.extractBytes(), epk, hostPublic);
      final clear = await _aes.decrypt(
        SecretBox(ct.sublist(0, ct.length - 16), nonce: nonce, mac: Mac(ct.sublist(ct.length - 16))),
        secretKey: key,
        aad: _aad(deviceId),
      );
      return (jsonDecode(utf8.decode(clear)) as Map).cast<String, Object?>();
    } on ProtocolException {
      rethrow;
    } on Object {
      throw const ProtocolException(ErrorCode.unauthenticated, 'This request could not be opened by this POS');
    }
  }
}
