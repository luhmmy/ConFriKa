import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/confrika_brand_widgets.dart';

class HomeScreen extends StatefulWidget {
  final VoidCallback onOpenGlobalSpaces;
  final VoidCallback onOpenToneCoach;
  final VoidCallback onOpenTranslate;
  final ValueChanged<String> onStartCall;

  const HomeScreen({
    super.key,
    required this.onOpenGlobalSpaces,
    required this.onOpenToneCoach,
    required this.onOpenTranslate,
    required this.onStartCall,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _api = ConFriKaApiClient.instance;
  final _usernameCtrl = TextEditingController();

  List<dynamic> _contacts = [];
  bool _loadingContacts = true;
  String? _contactsError;
  int? _onlineCount;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loadingContacts = true;
      _contactsError = null;
    });
    try {
      final results = await Future.wait([_api.contacts(), _api.health()]);
      if (!mounted) return;
      setState(() {
        _contacts = results[0] as List<dynamic>;
        _onlineCount = (results[1] as Map)['online_users'] as int?;
        _loadingContacts = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _contactsError = e.message;
        _loadingContacts = false;
      });
    }
  }

  Future<void> _addContact() async {
    final raw = _usernameCtrl.text.trim();
    if (raw.isEmpty) return;
    setState(() => _adding = true);
    try {
      await _api.addContact(raw);
      _usernameCtrl.clear();
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact added.')),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ConFriKaSession.instance;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ConFriKaTriColorBar(height: 6),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('WELCOME',
                          style: TextStyle(
                              color: ConFriKaColors.sunsetOrange,
                              fontSize: 11,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('${session.displayName} · ${session.username}',
                          style:
                              const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        'Dialect: ${session.primaryDialect}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _actionTile(Icons.translate, 'Translate',
                                ConFriKaColors.savannaGreen, widget.onOpenTranslate),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _actionTile(Icons.graphic_eq, 'Tone Coach',
                                ConFriKaColors.oceanBlue, widget.onOpenToneCoach),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Card(
            child: ListTile(
              onTap: widget.onOpenGlobalSpaces,
              leading: const CircleAvatar(
                backgroundColor: ConFriKaColors.oceanBlue,
                foregroundColor: Colors.white,
                child: Icon(Icons.public),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Global Spaces',
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                  ),
                  if (_onlineCount != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Color(0xFF10B981), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('$_onlineCount online',
                            style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                ],
              ),
              subtitle: const Text('Chat across Africa with live translation',
                  style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            ),
          ),
          const SizedBox(height: 18),

          const Text('Contacts & Calls',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _usernameCtrl,
                      onSubmitted: (_) => _addContact(),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: 'Add contact by @username...',
                        prefixIcon: const Icon(Icons.alternate_email, size: 16),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _adding ? null : _addContact,
                    style: FilledButton.styleFrom(
                        backgroundColor: ConFriKaColors.savannaGreen),
                    child: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('+ Add'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          if (_loadingContacts)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_contactsError != null)
            _infoCard('Could not load contacts: $_contactsError', Colors.redAccent)
          else if (_contacts.isEmpty)
            _infoCard(
                'No contacts yet. Add someone by their @username to start calling and messaging.',
                Colors.grey)
          else
            ..._contacts.map(_contactCard),

          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.phone_disabled, color: ConFriKaColors.sunsetOrange),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No-App Mobile Call',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('Direct PSTN carrier calling — in development',
                            style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ConFriKaColors.sunsetOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('In development',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: ConFriKaColors.sunsetOrange)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 6),
            Text(label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _infoCard(String text, Color color) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(text, style: TextStyle(color: color, fontSize: 13)),
        ),
      );

  Widget _contactCard(dynamic c) {
    final m = c as Map<String, dynamic>;
    final online = m['is_online'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFE0F2FE),
                  child: Text(m['initials']?.toString() ?? '·',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: ConFriKaColors.oceanBlue)),
                ),
                title: Text('${m['name']} (${m['username']})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                subtitle: Text(
                  '${m['flag'] ?? '🌍'} ${m['origin'] ?? ''} · ${m['dialect'] ?? ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online ? const Color(0xFF10B981) : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(online ? 'online' : 'offline',
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => widget.onStartCall(m['username'].toString()),
                  style: FilledButton.styleFrom(
                    backgroundColor: ConFriKaColors.oceanBlue,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.phone_in_talk, size: 18),
                  label: Text('Call ${m['username']}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
