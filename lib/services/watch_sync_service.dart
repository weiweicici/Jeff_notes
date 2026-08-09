import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostic_log_service.dart';

class WatchGrammarWritingRequest {
  const WatchGrammarWritingRequest({
    required this.topic,
    required this.requestId,
    required this.selectionMode,
    required this.selectedPartIds,
    required this.selectedUnitIds,
    this.contentType,
    this.requireAllSelectedGrammar = false,
  });

  final String topic;
  final String requestId;
  final String selectionMode;
  final Set<String> selectedPartIds;
  final Set<String> selectedUnitIds;
  final String? contentType;
  final bool requireAllSelectedGrammar;
}

/// Queues text and sentence metadata for the paired Apple Watch remote.
///
/// The Watch never receives API credentials and never performs AI or TTS
/// requests. Audio stays on the iPhone; the Watch displays the synced text and
/// sends playback commands back to the iPhone.
class WatchSyncService {
  WatchSyncService._();

  static final WatchSyncService instance = WatchSyncService._();
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/watch_sync');
  final StreamController<WatchGrammarWritingRequest> _grammarWritingRequests =
      StreamController<WatchGrammarWritingRequest>.broadcast();
  Future<void> Function(String command)? _commandHandler;
  Future<void> Function(String command)? _recordingCommandHandler;
  Future<void> Function()? _grammarConfigRequestHandler;
  final Set<String> _handledGrammarRequestIds = <String>{};
  final List<String> _grammarRequestOrder = <String>[];
  final Set<String> _handledRecordingCommandIds = <String>{};
  final List<String> _recordingCommandOrder = <String>[];
  bool _initialized = false;

  Stream<WatchGrammarWritingRequest> get grammarWritingRequests =>
      _grammarWritingRequests.stream;

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

  void setGrammarConfigRequestHandler(Future<void> Function() handler) {
    _grammarConfigRequestHandler = handler;
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

    if (command == 'generateGrammarWriting') {
      final topic = payload['topic']?.toString().trim() ?? '';
      final requestId = payload['requestId']?.toString().trim() ?? '';
      if (requestId.isNotEmpty &&
          _handledGrammarRequestIds.contains(requestId)) {
        return true;
      }
      if (requestId.isNotEmpty) {
        _handledGrammarRequestIds.add(requestId);
        _grammarRequestOrder.add(requestId);
        if (_grammarRequestOrder.length > 100) {
          _handledGrammarRequestIds.remove(_grammarRequestOrder.removeAt(0));
        }
      }
      Set<String> stringSet(Object? value) => value is List
          ? value.map((item) => item.toString()).toSet()
          : const <String>{};
      final selectionMode = payload['selectionMode']?.toString() ?? 'phone';
      _grammarWritingRequests.add(
        WatchGrammarWritingRequest(
          topic: topic,
          requestId: requestId,
          selectionMode:
              const {'phone', 'automatic', 'custom'}.contains(selectionMode)
              ? selectionMode
              : 'phone',
          selectedPartIds: stringSet(payload['selectedPartIds']),
          selectedUnitIds: stringSet(payload['selectedUnitIds']),
          contentType:
              payload['contentType']?.toString().trim().isNotEmpty == true
              ? payload['contentType'].toString().trim()
              : null,
          requireAllSelectedGrammar:
              payload['requireAllSelectedGrammar'] == true,
        ),
      );
      return true;
    }

    if (command == 'requestGrammarWritingConfig') {
      final handler = _grammarConfigRequestHandler;
      if (handler == null) return false;
      await handler();
      return true;
    }

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
      try {
        await handler(command);
        unawaited(
          DiagnosticLogService.instance.record(
            'watch',
            'recording_command_completed',
            fields: {'command': command, 'commandId': commandId},
          ),
        );
        return true;
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
        rethrow;
      }
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

  Future<bool> updateGrammarWritingConfig(Map<String, Object?> config) async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'updateGrammarWritingConfig',
            config,
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('[WatchSync] Grammar config update failed: $error');
      return false;
    }
  }

  Future<bool> updateGrammarWritingState({
    required String requestId,
    required String state,
    required String message,
  }) async {
    if (!Platform.isIOS || requestId.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('updateGrammarWritingState', {
            'request_id': requestId,
            'state': state,
            'message': message,
            'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } catch (error) {
      debugPrint('[WatchSync] Grammar state update failed: $error');
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
