import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

/// Reachability / privacy controls so strangers from Global Spaces can't
/// suddenly call or spam a user — and image-sending can be turned off.
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  final _api = ConFriKaApiClient.instance;

  late String _calls;
  late String _messages;
  late bool _allowImages;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final u = ConFriKaSession.instance.user ?? {};
    _calls = (u['calls_privacy'] as String?) ?? 'everyone';
    _messages = (u['messages_privacy'] as String?) ?? 'everyone';
    _allowImages = (u['allow_images'] as bool?) ?? true;
  }

  Future<void> _save({
    String? calls,
    String? messages,
    bool? images,
  }) async {
    setState(() => _busy = true);
    try {
      final updated = await _api.updatePrivacy(
        callsPrivacy: calls,
        messagesPrivacy: messages,
        allowImages: images,
      );
      await ConFriKaSession.instance.updateUser(updated);
      if (mounted) {
        setState(() {
          _calls = (updated['calls_privacy'] as String?) ?? _calls;
          _messages = (updated['messages_privacy'] as String?) ?? _messages;
          _allowImages = (updated['allow_images'] as bool?) ?? _allowImages;
        });
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _sectionHeader('Who can call me', Icons.phone, theme),
            _choices(
              value: _calls,
              onChanged: (v) => _save(calls: v),
            ),
            const Divider(height: 24),
            _sectionHeader('Who can message me', Icons.chat_bubble_outline, theme),
            _choices(
              value: _messages,
              onChanged: (v) => _save(messages: v),
            ),
            const Divider(height: 24),
            SwitchListTile(
              secondary: const Icon(Icons.image_outlined),
              title: const Text('Allow others to send me images'),
              subtitle: const Text('Turn off to block incoming image messages'),
              value: _allowImages,
              activeThumbColor: ConFriKaColors.savannaGreen,
              onChanged: (v) => _save(images: v),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                '“My contacts” means only people you’ve added by @username can '
                'reach you. Changes apply immediately and are enforced on the server.',
                style: TextStyle(fontSize: 12, color: theme.hintColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, ThemeData theme) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: ConFriKaColors.oceanBlue),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _choices({
    required String value,
    required ValueChanged<String> onChanged,
  }) {
    const options = [
      ['everyone', 'Everyone', 'Anyone on ConFriKa'],
      ['contacts', 'My contacts', 'Only people you’ve added'],
      ['nobody', 'Nobody', 'No one can reach you this way'],
    ];
    return RadioGroup<String>(
      groupValue: value,
      onChanged: (v) {
        if (v != null && v != value) onChanged(v);
      },
      child: Column(
        children: [
          for (final o in options)
            RadioListTile<String>(
              value: o[0],
              activeColor: ConFriKaColors.oceanBlue,
              title: Text(o[1]),
              subtitle: Text(o[2], style: const TextStyle(fontSize: 12)),
              dense: true,
            ),
        ],
      ),
    );
  }
}
