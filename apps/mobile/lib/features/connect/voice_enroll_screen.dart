import 'dart:async';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/confrika_theme.dart';

/// Enroll a voice clone: the user reads a short passage, and the recording is
/// sent to the cloud voice service so live call translation can speak in their
/// own voice. One-time setup, stored as their voice_id.
class VoiceEnrollScreen extends StatefulWidget {
  const VoiceEnrollScreen({super.key});

  @override
  State<VoiceEnrollScreen> createState() => _VoiceEnrollScreenState();
}

class _VoiceEnrollScreenState extends State<VoiceEnrollScreen> {
  final _api = ConFriKaApiClient.instance;
  final _recorder = AudioRecorder();

  bool _recording = false;
  bool _busy = false;
  bool _enrolled = false;
  int _seconds = 0;
  String? _path;
  String? _status;
  Timer? _timer;

  static const _passage =
      'My name is my own, and my voice carries my language. '
      'Across rivers and cities, from the coast to the savanna, '
      'I speak so that all of Africa can understand me. '
      'Good morning, good afternoon, and good evening to every nation.';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final s = await _api.voiceStatus();
      if (mounted) {
        setState(() {
          _enrolled = s['enrolled'] == true;
          if (s['voice_service_configured'] != true) {
            _status = 'The voice service is not switched on yet.';
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleRecord() async {
    if (_recording) {
      _timer?.cancel();
      _path = await _recorder.stop();
      setState(() => _recording = false);
      return;
    }
    if (!await _recorder.hasPermission()) {
      setState(() => _status = 'Microphone permission is required.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_enroll.wav';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 22050, numChannels: 1),
      path: path,
    );
    setState(() {
      _recording = true;
      _seconds = 0;
      _path = null;
      _status = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= 40) _toggleRecord(); // auto-stop at 40s
    });
  }

  Future<void> _submit() async {
    if (_path == null || _seconds < 10) {
      setState(() => _status = 'Record at least 10 seconds of clear speech.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _api.enrollVoice(_path!);
      if (mounted) {
        setState(() {
          _enrolled = true;
          _busy = false;
          _status = 'Your translation voice is ready.';
        });
      }
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _status = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Translation voice')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_enrolled)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: ConFriKaColors.savannaGreen.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(children: [
                    Icon(Icons.check_circle, color: ConFriKaColors.savannaGreen),
                    SizedBox(width: 8),
                    Expanded(
                        child: Text('Voice enrolled. On calls, people can hear you '
                            'translated in your own voice.')),
                  ]),
                ),
              const SizedBox(height: 14),
              const Text('Read this aloud, clearly, in a quiet place:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(_passage, style: TextStyle(fontSize: 16, height: 1.5)),
              ),
              const SizedBox(height: 22),
              Center(
                child: Text(
                  _recording ? 'Recording  ${_seconds}s' : (_path != null ? 'Recorded ${_seconds}s' : 'Not recorded'),
                  style: TextStyle(color: Theme.of(context).hintColor),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _busy ? null : _toggleRecord,
                style: FilledButton.styleFrom(
                  backgroundColor: _recording ? Colors.redAccent : ConFriKaColors.oceanBlue,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: Icon(_recording ? Icons.stop : Icons.mic),
                label: Text(_recording ? 'Stop' : (_path != null ? 'Record again' : 'Start recording')),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
              const SizedBox(height: 14),
              FilledButton(
                onPressed: (_busy || _path == null) ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: ConFriKaColors.savannaGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(_enrolled ? 'Update my voice' : 'Create my voice',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
