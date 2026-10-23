import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

/// Validates the exact E2EE scheme used by E2eeService:
/// static X25519 ECDH → HKDF-SHA256 → AES-256-GCM, with the same salt/info.
/// (E2eeService itself wraps this with secure-storage key persistence, which
/// isn't available in a unit-test host, so we exercise the crypto directly.)
void main() {
  final x = X25519();
  final aead = AesGcm.with256bits();
  final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  Future<SecretKey> sharedKey(SimpleKeyPair mine, SimplePublicKey peerPub) async {
    final shared = await x.sharedSecretKey(keyPair: mine, remotePublicKey: peerPub);
    return hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('confrika-dm-v1'),
      info: utf8.encode('direct-message'),
    );
  }

  test('two parties round-trip an encrypted message (both directions)', () async {
    final alice = await x.newKeyPair();
    final bob = await x.newKeyPair();
    final alicePub = await alice.extractPublicKey();
    final bobPub = await bob.extractPublicKey();

    // Alice encrypts for Bob.
    final kA = await sharedKey(alice, bobPub);
    final box = await aead.encrypt(utf8.encode('Ẹ káàsán, how far?'), secretKey: kA);
    final blob = base64Encode(box.concatenation());

    // Bob decrypts with his key + Alice's public key.
    final kB = await sharedKey(bob, alicePub);
    final recovered = SecretBox.fromConcatenation(base64Decode(blob),
        nonceLength: 12, macLength: 16);
    final clear = await aead.decrypt(recovered, secretKey: kB);
    expect(utf8.decode(clear), 'Ẹ káàsán, how far?');
  });

  test('a third party with the wrong key cannot decrypt', () async {
    final alice = await x.newKeyPair();
    final bob = await x.newKeyPair();
    final eve = await x.newKeyPair();
    final bobPub = await bob.extractPublicKey();
    final alicePub = await alice.extractPublicKey();

    final kA = await sharedKey(alice, bobPub);
    final box = await aead.encrypt(utf8.encode('secret'), secretKey: kA);

    // Eve derives a shared key with Alice — not the Alice↔Bob key.
    final kEve = await sharedKey(eve, alicePub);
    expect(
      () async => aead.decrypt(box, secretKey: kEve),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('derived key is 256-bit and deterministic for a pair', () async {
    final alice = await x.newKeyPair();
    final bob = await x.newKeyPair();
    final bobPub = await bob.extractPublicKey();
    final alicePub = await alice.extractPublicKey();

    final k1 = await (await sharedKey(alice, bobPub)).extractBytes();
    final k2 = await (await sharedKey(bob, alicePub)).extractBytes();
    expect(k1.length, 32);
    expect(k1, equals(k2)); // ECDH symmetry
  });
}
