import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// End-to-end encryption for direct messages.
///
/// Scheme (v1): static X25519 ECDH → HKDF-SHA256 → AES-256-GCM. The shared
/// secret between two users is symmetric, so the same derived key both encrypts
/// and decrypts every message in a 1:1 thread, in either direction.
///
/// The private key never leaves the device (stored in the platform keystore via
/// flutter_secure_storage); only the public key is uploaded. Note: this is not
/// a double-ratchet, so it has no forward secrecy — a reasonable v1 trade-off.
class E2eeService {
  E2eeService._();
  static final E2eeService instance = E2eeService._();

  static const _kSeed = 'confrika_e2ee_seed_v1';
  static const _kPub = 'confrika_e2ee_pub_v1';

  final _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  final _x25519 = X25519();
  final _aead = AesGcm.with256bits();
  final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  SimpleKeyPair? _keyPair;
  String? _publicKeyB64;

  // Derived-key cache keyed by peer public key (avoids repeating ECDH+HKDF).
  final Map<String, SecretKey> _sharedCache = {};

  /// Ensure a device keypair exists; returns our base64 public key.
  Future<String> ensureKeyPair() async {
    if (_publicKeyB64 != null) return _publicKeyB64!;
    final seed = await _storage.read(key: _kSeed);
    final pub = await _storage.read(key: _kPub);
    if (seed != null && pub != null) {
      _keyPair = await _x25519.newKeyPairFromSeed(base64Decode(seed));
      _publicKeyB64 = pub;
      return pub;
    }
    final kp = await _x25519.newKeyPair();
    final seedBytes = await kp.extractPrivateKeyBytes();
    final pk = await kp.extractPublicKey();
    final pubB64 = base64Encode(pk.bytes);
    await _storage.write(key: _kSeed, value: base64Encode(seedBytes));
    await _storage.write(key: _kPub, value: pubB64);
    _keyPair = kp;
    _publicKeyB64 = pubB64;
    return pubB64;
  }

  Future<String> get publicKey async => ensureKeyPair();

  Future<SecretKey> _sharedKey(String peerPubB64) async {
    final cached = _sharedCache[peerPubB64];
    if (cached != null) return cached;
    await ensureKeyPair();
    final peerPub =
        SimplePublicKey(base64Decode(peerPubB64), type: KeyPairType.x25519);
    final shared = await _x25519.sharedSecretKey(
      keyPair: _keyPair!,
      remotePublicKey: peerPub,
    );
    final derived = await _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('confrika-dm-v1'),
      info: utf8.encode('direct-message'),
    );
    _sharedCache[peerPubB64] = derived;
    return derived;
  }

  /// Encrypt [plaintext] for the peer whose public key is [peerPubB64].
  /// Returns a single base64 blob packing nonce | ciphertext | mac.
  Future<String> encryptFor(String peerPubB64, String plaintext) async {
    final key = await _sharedKey(peerPubB64);
    final box = await _aead.encrypt(utf8.encode(plaintext), secretKey: key);
    return base64Encode(box.concatenation());
  }

  /// Decrypt a base64 blob produced by [encryptFor] from the same peer.
  Future<String> decryptFrom(String peerPubB64, String blobB64) async {
    final key = await _sharedKey(peerPubB64);
    final box = SecretBox.fromConcatenation(
      base64Decode(blobB64),
      nonceLength: 12,
      macLength: 16,
    );
    final clear = await _aead.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  /// Encrypt raw bytes (e.g. an image) for a peer; returns nonce|ct|mac bytes.
  Future<List<int>> encryptBytes(String peerPubB64, List<int> bytes) async {
    final key = await _sharedKey(peerPubB64);
    final box = await _aead.encrypt(bytes, secretKey: key);
    return box.concatenation();
  }

  /// Decrypt raw bytes produced by [encryptBytes] from the same peer.
  Future<List<int>> decryptBytes(String peerPubB64, List<int> blob) async {
    final key = await _sharedKey(peerPubB64);
    final box = SecretBox.fromConcatenation(blob, nonceLength: 12, macLength: 16);
    return _aead.decrypt(box, secretKey: key);
  }
}
