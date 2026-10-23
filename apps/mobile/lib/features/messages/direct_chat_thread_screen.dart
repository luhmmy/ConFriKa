import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/crypto/e2ee_service.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/chat_image.dart';
import '../../core/widgets/user_avatar.dart';

/// A single 1-on-1 private conversation (WhatsApp-style thread).
///
/// Messages are auto-translated into each reader's own dialect, and the thread
/// polls for new incoming messages while it is open.
class DirectChatThreadScreen extends StatefulWidget {
  final String partnerUsername;
  final String partnerName;
  final void Function(String username)? onStartCall;

  const DirectChatThreadScreen({
    super.key,
    required this.partnerUsername,
    required this.partnerName,
    this.onStartCall,
  });

  @override
  State<DirectChatThreadScreen> createState() => _DirectChatThreadScreenState();
}

class _DirectChatThreadScreenState extends State<DirectChatThreadScreen> {
  final _api = ConFriKaApiClient.instance;
  final _composeCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _picker = ImagePicker();
  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _showTranslation = true;
  bool _showEmoji = false;
  String? _error;
  Timer? _pollTimer;

  // E2E encryption state for this thread.
  String? _partnerPub; // null => partner has no key; chat falls back to plaintext
  String? _partnerDialect;
  String? _partnerAvatar;
  bool get _encrypted => _partnerPub != null;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await E2eeService.instance.ensureKeyPair();
    try {
      final info = await _api.peerKeyInfo(widget.partnerUsername);
      _partnerPub = info['public_key'] as String?;
      _partnerDialect = info['primary_dialect'] as String?;
      _partnerAvatar = info['avatar_url'] as String?;
    } catch (_) {}
    await _load(initial: true);
    _pollTimer =
        Timer.periodic(const Duration(seconds: 4), (_) => _load(initial: false));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _composeCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load({required bool initial}) async {
    try {
      final rows = await _api.directMessages(widget.partnerUsername);
      if (!mounted) return;
      final next = rows.cast<Map<String, dynamic>>();
      await _decryptAll(next);
      final grew = next.length != _messages.length;
      setState(() {
        _messages = next;
        _loading = false;
        _error = null;
      });
      // Clear unread badges for messages the partner sent me.
      unawaited(_api.markThreadRead(widget.partnerUsername).catchError((_) {}));
      if (initial || grew) _scrollToBottom();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  /// Decrypt every encrypted message in place so the bubble renderer can use
  /// the existing original_text / translated_text fields. Both directions of a
  /// 1:1 thread share the same key (ECDH is symmetric), so the partner's public
  /// key decrypts my own sent messages too.
  Future<void> _decryptAll(List<Map<String, dynamic>> rows) async {
    for (final m in rows) {
      if (m['is_encrypted'] != true) continue;
      final blob = m['ciphertext'] as String?;
      final peerPub = _partnerPub;
      if (blob == null || peerPub == null) {
        m['original_text'] = '🔒 Encrypted';
        continue;
      }
      try {
        final clear = await E2eeService.instance.decryptFrom(peerPub, blob);
        final payload = jsonDecode(clear) as Map<String, dynamic>;
        m['original_text'] = payload['original'] as String? ?? '';
        m['translated_text'] = payload['translated'] as String?;
        if (payload['media_url'] != null) m['media_url'] = payload['media_url'];
      } catch (_) {
        m['original_text'] = '🔒 Unable to decrypt';
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _composeCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final sourceDialect = ConFriKaSession.instance.primaryDialect;
    try {
      if (_encrypted) {
        // Translate-before-encrypt: the server only ever stores ciphertext.
        String? translated;
        final target = _partnerDialect ?? 'English';
        if (target.trim().toLowerCase() != sourceDialect.trim().toLowerCase()) {
          try {
            final res = await _api.translate(
              text: text,
              sourceDialect: sourceDialect,
              targetDialect: target,
            );
            translated = res['translated_text'] as String?;
          } catch (_) {/* send without translation if it fails */}
        }
        final payload = jsonEncode({'original': text, 'translated': translated});
        final blob = await E2eeService.instance.encryptFor(_partnerPub!, payload);
        await _api.sendEncryptedDirectMessage(
          recipientUsername: widget.partnerUsername,
          ciphertext: blob,
          senderPub: await E2eeService.instance.publicKey,
          sourceDialect: sourceDialect,
          targetDialect: target,
        );
      } else {
        await _api.sendDirectMessage(
          recipientUsername: widget.partnerUsername,
          text: text,
          sourceDialect: sourceDialect,
          autoTranslate: _showTranslation,
        );
      }
      _composeCtrl.clear();
      await _load(initial: false);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickAndSendImage() async {
    final XFile? picked =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    setState(() => _sending = true);
    final dialect = ConFriKaSession.instance.primaryDialect;
    try {
      if (_encrypted) {
        // Encrypt the image bytes, upload the ciphertext blob, and reference it
        // inside the encrypted message payload.
        final bytes = await File(picked.path).readAsBytes();
        final blob = await E2eeService.instance.encryptBytes(_partnerPub!, bytes);
        final url = await _api.uploadEncryptedBlob(blob);
        final payload =
            jsonEncode({'original': '', 'translated': null, 'media_url': url});
        final ct = await E2eeService.instance.encryptFor(_partnerPub!, payload);
        await _api.sendEncryptedDirectMessage(
          recipientUsername: widget.partnerUsername,
          ciphertext: ct,
          senderPub: await E2eeService.instance.publicKey,
          sourceDialect: dialect,
          messageType: 'image',
        );
      } else {
        final url = await _api.uploadImage(picked.path);
        await _api.sendDirectMessage(
          recipientUsername: widget.partnerUsername,
          sourceDialect: dialect,
          messageType: 'image',
          mediaUrl: url,
          autoTranslate: false,
        );
      }
      await _load(initial: false);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            UserAvatar(
                name: widget.partnerName, avatarUrl: _partnerAvatar, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.partnerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis),
                  Text('@${widget.partnerUsername.replaceFirst('@', '')}',
                      style: TextStyle(
                          fontSize: 11, color: theme.hintColor),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Voice call',
            icon: const Icon(Icons.phone),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onStartCall?.call(widget.partnerUsername);
            },
          ),
          IconButton(
            tooltip: _showTranslation ? 'Showing translation' : 'Showing original',
            icon: Icon(_showTranslation ? Icons.translate : Icons.translate_outlined),
            onPressed: () =>
                setState(() => _showTranslation = !_showTranslation),
          ),
        ],
      ),
      body: Column(
        children: [
          _encryptionBanner(theme),
          Expanded(child: _body(theme)),
          _composer(theme),
        ],
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 40, color: theme.hintColor),
            const SizedBox(height: 10),
            Text('No messages yet.\nSay hello to ${widget.partnerName} 👋',
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.hintColor)),
          ],
        ),
      );
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i], theme),
    );
  }

  Widget _bubble(Map<String, dynamic> m, ThemeData theme) {
    final isMe = m['is_me'] == true;
    final original = (m['original_text'] as String?) ?? '';
    final translated = m['translated_text'] as String?;
    // Readers see the translation; the author always sees what they typed.
    final primary = (!isMe && _showTranslation && translated != null)
        ? translated
        : original;
    final secondary = (!isMe && _showTranslation && translated != null)
        ? original
        : (isMe && translated != null ? translated : null);

    final bg = isMe ? ConFriKaColors.oceanBlue : theme.colorScheme.surfaceContainerHighest;
    final fg = isMe ? Colors.white : theme.colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if ((m['message_type'] == 'image' || m['message_type'] == 'sticker') &&
                m['media_url'] != null) ...[
              ChatImage(
                mediaUrl: m['media_url'] as String,
                encrypted: m['is_encrypted'] == true,
                peerPub: _partnerPub,
              ),
              if (primary.isNotEmpty) const SizedBox(height: 6),
            ],
            if (primary.isNotEmpty)
              Text(primary, style: TextStyle(color: fg, fontSize: 15)),
            if (secondary != null && secondary.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                secondary,
                style: TextStyle(
                    color: fg.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontStyle: FontStyle.italic),
              ),
            ],
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _time(m['created_at'] as String?),
                  style: TextStyle(
                      color: fg.withValues(alpha: 0.6), fontSize: 10),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    m['is_read'] == true ? Icons.done_all : Icons.done,
                    size: 13,
                    color: m['is_read'] == true
                        ? const Color(0xFF7FD4FF)
                        : fg.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _composer(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 10, 6),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Emoji',
                    icon: Icon(_showEmoji
                        ? Icons.keyboard
                        : Icons.emoji_emotions_outlined),
                    onPressed: () {
                      if (!_showEmoji) FocusScope.of(context).unfocus();
                      setState(() => _showEmoji = !_showEmoji);
                    },
                  ),
                  IconButton(
                    tooltip: 'Send image',
                    icon: const Icon(Icons.image_outlined),
                    onPressed: _sending ? null : _pickAndSendImage,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _composeCtrl,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.send,
                      onTap: () {
                        if (_showEmoji) setState(() => _showEmoji = false);
                      },
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: 'Message ${widget.partnerName.split(' ').first}…',
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: ConFriKaColors.savannaGreen,
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _send,
                          ),
                  ),
                ],
              ),
            ),
            if (_showEmoji)
              SizedBox(
                height: 260,
                child: EmojiPicker(
                  textEditingController: _composeCtrl,
                  config: const Config(
                    height: 260,
                    checkPlatformCompatibility: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _encryptionBanner(ThemeData theme) {
    final enc = _encrypted;
    final color = enc ? ConFriKaColors.savannaGreen : ConFriKaColors.amberHighlight;
    final text = enc
        ? 'End-to-end encrypted · auto-translated into each person’s dialect'
        : 'Not encrypted yet — recipient hasn’t set up a key';
    return Container(
      width: double.infinity,
      color: color.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(enc ? Icons.lock : Icons.lock_open, size: 12, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: theme.hintColor),
                textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }

  static String _time(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final ampm = dt.hour < 12 ? 'AM' : 'PM';
    return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
  }
}

