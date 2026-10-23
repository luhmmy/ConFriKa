import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../crypto/e2ee_service.dart';
import '../network/api_client.dart';

/// Renders an image message. Plaintext images load over the network; encrypted
/// images are downloaded as a ciphertext blob and decrypted on-device with the
/// thread's shared key, then shown from memory.
class ChatImage extends StatelessWidget {
  final String mediaUrl;
  final bool encrypted;
  final String? peerPub; // required when encrypted

  const ChatImage({
    super.key,
    required this.mediaUrl,
    this.encrypted = false,
    this.peerPub,
  });

  // Small in-memory cache so a decrypted image isn't fetched/decrypted twice.
  static final Map<String, Uint8List> _cache = {};

  @override
  Widget build(BuildContext context) {
    final api = ConFriKaApiClient.instance;
    const maxW = 240.0;
    final border = BorderRadius.circular(12);

    if (!encrypted) {
      return ClipRRect(
        borderRadius: border,
        child: Image.network(
          api.mediaUrl(mediaUrl),
          width: maxW,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _broken(),
          loadingBuilder: (c, child, p) =>
              p == null ? child : _loading(),
        ),
      );
    }

    final cached = _cache[mediaUrl];
    if (cached != null) {
      return ClipRRect(
          borderRadius: border,
          child: Image.memory(cached, width: maxW, fit: BoxFit.cover));
    }
    return FutureBuilder<Uint8List>(
      future: _decrypt(api),
      builder: (c, snap) {
        if (snap.connectionState != ConnectionState.done) return _loading();
        if (snap.hasError || snap.data == null) return _broken();
        _cache[mediaUrl] = snap.data!;
        return ClipRRect(
            borderRadius: border,
            child: Image.memory(snap.data!, width: maxW, fit: BoxFit.cover));
      },
    );
  }

  Future<Uint8List> _decrypt(ConFriKaApiClient api) async {
    final blob = await api.downloadBytes(mediaUrl);
    final clear = await E2eeService.instance.decryptBytes(peerPub!, blob);
    return Uint8List.fromList(clear);
  }

  Widget _loading() => Container(
        width: 240,
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const SizedBox(
            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
      );

  Widget _broken() => Container(
        width: 240,
        height: 140,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.broken_image_outlined, color: Colors.white70),
      );
}
