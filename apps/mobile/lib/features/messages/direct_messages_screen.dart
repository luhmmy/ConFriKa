import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/user_avatar.dart';
import 'direct_chat_thread_screen.dart';

/// Private messaging hub: a WhatsApp-style list of 1-on-1 conversations.
/// Kept deliberately separate from the public Global Spaces feed.
class DirectMessagesScreen extends StatefulWidget {
  final void Function(String username)? onStartCall;
  final VoidCallback? onOpenGlobalSpaces;

  const DirectMessagesScreen({
    super.key,
    this.onStartCall,
    this.onOpenGlobalSpaces,
  });

  @override
  State<DirectMessagesScreen> createState() => _DirectMessagesScreenState();
}

class _DirectMessagesScreenState extends State<DirectMessagesScreen> {
  final _api = ConFriKaApiClient.instance;

  List<Map<String, dynamic>> _conversations = [];
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final rows = await _api.conversations();
      if (!mounted) return;
      setState(() {
        _conversations = rows.cast<Map<String, dynamic>>();
        _loading = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    }
  }

  Future<void> _openThread(String username, String name) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DirectChatThreadScreen(
        partnerUsername: username,
        partnerName: name,
        onStartCall: widget.onStartCall,
      ),
    ));
    _load(silent: true); // refresh previews/unread on return
  }

  Future<void> _newChat() async {
    final ctrl = TextEditingController();
    final username = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.alternate_email),
            hintText: 'username (e.g. amaka_enugu)',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Chat')),
        ],
      ),
    );
    if (username == null || username.isEmpty) return;
    final handle = username.startsWith('@') ? username : '@$username';
    if (mounted) _openThread(handle, handle.replaceFirst('@', ''));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: ConFriKaColors.savannaGreen,
        onPressed: _newChat,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: Column(
        children: [
          _header(theme),
          Expanded(child: _list(theme)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      child: Row(
        children: [
          const Text('Messages',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
          const Spacer(),
          // Clear route to the SEPARATE public feed.
          OutlinedButton.icon(
            onPressed: widget.onOpenGlobalSpaces,
            icon: const Icon(Icons.public, size: 18),
            label: const Text('Global'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ConFriKaColors.oceanBlue,
              side: BorderSide(
                  color: ConFriKaColors.oceanBlue.withValues(alpha: 0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red)));
    }
    if (_conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 90),
            Icon(Icons.forum_outlined, size: 54, color: theme.hintColor),
            const SizedBox(height: 14),
            Center(
              child: Text('No conversations yet',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: theme.hintColor)),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text('Tap the pencil to message someone by @username',
                  style: TextStyle(color: theme.hintColor)),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, indent: 76, color: theme.dividerColor),
        itemBuilder: (_, i) => _tile(_conversations[i], theme),
      ),
    );
  }

  Widget _tile(Map<String, dynamic> c, ThemeData theme) {
    final name = (c['partner_name'] as String?) ?? 'Unknown';
    final handle = (c['partner_username'] as String?) ?? '';
    final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
    final lastIsMe = c['last_is_me'] == true;
    final last = (c['last_message'] as String?) ?? '';
    final preview = lastIsMe ? 'You: $last' : last;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: UserAvatar(
        name: name,
        avatarUrl: c['partner_avatar'] as String?,
        radius: 26,
      ),
      title: Text(name,
          style: const TextStyle(fontWeight: FontWeight.w700),
          overflow: TextOverflow.ellipsis),
      subtitle: Text(preview,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: unread > 0 ? theme.colorScheme.onSurface : theme.hintColor,
            fontWeight: unread > 0 ? FontWeight.w600 : FontWeight.normal,
          )),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(_time(c['last_at'] as String?),
              style: TextStyle(
                  fontSize: 11,
                  color: unread > 0
                      ? ConFriKaColors.savannaGreen
                      : theme.hintColor)),
          const SizedBox(height: 6),
          if (unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: const BoxDecoration(
                color: ConFriKaColors.savannaGreen,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              child: Text('$unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            )
          else
            const SizedBox(height: 20),
        ],
      ),
      onTap: () => _openThread(handle, name),
    );
  }

  static String _time(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h:${dt.minute.toString().padLeft(2, '0')} $ampm';
    }
    return '${dt.day}/${dt.month}';
  }
}
