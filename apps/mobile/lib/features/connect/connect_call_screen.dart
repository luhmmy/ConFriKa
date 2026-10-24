import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/user_avatar.dart';
import 'active_call_screen.dart';

/// The Calls tab: a simple dialer. Placing a call opens the full-screen
/// [ActiveCallScreen] (WhatsApp-style) which owns the WebRTC session.
class ConnectCallScreen extends StatefulWidget {
  final String? initialCallee;
  const ConnectCallScreen({super.key, this.initialCallee});

  @override
  State<ConnectCallScreen> createState() => _ConnectCallScreenState();
}

class _ConnectCallScreenState extends State<ConnectCallScreen> {
  final _calleeCtrl = TextEditingController();
  final _api = ConFriKaApiClient.instance;
  String? _error;
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialCallee != null) _calleeCtrl.text = widget.initialCallee!;
    _loadHistory();
  }

  @override
  void dispose() {
    _calleeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await _api.callHistory();
      if (mounted) setState(() => _history = rows.cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  void _call() {
    final callee = _calleeCtrl.text.trim();
    if (callee.isEmpty) {
      setState(() => _error = 'Enter a @username to call.');
      return;
    }
    setState(() => _error = null);
    _callUser(callee.startsWith('@') ? callee : '@$callee');
  }

  Future<void> _callUser(String handle) async {
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActiveCallScreen(calleeUsername: handle),
    ));
    _loadHistory(); // refresh after the call ends
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Voice Call',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text('Encrypted peer-to-peer WebRTC voice over STUN/TURN',
            style: TextStyle(fontSize: 12, color: theme.hintColor)),
        const SizedBox(height: 18),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _calleeCtrl,
                  textInputAction: TextInputAction.go,
                  onSubmitted: (_) => _call(),
                  decoration: InputDecoration(
                    labelText: 'Call @username',
                    prefixIcon: const Icon(Icons.alternate_email),
                    border:
                        OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_error!,
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 13)),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _call,
                    style: FilledButton.styleFrom(
                      backgroundColor: ConFriKaColors.savannaGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: const Icon(Icons.phone_in_talk),
                    label: const Text('Start Call',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        if (_history.isNotEmpty) ...[
          const Text('Recent calls',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          ..._history.map(_historyTile),
          const SizedBox(height: 12),
        ],
        Card(
          color: ConFriKaColors.oceanBlue.withValues(alpha: 0.05),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How calling works',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                SizedBox(height: 6),
                Text(
                  '• Audio is peer-to-peer via WebRTC; media never passes through our '
                  'servers (only signaling does).\n'
                  '• Calls are end-to-end encrypted by WebRTC (DTLS-SRTP).\n'
                  '• Live in-call speech translation: hearing the other person in '
                  'your language, in their voice, is being wired up next.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _historyTile(Map<String, dynamic> h) {
    final name = (h['other_username'] as String?)?.replaceFirst('@', '') ?? '';
    final missed = h['missed'] == true;
    final outgoing = h['direction'] == 'outgoing';
    final dur = (h['duration_seconds'] as num?)?.toInt() ?? 0;
    final icon = missed
        ? Icons.call_missed
        : (outgoing ? Icons.call_made : Icons.call_received);
    final color = missed
        ? Colors.redAccent
        : (outgoing ? ConFriKaColors.oceanBlue : ConFriKaColors.savannaGreen);
    final sub = missed
        ? 'Missed'
        : (outgoing ? 'Outgoing' : 'Incoming') +
            (dur > 0 ? ' · ${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}' : '');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: UserAvatar(name: name, radius: 20),
      title: Text('@$name',
          style: TextStyle(
              fontWeight: FontWeight.w600,
              color: missed ? Colors.redAccent : null)),
      subtitle: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(sub, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        const Spacer(),
        Text(_time(h['started_at'] as String?),
            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
      ]),
      trailing: IconButton(
        icon: const Icon(Icons.phone, color: ConFriKaColors.savannaGreen),
        onPressed: () => _callUser('@$name'),
      ),
    );
  }

  static String _time(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      return '$h:${dt.minute.toString().padLeft(2, '0')} ${dt.hour < 12 ? 'AM' : 'PM'}';
    }
    return '${dt.day}/${dt.month}';
  }
}
