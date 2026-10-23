import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/confrika_theme.dart';
import 'global_spaces_chat_screen.dart';

/// Hub listing joinable communities (Business & Tech, Culture & Music, …).
/// Users can join/leave, create their own, and open a community's live feed.
class CommunitiesScreen extends StatefulWidget {
  final void Function(String username) onStartCall;
  const CommunitiesScreen({super.key, required this.onStartCall});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  final _api = ConFriKaApiClient.instance;
  List<Map<String, dynamic>> _communities = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await _api.communities();
      if (!mounted) return;
      setState(() {
        _communities = rows.cast<Map<String, dynamic>>();
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

  Future<void> _toggleJoin(Map<String, dynamic> c) async {
    final slug = c['slug'] as String;
    final joined = c['joined'] == true;
    setState(() => c['joined'] = !joined); // optimistic
    try {
      if (joined) {
        await _api.leaveCommunity(slug);
      } else {
        await _api.joinCommunity(slug);
      }
      _load();
    } on ApiException catch (e) {
      setState(() => c['joined'] = joined); // revert
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  void _open(Map<String, dynamic> c) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GlobalSpacesChatScreen(
        onStartCall: widget.onStartCall,
        communitySlug: c['slug'] as String,
        communityName: c['name'] as String,
        communityIcon: (c['icon'] as String?) ?? '🌍',
        canPost: c['joined'] == true,
      ),
    ));
  }

  Future<void> _createDialog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final iconCtrl = TextEditingController(text: '🌍');
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create community'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: iconCtrl,
                maxLength: 2,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                    labelText: 'Icon (emoji)', counterText: ''),
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().length < 3) return;
              try {
                await _api.createCommunity(
                  name: nameCtrl.text.trim(),
                  description: descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  icon: iconCtrl.text.trim().isEmpty ? '🌍' : iconCtrl.text.trim(),
                );
                if (ctx.mounted) Navigator.pop(ctx, true);
              } on ApiException catch (e) {
                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx)
                      .showSnackBar(SnackBar(content: Text(e.message)));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (created == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Communities')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: ConFriKaColors.savannaGreen,
        onPressed: _createDialog,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Create', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _communities.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) => _tile(_communities[i], theme),
                  ),
                ),
    );
  }

  Widget _tile(Map<String, dynamic> c, ThemeData theme) {
    final joined = c['joined'] == true;
    final isDefault = c['is_default'] == true;
    final count = (c['member_count'] as num?)?.toInt() ?? 0;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: ConFriKaColors.oceanBlue.withValues(alpha: 0.12),
        child: Text((c['icon'] as String?) ?? '🌍',
            style: const TextStyle(fontSize: 22)),
      ),
      title: Text(c['name'] as String,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((c['description'] as String?)?.isNotEmpty == true)
            Text(c['description'] as String,
                maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('$count member${count == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 11, color: theme.hintColor)),
        ],
      ),
      trailing: isDefault
          ? Chip(
              label: const Text('Default', style: TextStyle(fontSize: 11)),
              backgroundColor: ConFriKaColors.savannaGreen.withValues(alpha: 0.15),
              side: BorderSide.none,
            )
          : OutlinedButton(
              onPressed: () => _toggleJoin(c),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    joined ? theme.hintColor : ConFriKaColors.oceanBlue,
                side: BorderSide(
                    color: joined
                        ? theme.dividerColor
                        : ConFriKaColors.oceanBlue.withValues(alpha: 0.5)),
              ),
              child: Text(joined ? 'Joined' : 'Join'),
            ),
      onTap: () => _open(c),
    );
  }
}
