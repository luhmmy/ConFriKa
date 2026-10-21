import 'package:flutter/material.dart';

import '../../core/constants/african_countries.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/confrika_brand_widgets.dart';

class ConFriKaAuthScreen extends StatefulWidget {
  const ConFriKaAuthScreen({super.key});

  @override
  State<ConFriKaAuthScreen> createState() => _ConFriKaAuthScreenState();
}

class _ConFriKaAuthScreenState extends State<ConFriKaAuthScreen> {
  bool _isSignUpMode = true;
  bool _busy = false;
  String? _error;
  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _originController = TextEditingController();
  final _loginIdentifierController = TextEditingController();
  final _loginPasswordController = TextEditingController();

  late AfricanCountryInfo _selectedCountry;
  late String _selectedDialect;

  @override
  void initState() {
    super.initState();
    _selectedCountry = kAll54AfricanCountries.firstWhere(
      (c) => c.code == 'NG',
      orElse: () => kAll54AfricanCountries.first,
    );
    _selectedDialect = kAll54AfricanDialects.firstWhere(
      (d) => d.contains(_selectedCountry.dialects.first),
      orElse: () => kAll54AfricanDialects.first,
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    _usernameController.dispose();
    _originController.dispose();
    _loginIdentifierController.dispose();
    _loginPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit(Future<Map<String, dynamic>> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await action();
      await ConFriKaSession.instance.setAuthenticated(
        data['access_token'] as String,
        (data['user'] as Map).cast<String, dynamic>(),
      );
      // The root AnimatedBuilder swaps to the shell automatically.
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _handleSignUp() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    _submit(() => ConFriKaApiClient.instance.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _fullNameController.text.trim(),
          username: _usernameController.text.trim(),
          countryCode: _selectedCountry.code,
          originRegion: _originController.text.trim(),
          primaryDialect: _selectedDialect,
        ));
  }

  void _handleLogin() {
    if (_loginIdentifierController.text.trim().isEmpty ||
        _loginPasswordController.text.isEmpty) {
      setState(() => _error = 'Enter your email/username and password.');
      return;
    }
    _submit(() => ConFriKaApiClient.instance.login(
          emailOrUsername: _loginIdentifierController.text.trim(),
          password: _loginPasswordController.text,
        ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConFriKaAppLogo(size: 30),
            SizedBox(width: 8),
            ConFriKaWordmark(fontSize: 18),
          ],
        ),
      ),
      body: ListView(
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
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'WELCOME TO CONFRIKA',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: ConFriKaColors.sunsetOrange,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isSignUpMode ? 'Create your account' : 'Welcome back',
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Many languages. One connection. One Africa.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.person_add_alt_1, size: 16),
                                label: Text('Sign Up'),
                              ),
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.login, size: 16),
                                label: Text('Log In'),
                              ),
                            ],
                            selected: {_isSignUpMode},
                            onSelectionChanged: (s) =>
                                setState(() => _isSignUpMode = s.first),
                          ),
                        ),
                        const SizedBox(height: 14),

                        if (_error != null) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],

                        if (_isSignUpMode) ..._signUpFields() else ..._loginFields(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _signUpFields() => [
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.mail_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (val) {
            final v = (val ?? '').trim();
            final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
            return ok ? null : 'Enter a valid email address';
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _passwordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password (min 8 characters)',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (val) =>
              (val == null || val.length < 8) ? 'Password must be at least 8 characters' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _fullNameController,
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.badge_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (val) =>
              (val == null || val.trim().length < 2) ? 'Full name is required' : null,
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _usernameController,
          decoration: const InputDecoration(
            labelText: 'Username (@handle)',
            prefixIcon: Icon(Icons.alternate_email),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (val) {
            final v = (val ?? '').trim().replaceAll('@', '');
            return RegExp(r'^[a-zA-Z0-9_]{3,38}$').hasMatch(v)
                ? null
                : '3-38 letters, digits, or underscore';
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<AfricanCountryInfo>(
          initialValue: _selectedCountry,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Country',
            prefixIcon: Icon(Icons.public),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: kAll54AfricanCountries
              .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c.displayLabel,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (c) {
            if (c == null) return;
            setState(() {
              _selectedCountry = c;
              _selectedDialect = kAll54AfricanDialects.firstWhere(
                (d) => d.contains(c.dialects.first),
                orElse: () => kAll54AfricanDialects.first,
              );
              _originController.text = '${c.name} (${c.region})';
            });
          },
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _originController,
          decoration: const InputDecoration(
            labelText: 'Origin (state / city)',
            prefixIcon: Icon(Icons.place_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          validator: (val) =>
              (val == null || val.trim().length < 2) ? 'Origin is required' : null,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _selectedDialect,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Local dialect',
            prefixIcon: Icon(Icons.record_voice_over_outlined),
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: kAll54AfricanDialects
              .map((d) => DropdownMenuItem(
                    value: d,
                    child: Text(d,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (d) => setState(() => _selectedDialect = d ?? _selectedDialect),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _handleSignUp,
            style: FilledButton.styleFrom(
              backgroundColor: ConFriKaColors.savannaGreen,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ];

  List<Widget> _loginFields() => [
        TextFormField(
          controller: _loginIdentifierController,
          decoration: const InputDecoration(
            labelText: 'Email or @username',
            prefixIcon: Icon(Icons.person_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _loginPasswordController,
          obscureText: true,
          onFieldSubmitted: (_) => _handleLogin(),
          decoration: const InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _busy ? null : _handleLogin,
            style: FilledButton.styleFrom(
              backgroundColor: ConFriKaColors.oceanBlue,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            icon: _busy
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.login, size: 18),
            label: const Text('Log In', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ];
}
