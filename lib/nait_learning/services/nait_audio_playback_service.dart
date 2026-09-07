import 'dart:io';
import '../../services/tts_service.dart';

class NaitAudioPlaybackService {
  final TtsService _ttsService;

  NaitAudioPlaybackService({TtsService? ttsService})
      : _ttsService = ttsService ?? TtsService();

  String? _currentlyPlayingPath;
  String? get currentlyPlayingPath => _currentlyPlayingPath;

  bool get isPlaying => _ttsService.isPlaying;

  /// Plays a local WAV audio clip (or weekly listening pack) through the existing
  /// TtsService safety-checked route.
  Future<void> playWav(String wavPath) async {
    final file = File(wavPath);
    if (!await file.exists()) {
      throw FileNotFoundException('Audio file not found: $wavPath');
    }

    _currentlyPlayingPath = wavPath;
    await _ttsService.speakRecordedAudio(wavPath);
  }

  /// Speaks text via TTS if user wants to hear practice sentences or vocabulary chunks.
  Future<void> speakText(String text) async {
    await _ttsService.speakEnglish(text);
  }

  /// Pauses current playback.
  Future<void> pause() async {
    await stop();
  }

  /// Resumes current playback.
  Future<void> resume() async {
    if (_currentlyPlayingPath != null) {
      await playWav(_currentlyPlayingPath!);
    }
  }

  /// Stops current playback.
  Future<void> stop() async {
    _currentlyPlayingPath = null;
    await _ttsService.stop();
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
