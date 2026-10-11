import 'dart:convert';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart' as bu;
import 'package:crypto/crypto.dart' as hash;
import 'package:cryptography/cryptography.dart';

import '../protocol/canonical_json.dart';
import '../security/secret_store.dart';

/// The POS host's key material. Private parts come from [SecretStore]; the
/// public parts and the certificate are also kept in the host identity row so
/// devices and the cloud can be told about them.
class HostKeys {
  HostKeys({
    required this.tlsCertPem,
    required this.tlsKeyPem,
    required this.signingKey,
    required this.sealKey,
    required this.signingPublicKey,
    required this.sealPublicKey,
  });

  final String tlsCertPem;
  final String tlsKeyPem;
  final SimpleKeyPair signingKey;
  final SimpleKeyPair sealKey;
  final List<int> signingPublicKey;
  final List<int> sealPublicKey;

  String get tlsCertSha256 => certificateSha256(tlsCertPem);

  static String _secret(String hostDeviceId, String name) => 'cafedesk-online/host/$hostDeviceId/$name';

  /// Creates new keys and a self-signed TLS certificate (EC P-256, 10 years)
  /// and stores the private parts.
  static Future<HostKeys> generate(String hostDeviceId, SecretStore store) async {
    // Certificate generation is pure Dart and takes a moment; keep it off the
    // UI isolate.
    final (certPem, keyPem) = await Isolate.run(() => _selfSigned(hostDeviceId));
    final signing = await Ed25519().newKeyPair();
    final seal = await X25519().newKeyPair();
    final signingSeed = await signing.extractPrivateKeyBytes();
    final sealSeed = await seal.extractPrivateKeyBytes();
    await store.write(_secret(hostDeviceId, 'tls_key'), keyPem);
    await store.write(_secret(hostDeviceId, 'signing_seed'), b64url(signingSeed));
    await store.write(_secret(hostDeviceId, 'seal_seed'), b64url(sealSeed));
    return HostKeys(
      tlsCertPem: certPem,
      tlsKeyPem: keyPem,
      signingKey: signing,
      sealKey: seal,
      signingPublicKey: (await signing.extractPublicKey()).bytes,
      sealPublicKey: (await seal.extractPublicKey()).bytes,
    );
  }

  /// Loads the private parts for [hostDeviceId]; null if any is missing (for
  /// example a backup restored on a different PC, whose secure storage does
  /// not have them).
  static Future<HostKeys?> load(String hostDeviceId, String certPem, SecretStore store) async {
    final keyPem = await store.read(_secret(hostDeviceId, 'tls_key'));
    final signingSeed = await store.read(_secret(hostDeviceId, 'signing_seed'));
    final sealSeed = await store.read(_secret(hostDeviceId, 'seal_seed'));
    if (keyPem == null || signingSeed == null || sealSeed == null) return null;
    final signing = await Ed25519().newKeyPairFromSeed(b64urlDecode(signingSeed));
    final seal = await X25519().newKeyPairFromSeed(b64urlDecode(sealSeed));
    return HostKeys(
      tlsCertPem: certPem,
      tlsKeyPem: keyPem,
      signingKey: signing,
      sealKey: seal,
      signingPublicKey: (await signing.extractPublicKey()).bytes,
      sealPublicKey: (await seal.extractPublicKey()).bytes,
    );
  }

  static Future<void> forget(String hostDeviceId, SecretStore store) async {
    for (final name in ['tls_key', 'signing_seed', 'seal_seed', 'cloud_credential']) {
      await store.delete(_secret(hostDeviceId, name));
    }
  }

  static Future<void> writeCloudCredential(String hostDeviceId, SecretStore store, String credential) =>
      store.write(_secret(hostDeviceId, 'cloud_credential'), credential);

  static Future<String?> readCloudCredential(String hostDeviceId, SecretStore store) =>
      store.read(_secret(hostDeviceId, 'cloud_credential'));
}

(String, String) _selfSigned(String hostDeviceId) {
  final pair = bu.CryptoUtils.generateEcKeyPair();
  final priv = pair.privateKey as bu.ECPrivateKey;
  final pub = pair.publicKey as bu.ECPublicKey;
  final name = {'CN': 'CafeDesk Online POS ${hostDeviceId.substring(0, 8)}', 'O': 'CafeDesk Online'};
  final csr = bu.X509Utils.generateEccCsrPem(name, priv, pub);
  final cert = bu.X509Utils.generateSelfSignedCertificate(
    priv,
    csr,
    3650,
    serialNumber: '${DateTime.now().toUtc().millisecondsSinceEpoch}',
    notBefore: DateTime.now().toUtc().subtract(const Duration(days: 1)),
  );
  return (cert, bu.CryptoUtils.encodeEcPrivateKeyToPem(priv));
}

/// SHA-256 (lower-case hex) of the certificate's DER bytes — what devices pin.
String certificateSha256(String pem) => hash.sha256.convert(pemToDer(pem)).toString();

List<int> pemToDer(String pem) {
  final body = pem.split('\n').where((l) => !l.startsWith('-----') && l.trim().isNotEmpty).map((l) => l.trim()).join();
  return base64.decode(body);
}
