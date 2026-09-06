import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log_service.dart';

/// Queues text and sentence metadata for the paired Apple Watch remote.
///
/// The Watch never receives API credentials and never performs AI or TTS
/// requests. Audio stays on the iPhone; the Watch displays the synced text and
/// sends playback commands back to the iPhone.
class WatchSyncService {
  WatchSyncService._();

  static final WatchSyncService instance = WatchSyncService._();
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/watch_sync');
  Future<void> Function(String command)? _commandHandler;
  Future<void> Function(String command)? _recordingCommandHandler;
  final Set<String> _handledRecordingCommandIds = <String>{};
  final List<String> _recordingCommandOrder = <String>[];
  // MethodChannel calls can arrive concurrently even though Watch messages
  // are ordered.  Keep transport acknowledgement independent from the
  // actual recorder operation, but serialize operations on the Dart side.
  Future<void> _recordingCommandTail = Future<void>.value();
  bool _initialized = false;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  String _stableDocumentId(String title, {String? fallback}) {
    final normalized = title.trim().isNotEmpty
        ? title.trim()
        : (fallback ?? 'document');
    return 'document_${md5.convert(utf8.encode(normalized))}';
  }

  void setCommandHandler(Future<void> Function(String command) handler) {
    _commandHandler = handler;
    initialize();
  }

  void setRecordingCommandHandler(
    Future<void> Function(String command) handler,
  ) {
    _recordingCommandHandler = handler;
    initialize();
  }

  Future<bool> _handleMethodCall(MethodCall call) async {
    if (call.method != 'watchCommand') return false;

    final arguments = call.arguments;
    final payload = arguments is Map
        ? Map<String, dynamic>.from(arguments)
        : <String, dynamic>{'command': arguments?.toString() ?? ''};
    final command = payload['command']?.toString() ?? '';
    if (command.isEmpty) return false;

    if (const {
      'armListeningRecording',
      'disarmListeningRecording',
      'startListeningRecording',
      'stopListeningRecording',
    }.contains(command)) {
      final handler = _recordingCommandHandler;
      if (handler == null) return false;
      final commandId = payload['commandId']?.toString().trim() ?? '';
      if (commandId.isNotEmpty &&
          _handledRecordingCommandIds.contains(commandId)) {
        return true;
      }
      if (commandId.isNotEmpty) {
        _handledRecordingCommandIds.add(commandId);
        _recordingCommandOrder.add(commandId);
        if (_recordingCommandOrder.length > 100) {
          _handledRecordingCommandIds.remove(
            _recordingCommandOrder.removeAt(0),
          );
        }
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'watch',
          'recording_command_received',
          fields: {'command': command, 'commandId': commandId},
        ),
      );
      // A Watch transport ACK only means the command was accepted.  Do not
      // hold the MethodChannel reply open while an audio start/stop runs;
      // queue the real operation and preserve receive order instead.  A
      // failed command is removed from the idempotency set so Watch can retry.
      final operation = _recordingCommandTail.then((_) async {
        try {
          await handler(command);
          unawaited(
            DiagnosticLogService.instance.record(
              'watch',
              'recording_command_completed',
              fields: {'command': command, 'commandId': commandId},
            ),
          );
        } catch (error) {
          if (commandId.isNotEmpty) {
            _handledRecordingCommandIds.remove(commandId);
            _recordingCommandOrder.remove(commandId);
          }
          unawaited(
            DiagnosticLogService.instance.record(
              'watch',
              'recording_command_failed',
              fields: {
                'command': command,
                'commandId': commandId,
                'errorType': error.runtimeType,
              },
            ),
          );
        }
      });
      // Keep the tail alive after a failed command, allowing later commands
      // to execute while the failed command remains retryable.
      _recordingCommandTail = operation.catchError((Object _) {});
      return true;
    }

    final handler = _commandHandler;
    if (handler == null) return false;
    await handler(command);
    return true;
  }

  Future<bool> updateRecordingState(Map<String, Object?> state) async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('updateRecordingState', state) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('[WatchSync] Recording state update failed: $error');
      return false;
    }
  }

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

    final safeId = _stableDocumentId(title, fallback: documentId);
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

  Future<bool> queueMarkdownDocument({
    required String title,
    required String markdown,
  }) async {
    if (!Platform.isIOS || markdown.trim().isEmpty) return false;

    final safeId = _stableDocumentId(title);
    final directory = await getApplicationDocumentsDirectory();
    final packageDirectory = Directory('${directory.path}/tts_cache');
    if (!await packageDirectory.exists()) {
      await packageDirectory.create(recursive: true);
    }
    final markdownFile = File('${packageDirectory.path}/watch_$safeId.md');
    final manifestFile = File('${packageDirectory.path}/watch_$safeId.json');
    await markdownFile.writeAsString(markdown, flush: true);
    await manifestFile.writeAsString(
      jsonEncode({
        'schema_version': 1,
        'document_id': safeId,
        'title': title,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'audio_file': 'audio.mp3',
        'markdown_file': 'document.md',
        'loop_enabled': true,
        'pause_ms': 0,
        'sentences': <Object>[],
      }),
      flush: true,
    );

    try {
      return await _channel.invokeMethod<bool>('queueTtsPackage', {
            'documentId': safeId,
            'title': title,
            'markdownPath': markdownFile.path,
            'manifestPath': manifestFile.path,
          }) ??
          false;
    } catch (error) {
      debugPrint('[WatchSync] Markdown queue failed: $error');
      return false;
    }
  }
}
