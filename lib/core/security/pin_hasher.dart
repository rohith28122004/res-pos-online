import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:hashlib/hashlib.dart';

import '../errors/app_exception.dart';

/// Salted Argon2id PIN hashing (hashlib, PHC string format).
///
/// A 4–8 digit PIN is a weak secret: these hashes slow down casual guessing
/// and keep PINs out of the database in plain text, but anyone who can copy
/// the database file can still brute-force a short PIN offline. The app's
/// retry delay only protects the normal login screen.
class PinHasher {
  const PinHasher({this.memoryKb = 19456, this.iterations = 2, this.parallelism = 1});

  /// Cheap parameters for unit tests only.
  const PinHasher.fastForTests() : this(memoryKb: 64, iterations: 1, parallelism: 1);

  final int memoryKb;
  final int iterations;
  final int parallelism;

  static void validatePin(String pin) {
    if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
      throw const ValidationException('PIN must be 4 to 8 digits');
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin)) {
      throw const ValidationException('PIN cannot be the same digit repeated');
    }
    const sequences = '0123456789012345678909876543210';
    if (sequences.contains(pin)) {
      throw const ValidationException('PIN cannot be a simple sequence like 1234');
    }
  }

  /// Runs off the UI isolate.
  Future<String> hash(String pin) {
    final salt = _randomBytes(16);
    final m = memoryKb, t = iterations, p = parallelism;
    return Isolate.run(
      () => Argon2(
        salt: salt,
        type: Argon2Type.argon2id,
        hashLength: 32,
        iterations: t,
        parallelism: p,
        memorySizeKB: m,
      ).encode(utf8.encode(pin)),
    );
  }

  Future<bool> verify(String pin, String encoded) => Isolate.run(() {
    try {
      return argon2Verify(encoded, utf8.encode(pin));
    } on Object {
      return false;
    }
  });

  static List<int> _randomBytes(int n) {
    final r = Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  /// Random recovery code like "K7QF-2MXP-9TRA-VD4H" (no 0/O/1/I).
  static String newRecoveryCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    final chars = List.generate(16, (_) => alphabet[r.nextInt(alphabet.length)]);
    return [
      for (var i = 0; i < 16; i += 4) chars.sublist(i, i + 4).join(),
    ].join('-');
  }

  static String normalizeRecoveryCode(String input) => input.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
