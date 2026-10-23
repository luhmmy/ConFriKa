import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

/// The public, Pan-African broadcast feed — deliberately separate from private
/// Direct Messages. Anyone can post; everything is auto-translated for readers.
class GlobalSpacesChatScreen extends StatefulWidget {
  final ValueChanged<String> onStartCall;
  const GlobalSpacesChatScreen({super.key, required this.onStartCall});

  @override
  State<GlobalSpacesChatScreen> createState() => _GlobalSpacesChatScreenState();
}

class _GlobalSpacesChatScreenState extends State<GlobalSpacesChatScreen> {
  final _api = ConFriKaApiClient.instance;
  final _composer = TextEditingController();

  String _channel = 'all';
  bool _showOriginal = false;
  bool _autoTranslate = true;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int? _onlineCount;

  List<dynamic> _spaces = [];
  WebSocketChannel? _ws;

  @override
  void initState() {
    super.initState();
    _loadSpaces();
    _connectWs();
  }

  @override
  void dispose() {
    _composer.dispose();
    _ws?.sink.close();
    super.dispose();
  }

  void _connectWs() {
    final token = _api.authToken;
    if (token == null) return;
    try {
      _ws = WebSocketChannel.connect(
        Uri.parse('${AppConfig.wsBaseUrl}/ws/chat?token=$token'),
      );
      _ws!.stream.listen((event) {
        try {
          final data = jsonDecode(event as String) as Map<String, dynamic>;
          if (data['type'] == 'presence_update') {
            setState(() => _onlineCount = data['online_count'] as int?);
          } else if (data['type'] == 'spaces_message') {
            _loadSpaces();
          }
        } catch (_) {}
      }, onError: (_) {}, cancelOnError: false);
    } catch (_) {}
  }

  Future<void> _loadSpaces() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.spaces(channel: _channel);
      if (!mounted) return;
      setState(() {
        _spaces = list;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _api.postSpaces(
        text: text,
        sourceDialect: ConFriKaSession.instance.primaryDialect,
        channel: _channel,
        autoTranslate: _autoTranslate,
      );
      _composer.clear();
      await _loadSpaces();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Global Spaces'),
        actions: [
          if (_onlineCount != null)
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Center(
                child: Text('$_onlineCount online',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
            child: Text(
              'Share voice notes & messages across Africa — auto-translated for everyone.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
            ),
          ),
          _translateToggle(),
          _channelPills(),
          Expanded(child: _buildList()),
          _composerBar(),
        ],
      ),
    );
  }

  Widget _translateToggle() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.translate, size: 15),
                  label: Text('Translated')),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.record_voice_over, size: 15),
                  label: Text('Original')),
            ],
            selected: {_showOriginal},
            onSelectionChanged: (s) => setState(() => _showOriginal = s.first),
          ),
        ),
      );

  Widget _channelPills() => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            for (final ch in const [
              ['all', '🌍 All'],
              ['trade', '💼 Business & Tech'],
              ['culture', '🎶 Culture & Music'],
            ])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(ch[1]),
                  selected: _channel == ch[0],
                  onSelected: (_) {
                    setState(() => _channel = ch[0]);
                    _loadSpaces();
                  },
                ),
              ),
          ],
        ),
      );

  Widget _buildList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent))));
    }
    if (_spaces.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No messages in this space yet. Be the first to post!',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSpaces,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _spaces.length,
        itemBuilder: (context, i) => _messageCard(_spaces[i] as Map<String, dynamic>),
      ),
    );
  }

  Widget _messageCard(Map<String, dynamic> m) {
    final isMe = m['is_me'] == true;
    final original = m['original_text']?.toString() ?? '';
    final translated = m['translated_text']?.toString() ?? '';
    final body = _showOriginal || translated.isEmpty ? original : translated;
    final name = m['sender_name']?.toString() ?? '';
    final location =
        m['sender_location']?.toString() ?? m['sender_username']?.toString() ?? '';
    final dialect = m['dialect_name']?.toString() ?? '';
    final isVoice = m['message_type'] == 'voicenote';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        color: isMe ? ConFriKaColors.oceanBlue.withValues(alpha: 0.06) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text('$name · $location',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: ConFriKaColors.oceanBlue),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (!isMe)
                    TextButton.icon(
                      onPressed: () =>
                          widget.onStartCall(m['sender_username']?.toString() ?? ''),
                      icon: const Icon(Icons.phone_in_talk, size: 14),
                      label: const Text('Call', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
              Text(
                isVoice ? '🎙️ Voice note · $dialect' : '💬 $dialect',
                style: const TextStyle(
                    fontSize: 11,
                    color: ConFriKaColors.sunsetOrange,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(body.isEmpty ? '—' : body,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (translated.isNotEmpty && original.isNotEmpty)
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    _showOriginal ? 'showing original ($dialect)' : 'showing translation',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
          children: [
            Row(
              children: [
                Checkbox(
                  value: _autoTranslate,
                  onChanged: (v) => setState(() => _autoTranslate = v ?? true),
                  visualDensity: VisualDensity.compact,
                ),
                const Text('Auto-translate my message',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Post to Global Spaces…',
                      isDense: true,
                      border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _sending ? null : _send,
                  style:
                      FilledButton.styleFrom(backgroundColor: ConFriKaColors.oceanBlue),
                  child: _sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
