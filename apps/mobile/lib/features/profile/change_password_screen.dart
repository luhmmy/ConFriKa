import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/confrika_theme.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();

  bool _busy = false;
  bool _codeSent = false;
  String? _error;
  String? _info;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String? _passwordError(String v) {
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(v)) return 'Add an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(v)) return 'Add a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(v)) return 'Add a number';
    return null;
  }

  /// Validate the passwords locally before we bother emailing a code.
  String? _validatePasswords() {
    if (_currentCtrl.text.isEmpty) return 'Enter your current password.';
    final perr = _passwordError(_newCtrl.text);
    if (perr != null) return perr;
    if (_newCtrl.text != _confirmCtrl.text) return 'New passwords do not match.';
    return null;
  }

  Future<void> _sendCode() async {
    final err = _validatePasswords();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    try {
      final res =
          await ConFriKaApiClient.instance.requestChangePasswordOtp();
      final debugCode = res['debug_code'] as String?;
      setState(() {
        _codeSent = true;
        _info = debugCode != null
            ? 'Dev mode: your code is $debugCode'
            : 'We emailed a 6-digit code to confirm this change.';
        if (debugCode != null) _codeCtrl.text = debugCode;
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final err = _validatePasswords();
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    if (_codeCtrl.text.trim().length < 4) {
      setState(() => _error = 'Enter the code we emailed you.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ConFriKaApiClient.instance.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
        code: _codeCtrl.text.trim(),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed.')),
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
      appBar: AppBar(title: const Text('Change password')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                _banner(_error!, Colors.red),
                const SizedBox(height: 12),
              ],
              if (_info != null) ...[
                _banner(_info!, ConFriKaColors.oceanBlue),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _currentCtrl,
                obscureText: true,
                enabled: !_codeSent,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _newCtrl,
                obscureText: true,
                enabled: !_codeSent,
                decoration: const InputDecoration(
                  labelText: 'New password',
                  helperText: 'Min 8 chars, with uppercase, lowercase & a number',
                  prefixIcon: Icon(Icons.lock_reset),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmCtrl,
                obscureText: true,
                enabled: !_codeSent,
                decoration: const InputDecoration(
                  labelText: 'Confirm new password',
                  prefixIcon: Icon(Icons.lock_outline),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              if (!_codeSent)
                FilledButton(
                  onPressed: _busy ? null : _sendCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: ConFriKaColors.oceanBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const _Spinner()
                      : const Text('Email me a verification code',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                )
              else ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    prefixIcon: Icon(Icons.mark_email_read_outlined),
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _busy ? null : _sendCode,
                    child: const Text('Resend code'),
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: ConFriKaColors.oceanBlue,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _busy
                      ? const _Spinner()
                      : const Text('Confirm & change password',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12)),
      );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
