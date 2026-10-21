import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/services/audio_service.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

class LearnAndToneCoachScreen extends StatefulWidget {
  const LearnAndToneCoachScreen({super.key});

  @override
  State<LearnAndToneCoachScreen> createState() => _LearnAndToneCoachScreenState();
}

class _LearnAndToneCoachScreenState extends State<LearnAndToneCoachScreen> {
  final _api = ConFriKaApiClient.instance;
  final _audio = ConFriKaAudioService();

  List<dynamic> _pairs = [];
  bool _loading = true;
  String? _error;
  String? _activeId;
  bool _recording = false;
  bool _analyzing = false;
  Map<String, dynamic>? _lastResult; // calibration result for _activeId

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pairs = await _api.minimalPairs();
      if (!mounted) return;
      setState(() {
        _pairs = pairs;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  Future<void> _recordAndAnalyze(Map<String, dynamic> pair) async {
    final id = pair['id'] as String;
    if (_recording) {
      // Stop and analyze.
      setState(() {
        _recording = false;
        _analyzing = true;
      });
      final path = await _audio.stopRecording();
      if (path == null) {
        setState(() {
          _analyzing = false;
          _error = 'Recording failed.';
        });
        return;
      }
      try {
        final baseline = ConFriKaSession.instance.f0BaselineHz;
        final pitch = await _api.analyzePitch(path, baselineF0Hz: baseline);
        final contour = ((pitch['semitone_contour'] as List?) ?? [])
            .map((e) => (e as num).toDouble())
            .toList();
        final cal = await _api.calibrateTone(
          targetWordId: id,
          learnerSemitones: contour.isEmpty ? [0.0] : contour,
          baselineF0Hz: baseline,
        );
        cal['_voiced_ratio'] = pitch['voiced_ratio'];
        cal['_mean_f0'] = pitch['mean_f0_hz'];
        if (!mounted) return;
        setState(() {
          _lastResult = cal;
          _analyzing = false;
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          _analyzing = false;
          _error = e.message;
        });
      }
    } else {
      final ok = await _audio.startWavRecording();
      if (!ok) {
        setState(() => _error = 'Microphone permission needed to practice tones.');
        return;
      }
      setState(() {
        _recording = true;
        _activeId = id;
        _lastResult = null;
        _error = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _pairs.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_error!, style: const TextStyle(color: Colors.redAccent))));
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Tonal Coach',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const Text('Practice tonal minimal pairs — record yourself and get a real pitch match score',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ),
        const SizedBox(height: 6),
        ..._pairs.map((p) => _pairCard(p as Map<String, dynamic>)),
      ],
    );
  }

  Widget _pairCard(Map<String, dynamic> p) {
    final id = p['id'] as String;
    final isActive = _activeId == id;
    final targets = ((p['target_semitones'] as List?) ?? []).map((e) => (e as num).toDouble()).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(p['diacritized_word']?.toString() ?? '',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: ConFriKaColors.oceanBlue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(p['tone_pattern']?.toString() ?? '',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: ConFriKaColors.oceanBlue)),
                ),
              ],
            ),
            Text(p['meaning']?.toString() ?? '',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _ContourBar(values: targets),
            const SizedBox(height: 6),
            Text(p['coaching_tip']?.toString() ?? '',
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_analyzing) ? null : () => _recordAndAnalyze(p),
                style: FilledButton.styleFrom(
                  backgroundColor: (isActive && _recording)
                      ? Colors.redAccent
                      : ConFriKaColors.savannaGreen,
                ),
                icon: Icon((isActive && _recording) ? Icons.stop : Icons.mic, size: 18),
                label: Text((isActive && _recording)
                    ? 'Stop & analyze'
                    : (isActive && _analyzing ? 'Analyzing...' : 'Record & check pitch')),
              ),
            ),
            if (isActive && _lastResult != null) _resultPanel(_lastResult!),
          ],
        ),
      ),
    );
  }

  Widget _resultPanel(Map<String, dynamic> r) {
    final score = ((r['match_score_pct'] as num?) ?? 0).toDouble();
    final acceptable = r['is_acceptable_tone'] == true;
    final voiced = ((r['_voiced_ratio'] as num?) ?? 0).toDouble();
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (acceptable ? ConFriKaColors.savannaGreen : ConFriKaColors.sunsetOrange)
            .withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Match score: ${score.toStringAsFixed(1)}%',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: acceptable ? ConFriKaColors.savannaGreen : ConFriKaColors.sunsetOrange)),
          const SizedBox(height: 4),
          Text(r['feedback']?.toString() ?? '', style: const TextStyle(fontSize: 12)),
          if (voiced < 0.2)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Little voiced audio detected — speak clearly into the mic (emulators often have no mic input).',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}

/// Simple semitone contour visualization.
class _ContourBar extends StatelessWidget {
  final List<double> values;
  const _ContourBar({required this.values});

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: values.map((v) {
          // Map -4..+4 semitones to a bar height.
          final norm = ((v + 4) / 8).clamp(0.0, 1.0);
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  height: 6 + norm * 30,
                  decoration: BoxDecoration(
                    color: ConFriKaColors.oceanBlue,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
