import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

class GlobalSpacesChatScreen extends StatefulWidget {
  final ValueChanged<String> onStartCall;
  const GlobalSpacesChatScreen({super.key, required this.onStartCall});

  @override
  State<GlobalSpacesChatScreen> createState() => _GlobalSpacesChatScreenState();
}

class _GlobalSpacesChatScreenState extends State<GlobalSpacesChatScreen> {
  final _api = ConFriKaApiClient.instance;
  final _composer = TextEditingController();

  bool _dmMode = false;
  String _channel = 'all';
  bool _showOriginal = false;
  bool _autoTranslate = true;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int? _onlineCount;

  List<dynamic> _spaces = [];
  List<dynamic> _contacts = [];
  String? _activeDm;
  List<dynamic> _thread = [];

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
          } else if (data['type'] == 'spaces_message' && !_dmMode) {
            _loadSpaces();
          } else if (data['type'] == 'direct_message' && _dmMode) {
            if (data['sender'] == _activeDm) _loadThread();
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

  Future<void> _loadContacts() async {
    try {
      final list = await _api.contacts();
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _activeDm ??= list.isNotEmpty ? list.first['username'] as String : null;
      });
      if (_activeDm != null) _loadThread();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _loadThread() async {
    if (_activeDm == null) return;
    try {
      final list = await _api.directMessages(_activeDm!);
      if (!mounted) return;
      setState(() => _thread = list);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    final dialect = ConFriKaSession.instance.primaryDialect;
    try {
      if (_dmMode) {
        if (_activeDm == null) return;
        await _api.sendDirectMessage(
          recipientUsername: _activeDm!,
          text: text,
          sourceDialect: dialect,
          autoTranslate: _autoTranslate,
        );
        _composer.clear();
        await _loadThread();
      } else {
        await _api.postSpaces(
          text: text,
          sourceDialect: dialect,
          channel: _channel,
          autoTranslate: _autoTranslate,
        );
        _composer.clear();
        await _loadSpaces();
      }
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, icon: Icon(Icons.public, size: 15), label: Text('Global')),
                ButtonSegment(value: true, icon: Icon(Icons.lock_outline, size: 15), label: Text('Direct')),
              ],
              selected: {_dmMode},
              onSelectionChanged: (s) {
                setState(() => _dmMode = s.first);
                if (_dmMode && _contacts.isEmpty) {
                  _loadContacts();
                } else if (!_dmMode) {
                  _loadSpaces();
                }
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _dmMode ? 'Direct messages' : 'Global Spaces',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              if (_onlineCount != null && !_dmMode)
                Text('$_onlineCount online',
                    style: const TextStyle(
                        color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        SegmentedButtonsRow(
          showOriginal: _showOriginal,
          onChanged: (v) => setState(() => _showOriginal = v),
        ),
        if (!_dmMode) _channelPills(),
        if (_dmMode) _contactPills(),
        Expanded(child: _buildList()),
        _composerBar(),
      ],
    );
  }

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

  Widget _contactPills() {
    if (_contacts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Add contacts on the Home tab to start a direct chat.',
            style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: _contacts.map((c) {
          final handle = c['username'] as String;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text('${c['name']} ($handle)'),
              selected: handle == _activeDm,
              onSelected: (_) {
                setState(() => _activeDm = handle);
                _loadThread();
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && !_dmMode) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent))));
    }
    final items = _dmMode ? _thread : _spaces;
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _dmMode
                ? 'No messages yet. Say hello — your message is auto-translated into their dialect.'
                : 'No messages in this space yet. Be the first to post!',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, i) => _messageCard(items[i] as Map<String, dynamic>),
    );
  }

  Widget _messageCard(Map<String, dynamic> m) {
    final isMe = m['is_me'] == true;
    final original = m['original_text']?.toString() ?? '';
    final translated = m['translated_text']?.toString() ?? '';
    final body = _showOriginal || translated.isEmpty ? original : translated;
    final name = m['sender_name']?.toString() ?? '';
    final location = m['sender_location']?.toString() ?? m['sender_username']?.toString() ?? '';
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
                  if (!isMe && !_dmMode)
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
                    fontSize: 11, color: ConFriKaColors.sunsetOrange, fontWeight: FontWeight.w600),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
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
                    hintText: _dmMode ? 'Message $_activeDm...' : 'Post to Global Spaces...',
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _sending ? null : _send,
                style: FilledButton.styleFrom(backgroundColor: ConFriKaColors.oceanBlue),
                child: _sending
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small translate-on/off control reused in the Spaces header.
class SegmentedButtonsRow extends StatelessWidget {
  final bool showOriginal;
  final ValueChanged<bool> onChanged;
  const SegmentedButtonsRow({super.key, required this.showOriginal, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, icon: Icon(Icons.translate, size: 15), label: Text('Translated')),
            ButtonSegment(value: true, icon: Icon(Icons.record_voice_over, size: 15), label: Text('Original')),
          ],
          selected: {showOriginal},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    );
  }
}
