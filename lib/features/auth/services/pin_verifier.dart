import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// A stored PIN verifier: salt, parameters and the derived key.
///
/// This is what offline sign-in checks against. The PIN itself is never stored,
/// never logged, and never leaves the function that derives from it.
class PinVerifier {
  const PinVerifier({
    required this.salt,
    required this.hash,
    required this.iterations,
    this.algorithm = _algorithm,
  });

  factory PinVerifier.fromJson(Map<String, dynamic> json) => PinVerifier(
        salt: base64Decode(json['salt'] as String),
        hash: base64Decode(json['hash'] as String),
        iterations: json['iterations'] as int,
        algorithm: json['alg'] as String,
      );

  static const String _algorithm = 'PBKDF2-HMAC-SHA256';

  /// Work factor.
  ///
  /// A four-digit PIN is only ~13 bits, so no work factor makes an extracted
  /// verifier safe on its own — the real defences are the platform keystore
  /// holding this record and the attempt lockout above it. This value is a
  /// deliberate compromise: high enough to make bulk guessing slow, low enough
  /// that sign-in stays under about a second on a low-end handset. Raise it and
  /// add `cryptography_flutter` for native acceleration when that is available.
  static const int defaultIterations = 60000;

  final Uint8List salt;
  final Uint8List hash;
  final int iterations;
  final String algorithm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'salt': base64Encode(salt),
        'hash': base64Encode(hash),
        'iterations': iterations,
        'alg': algorithm,
      };

  /// Never include the salt or hash here.
  @override
  String toString() => 'PinVerifier($algorithm, $iterations iterations)';
}

/// Derives and checks PIN verifiers.
class PinHasher {
  const PinHasher({this.iterations = PinVerifier.defaultIterations});

  final int iterations;

  static final Random _random = Random.secure();

  /// Derives a fresh verifier for [pin] with a new random salt.
  Future<PinVerifier> derive(String pin) async {
    final Uint8List salt = _newSalt();
    return PinVerifier(
      salt: salt,
      hash: await _deriveKey(pin, salt, iterations),
      iterations: iterations,
    );
  }

  /// True when [pin] reproduces [verifier].
  ///
  /// Compares in constant time so a wrong PIN cannot be narrowed down by
  /// timing how long the check took.
  Future<bool> matches(String pin, PinVerifier verifier) async {
    final Uint8List candidate = await _deriveKey(
      pin,
      verifier.salt,
      verifier.iterations,
    );
    return _constantTimeEquals(candidate, verifier.hash);
  }

  static Future<Uint8List> _deriveKey(
    String pin,
    Uint8List salt,
    int iterations,
  ) async {
    final Pbkdf2 pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    final SecretKey key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  static Uint8List _newSalt() {
    final Uint8List salt = Uint8List(32);
    for (int i = 0; i < salt.length; i++) {
      salt[i] = _random.nextInt(256);
    }
    return salt;
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    int diff = 0;
    for (int i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
