import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Queues fully generated, offline playback packages for the paired Apple Watch.
///
/// The watch never receives API credentials and never performs AI or TTS
/// requests. It receives only a Markdown copy, one complete MP3, and a JSON
/// manifest containing sentence timings and local playback defaults.
class WatchSyncService {
  WatchSyncService._();

  static final WatchSyncService instance = WatchSyncService._();
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/watch_sync');

  Future<bool> queueDictationPackage({
    required String documentId,
    required String title,
    required String markdown,
    required File audioFile,
    required File boundaryFile,
    required List<Map<String, Object>> boundaries,
    required List<int> repeatCounts,
    required bool loopEnabled,
    required Duration pauseBetweenSentences,
  }) async {
    if (!Platform.isIOS || boundaries.isEmpty || !await audioFile.exists()) {
      return false;
    }

    final safeId = documentId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final packageDirectory = audioFile.parent;
    final markdownFile = File('${packageDirectory.path}/watch_$safeId.md');
    final manifestFile = File('${packageDirectory.path}/watch_$safeId.json');
    final normalizedRepeats = List<int>.generate(
      boundaries.length,
      (index) =>
          index < repeatCounts.length ? repeatCounts[index].clamp(1, 3) : 1,
    );

    final manifest = <String, Object>{
      'schema_version': 1,
      'document_id': safeId,
      'title': title,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'audio_file': 'audio.mp3',
      'markdown_file': 'document.md',
      'loop_enabled': loopEnabled,
      'pause_ms': pauseBetweenSentences.inMilliseconds,
      'sentences': List<Map<String, Object>>.generate(boundaries.length, (
        index,
      ) {
        final boundary = boundaries[index];
        return {...boundary, 'repeat_count': normalizedRepeats[index]};
      }),
    };

    await markdownFile.writeAsString(markdown, flush: true);
    await manifestFile.writeAsString(jsonEncode(manifest), flush: true);

    try {
      final queued = await _channel.invokeMethod<bool>('queueTtsPackage', {
        'documentId': safeId,
        'title': title,
        'audioPath': audioFile.path,
        'boundaryPath': boundaryFile.path,
        'markdownPath': markdownFile.path,
        'manifestPath': manifestFile.path,
      });
      return queued ?? false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('[WatchSync] Package queue failed: $error');
      return false;
    }
  }
}
