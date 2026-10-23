import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:audioplayers/audioplayers.dart';

/// ConFriKa Audio Service — voice-note and translated-audio playback.
class ConFriKaAudioService {
  static final ConFriKaAudioService _instance = ConFriKaAudioService._internal();
  factory ConFriKaAudioService() => _instance;
  ConFriKaAudioService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Function(PlayerState state)? onPlayerStateChanged;
  Function(Duration position)? onPositionChanged;
  Function(Duration duration)? onDurationChanged;

  void initialize() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      _isPlaying = state == PlayerState.playing;
      onPlayerStateChanged?.call(state);
    });
    _audioPlayer.onPositionChanged.listen((pos) => onPositionChanged?.call(pos));
    _audioPlayer.onDurationChanged.listen((dur) => onDurationChanged?.call(dur));
  }

  /// Play audio from a local file or a remote URL.
  Future<void> playAudio(String sourcePath, {bool isUrl = false}) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(isUrl ? UrlSource(sourcePath) : DeviceFileSource(sourcePath));
    } catch (e) {
      debugPrint('Error playing audio: $e');
    }
  }

  Future<void> stopPlayback() async {
    try {
      await _audioPlayer.stop();
      _isPlaying = false;
    } catch (e) {
      debugPrint('Error stopping audio: $e');
    }
  }

  Future<void> pausePlayback() async {
    try {
      await _audioPlayer.pause();
    } catch (e) {
      debugPrint('Error pausing audio: $e');
    }
  }

  Future<void> resumePlayback() async {
    try {
      await _audioPlayer.resume();
    } catch (e) {
      debugPrint('Error resuming audio: $e');
    }
  }

  Future<void> dispose() async {
    await _audioPlayer.dispose();
  }
}
