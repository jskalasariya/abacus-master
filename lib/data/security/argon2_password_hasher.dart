import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/helpers.dart' show constantTimeBytesEquality;

/// Password hashing adapter backed by RFC 9106 Argon2id.
///
/// Each hash receives a cryptographically random 16-byte salt. The encoded
/// value includes version and cost parameters so future code can verify or
/// upgrade it. The pure-Dart backend is portable; hashing is asynchronous and
/// costs memory/CPU, so tune it on target devices.
abstract interface class PasswordHasher {
  Future<String> hash(String password);

  Future<bool> verify(String password, String encodedHash);
}

final class Argon2PasswordHasher implements PasswordHasher {
  Argon2PasswordHasher() : _secureRandom = Random.secure();

  static const memoryKiB = 19456;
  static const iterations = 2;
  static const parallelism = 1;
  static const hashLength = 32;
  static const saltLength = 16;

  final Random _secureRandom;

  @override
  Future<String> hash(String password) async {
    final salt = List<int>.generate(
      saltLength,
      (_) => _secureRandom.nextInt(256),
      growable: false,
    );
    final algorithm = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: salt,
    );
    final derived = await key.extractBytes();
    final encoded = StringBuffer('argon2id\$v=19\$m=')
      ..write(memoryKiB)
      ..write(',t=')
      ..write(iterations)
      ..write(',p=')
      ..write(parallelism)
      ..write('\$')
      ..write(base64Url.encode(salt))
      ..write('\$')
      ..write(base64Url.encode(derived));
    return encoded.toString();
  }

  @override
  Future<bool> verify(String password, String encodedHash) async {
    if (password.isEmpty || password.length > 128) return false;
    final parsed = _parseEncoding(encodedHash);
    if (parsed == null) return false;

    final algorithm = Argon2id(
      memory: memoryKiB,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: hashLength,
    );
    final key = await algorithm.deriveKeyFromPassword(
      password: password,
      nonce: parsed.salt,
    );
    final derived = await key.extractBytes();
    return constantTimeBytesEquality.equals(derived, parsed.hash);
  }

  _ParsedPasswordHash? _parseEncoding(String encodedHash) {
    // Bound parsing work and accept only the exact encoding this implementation
    // writes. New algorithms or cost parameters need an explicit upgrade path.
    if (encodedHash.length > 128) return null;
    final fields = encodedHash.split(r'$');
    if (fields.length != 5 ||
        fields[0] != 'argon2id' ||
        fields[1] != 'v=19' ||
        fields[2] != 'm=$memoryKiB,t=$iterations,p=$parallelism') {
      return null;
    }

    try {
      final salt = base64Url.decode(fields[3]);
      final hash = base64Url.decode(fields[4]);
      if (salt.length != saltLength ||
          hash.length != hashLength ||
          base64Url.encode(salt) != fields[3] ||
          base64Url.encode(hash) != fields[4]) {
        return null;
      }
      return _ParsedPasswordHash(salt, hash);
    } on FormatException {
      return null;
    }
  }
}

final class _ParsedPasswordHash {
  const _ParsedPasswordHash(this.salt, this.hash);

  final List<int> salt;
  final List<int> hash;
}
