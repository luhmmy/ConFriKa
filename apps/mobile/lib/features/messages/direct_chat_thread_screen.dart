import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

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

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _showTranslation = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
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
    try {
      await _api.sendDirectMessage(
        recipientUsername: widget.partnerUsername,
        text: text,
        sourceDialect: ConFriKaSession.instance.primaryDialect,
        autoTranslate: _showTranslation,
      );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: ConFriKaColors.oceanBlue,
              child: Text(
                _initials(widget.partnerName),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
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
          const _EncryptionBanner(),
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
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _composeCtrl,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message ${widget.partnerName.split(' ').first}…',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '·';
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
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

class _EncryptionBanner extends StatelessWidget {
  const _EncryptionBanner();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ConFriKaColors.amberHighlight.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.lock, size: 12, color: ConFriKaColors.amberHighlight),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Private chat — auto-translated into each person’s dialect',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).hintColor),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
