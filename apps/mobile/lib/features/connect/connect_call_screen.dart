import 'package:flutter/material.dart';

import '../../core/theme/confrika_theme.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.initialCallee != null) _calleeCtrl.text = widget.initialCallee!;
  }

  @override
  void dispose() {
    _calleeCtrl.dispose();
    super.dispose();
  }

  void _call() {
    final callee = _calleeCtrl.text.trim();
    if (callee.isEmpty) {
      setState(() => _error = 'Enter a @username to call.');
      return;
    }
    setState(() => _error = null);
    final handle = callee.startsWith('@') ? callee : '@$callee';
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ActiveCallScreen(calleeUsername: handle),
    ));
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
        const SizedBox(height: 12),
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
}
