import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:hashlib/hashlib.dart';

import '../errors/app_exception.dart';

/// Salted Argon2id password hashing (hashlib, PHC string format), plus the
/// email and password rules for staff accounts.
///
/// Hashes keep passwords out of the database in plain text and make guessing
/// slow, but a weak password copied out with the database file can still be
/// guessed offline. The app's retry delay only protects the sign-in screen.
class PasswordHasher {
  /// OWASP's minimum Argon2id settings: 19 MiB, 2 passes, 1 lane.
  const PasswordHasher({this.memoryKb = 19456, this.iterations = 2, this.parallelism = 1});

  /// Cheap parameters for unit tests only.
  const PasswordHasher.fastForTests() : this(memoryKb: 64, iterations: 1, parallelism: 1);

  final int memoryKb;
  final int iterations;
  final int parallelism;

  static const minPasswordLength = 8;
  static const maxPasswordLength = 128;

  static void validatePassword(String password, {String? email}) {
    if (password.length < minPasswordLength) {
      throw const ValidationException('Password must be at least $minPasswordLength characters');
    }
    if (password.length > maxPasswordLength) {
      throw const ValidationException('Password must be at most $maxPasswordLength characters');
    }
    if (password.trim().isEmpty || RegExp(r'^(.)\1+$').hasMatch(password)) {
      throw const ValidationException('Password cannot be one character repeated');
    }
    if (email != null && password.trim().toLowerCase() == email.trim().toLowerCase()) {
      throw const ValidationException('Password cannot be the same as the email');
    }
  }

  /// Trimmed, lower-case email, or a [ValidationException].
  static String normalizeEmail(String input) {
    final e = input.trim().toLowerCase();
    if (e.length > 254 || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(e)) {
      throw const ValidationException('Enter a valid email address, like name@example.com');
    }
    return e;
  }

  /// Runs off the UI isolate.
  Future<String> hash(String secret) {
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
      ).encode(utf8.encode(secret)),
    );
  }

  Future<bool> verify(String secret, String encoded) => Isolate.run(() {
    try {
      return argon2Verify(encoded, utf8.encode(secret));
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
