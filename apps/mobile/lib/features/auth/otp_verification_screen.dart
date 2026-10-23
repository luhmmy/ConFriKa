import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';
import '../../core/widgets/confrika_brand_widgets.dart';

/// Email verification screen shown after signup (or when an unverified user
/// tries to log in). Verifying the OTP signs the user in.
class OtpVerificationScreen extends StatefulWidget {
  final String email;
  final String? devCode; // present only in dev when email isn't configured

  const OtpVerificationScreen({super.key, required this.email, this.devCode});

  @override
  State<OtpVerificationScreen> createState() => _OtpVerificationScreenState();
}

class _OtpVerificationScreenState extends State<OtpVerificationScreen> {
  final _codeCtrl = TextEditingController();
  bool _busy = false;
  bool _resending = false;
  String? _error;
  String? _info;

  @override
  void initState() {
    super.initState();
    if (widget.devCode != null) {
      _codeCtrl.text = widget.devCode!;
      _info = 'Dev mode: code pre-filled (email not configured).';
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _error = 'Enter the code from your email.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await ConFriKaApiClient.instance
          .verifyEmail(email: widget.email, code: code);
      await ConFriKaSession.instance.setAuthenticated(
        data['access_token'] as String,
        (data['user'] as Map).cast<String, dynamic>(),
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
      _info = null;
    });
    try {
      final res = await ConFriKaApiClient.instance.resendOtp(widget.email);
      final dev = res['debug_code'] as String?;
      setState(() {
        if (dev != null) _codeCtrl.text = dev;
        _info = dev != null
            ? 'Dev mode: new code pre-filled.'
            : 'A new code has been sent to ${widget.email}.';
      });
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: ConFriKaAppLogo(size: 56)),
              const SizedBox(height: 16),
              const Text('Enter verification code',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(
                'We sent a ${6}-digit code to ${widget.email}. Enter it below to '
                'finish creating your account.',
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                _banner(_error!, Colors.red),
                const SizedBox(height: 12),
              ],
              if (_info != null) ...[
                _banner(_info!, ConFriKaColors.oceanBlue),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _codeCtrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 10),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onSubmitted: (_) => _verify(),
                decoration: const InputDecoration(
                  counterText: '',
                  hintText: '••••••',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _busy ? null : _verify,
                style: FilledButton.styleFrom(
                  backgroundColor: ConFriKaColors.savannaGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Verify & Continue',
                        style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _resending ? null : _resend,
                child: Text(_resending ? 'Sending…' : "Didn't get it? Resend code"),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _banner(String text, Color color) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(text, style: TextStyle(color: color, fontSize: 12)),
      );
}
