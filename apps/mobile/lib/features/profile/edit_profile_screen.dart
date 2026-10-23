import 'package:flutter/material.dart';

import '../../core/constants/african_countries.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _originCtrl = TextEditingController();
  late AfricanCountryInfo _country;
  late String _dialect;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final s = ConFriKaSession.instance;
    _nameCtrl.text = s.displayName;
    _originCtrl.text = (s.user?['origin_region'] as String?) ?? '';
    _country = kAll54AfricanCountries.firstWhere(
      (c) => c.code == s.countryCode,
      orElse: () => kAll54AfricanCountries.firstWhere(
        (c) => c.code == 'NG',
        orElse: () => kAll54AfricanCountries.first,
      ),
    );
    final mineFirst = s.primaryDialect.split(' ').first;
    _dialect = _country.dialects.firstWhere(
      (d) => s.primaryDialect.contains(d) || d.contains(mineFirst),
      orElse: () => _country.dialects.first,
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _originCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your full name.');
      return;
    }
    if (_originCtrl.text.trim().length < 2) {
      setState(() => _error = 'Enter your origin (state / city).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ConFriKaApiClient.instance.updateProfile({
        'full_name': _nameCtrl.text.trim(),
        'origin_region': _originCtrl.text.trim(),
        'country_code': _country.code,
        'primary_dialect': _dialect,
      });
      await ConFriKaSession.instance.updateUser(updated);
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated.')),
        );
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<AfricanCountryInfo>(
                initialValue: _country,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Country',
                  prefixIcon: Icon(Icons.public),
                  border: OutlineInputBorder(),
                ),
                items: kAll54AfricanCountries
                    .map((c) => DropdownMenuItem(
                          value: c,
                          child: Text('${c.flag} ${c.name}',
                              overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (c) {
                  if (c == null) return;
                  setState(() {
                    _country = c;
                    _dialect = c.dialects.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _originCtrl,
                decoration: const InputDecoration(
                  labelText: 'Origin (state / city)',
                  prefixIcon: Icon(Icons.place_outlined),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue:
                    _country.dialects.contains(_dialect) ? _dialect : _country.dialects.first,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Primary dialect',
                  prefixIcon: Icon(Icons.record_voice_over_outlined),
                  border: OutlineInputBorder(),
                ),
                items: _country.dialects
                    .map((d) => DropdownMenuItem(
                          value: d,
                          child: Text(d, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: (d) => setState(() => _dialect = d ?? _dialect),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: ConFriKaColors.savannaGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
