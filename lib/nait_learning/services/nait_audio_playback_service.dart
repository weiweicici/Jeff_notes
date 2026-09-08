import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../services/tts_service.dart';
import '../../services/diagnostic_log_service.dart';

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
    final documentsDir = await getApplicationDocumentsDirectory();
    final resolvedPath = await resolvePersistedWavPath(wavPath, documentsDir);
    final file = File(resolvedPath);
    await DiagnosticLogService.instance.record(
      'nait_audio',
      await file.exists() ? 'file_resolved' : 'file_missing',
      fields: {
        'rebased': resolvedPath != wavPath,
        if (await file.exists()) 'bytes': await file.length(),
      },
    );
    if (!await file.exists()) {
      throw FileNotFoundException('Audio file not found: $wavPath');
    }

    _currentlyPlayingPath = resolvedPath;
    try {
      await _ttsService.speakRecordedAudio(resolvedPath);
      await DiagnosticLogService.instance.record('nait_audio', 'play_completed');
    } catch (error) {
      await DiagnosticLogService.instance.record(
        'nait_audio',
        'play_failed',
        fields: {'errorType': error.runtimeType},
      );
      rethrow;
    }
  }

  @visibleForTesting
  static Future<String> resolvePersistedWavPath(
    String storedPath,
    Directory currentDocumentsDir,
  ) async {
    if (await File(storedPath).exists()) return storedPath;
    const marker = '/Documents/';
    final markerIndex = storedPath.indexOf(marker);
    if (markerIndex < 0) return storedPath;
    final relativePath = storedPath.substring(markerIndex + marker.length);
    final candidate = File(p.join(currentDocumentsDir.path, relativePath));
    return await candidate.exists() ? candidate.path : storedPath;
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
