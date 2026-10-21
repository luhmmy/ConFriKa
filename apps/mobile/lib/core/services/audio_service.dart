import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// ConFriKa Audio Service
/// Handles voice note audio recording, playback, and pitch/tone sample reproduction.
class ConFriKaAudioService {
  static final ConFriKaAudioService _instance = ConFriKaAudioService._internal();
  factory ConFriKaAudioService() => _instance;
  ConFriKaAudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final AudioRecorder _audioRecorder = AudioRecorder();

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  String? _currentRecordingPath;
  String? get currentRecordingPath => _currentRecordingPath;

  Function(PlayerState state)? onPlayerStateChanged;
  Function(Duration position)? onPositionChanged;
  Function(Duration duration)? onDurationChanged;

  void initialize() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      onPlayerStateChanged?.call(state);
    });

    _audioPlayer.onPositionChanged.listen((pos) {
      onPositionChanged?.call(pos);
    });

    _audioPlayer.onDurationChanged.listen((dur) {
      onDurationChanged?.call(dur);
    });
  }

  /// Request microphone permission and start recording voice note
  Future<bool> startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final fileName = 'confrika_voice_${const Uuid().v4()}.m4a';
        _currentRecordingPath = '${dir.path}/$fileName';

        const config = RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 32000, // 32kbps AAC is ultra-lightweight for African mobile bandwidth
          sampleRate: 22050,
        );

        await _audioRecorder.start(config, path: _currentRecordingPath!);
        _isRecording = true;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to start recording: $e');
      return false;
    }
  }

  /// Start a 16 kHz mono WAV recording (used for F0 / pitch analysis).
  Future<bool> startWavRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        _currentRecordingPath = '${dir.path}/confrika_pitch_${const Uuid().v4()}.wav';
        const config = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        );
        await _audioRecorder.start(config, path: _currentRecordingPath!);
        _isRecording = true;
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Failed to start WAV recording: $e');
      return false;
    }
  }

  /// Stop current recording and return the recorded file path
  Future<String?> stopRecording() async {
    try {
      if (!_isRecording) return null;
      final path = await _audioRecorder.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      debugPrint('Failed to stop recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Play audio from local file or remote URL (e.g. voice notes, speech synthesis)
  Future<void> playAudio(String sourcePath, {bool isUrl = false}) async {
    try {
      await _audioPlayer.stop();
      if (isUrl) {
        await _audioPlayer.play(UrlSource(sourcePath));
      } else {
        await _audioPlayer.play(DeviceFileSource(sourcePath));
      }
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  /// Stop current playback
  Future<void> stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  /// Pause current playback
  Future<void> pausePlayback() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  /// Resume playback
  Future<void> resumePlayback() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      debugPrint('Error resuming audio: $e');
    }
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _audioPlayer.dispose();
    await _audioRecorder.dispose();
  }
}
