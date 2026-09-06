import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'services/supabase_config.dart';
import 'services/cloud_identity_guard.dart';
import 'services/upload_cache.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_session/audio_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'openai_service.dart';
import 'ai_orchestrator_service.dart';
import 'api_scheduler.dart';
import 'models.dart'; // 包含 AppMode 枚举
import 'prompt_provider.dart'; // 单元词汇高亮列表
export 'models/insight_note.dart';
import 'models/recording_session_context.dart';
import 'services/tts_service.dart';
import 'services/credential_store.dart';
import 'services/session_background_processor.dart';
import 'services/shadow_draft_service.dart';
import 'services/diagnostic_log_service.dart';
import 'services/api_rate_limit_service.dart';
import 'services/recovery_pipeline_runner.dart';
import 'services/recovery_retry_scheduler.dart';
import 'services/recovery_audio_ownership.dart';
import 'adapters/audio_recorder_adapter.dart';

import 'models/session_ready_event.dart';

class StitchData {
  final Uint8List tail;
  final String path;
  final int tailSize;
  StitchData(this.tail, this.path, this.tailSize);
}

int _findDataChunkOffset(Uint8List bytes) {
  if (bytes.length < 12) return 44;
  if (bytes[0] != 0x52 ||
      bytes[1] != 0x49 ||
      bytes[2] != 0x46 ||
      bytes[3] != 0x46)
    return 44; // "RIFF"
  if (bytes[8] != 0x57 ||
      bytes[9] != 0x41 ||
      bytes[10] != 0x56 ||
      bytes[11] != 0x45)
    return 44; // "WAVE"

  int offset = 12;
  while (offset + 8 <= bytes.length) {
    final c0 = bytes[offset];
    final c1 = bytes[offset + 1];
    final c2 = bytes[offset + 2];
    final c3 = bytes[offset + 3];

    // Check if it is "data" chunk
    if (c0 == 0x64 && c1 == 0x61 && c2 == 0x74 && c3 == 0x61) {
      return offset + 8;
    }

    final chunkSize =
        bytes[offset + 4] |
        (bytes[offset + 5] << 8) |
        (bytes[offset + 6] << 16) |
        (bytes[offset + 7] << 24);
    offset += 8 + chunkSize;
  }
  return 44;
}

Future<Map<String, dynamic>> _backgroundStitchTask(StitchData data) async {
  try {
    final currentFile = File(data.path);
    if (!currentFile.existsSync())
      return {'path': data.path, 'newTail': data.tail};
    final currentBytes = await currentFile.readAsBytes();

    final dataOffset = _findDataChunkOffset(currentBytes);

    if (currentBytes.length < dataOffset)
      return {'path': data.path, 'newTail': data.tail};
    final currentPcm = currentBytes.sublist(dataOffset);
    final List<int> combinedPcm = [...data.tail, ...currentPcm];
    final header = _generateWavHeaderStatic(combinedPcm.length);
    final stitchedBytes = Uint8List.fromList([...header, ...combinedPcm]);
    final stitchedPath = "${data.path}_stitched.wav";
    await File(stitchedPath).writeAsBytes(stitchedBytes);
    Uint8List nextTail = Uint8List(0);
    if (currentBytes.length > data.tailSize + dataOffset) {
      nextTail = currentBytes.sublist(currentBytes.length - data.tailSize);
    }
    return {'path': stitchedPath, 'newTail': nextTail};
  } catch (e) {
    return {'path': data.path, 'newTail': data.tail};
  }
}

/// Serializes ownership changes for the single native recorder used by
/// foreground recording and discarded background keepalive audio.
///
/// A completed session may call back after a newer session has started. The
/// session id on the keepalive lease ensures that callback can release only
/// its own capture, never the newer foreground recording or keepalive.
@visibleForTesting
class ProcessingAudioLeaseCoordinator {
  ProcessingAudioLeaseCoordinator(this._recorder);

  final AudioRecorderAdapter _recorder;
  Future<void> _operationTail = Future<void>.value();
  bool _foregroundCaptureClaimed = false;
  String? _keepaliveSessionId;
  String? _keepalivePath;
  final Set<String> _releasedSessionIds = <String>{};

  @visibleForTesting
  String? get keepaliveSessionId => _keepaliveSessionId;
  bool get hasKeepalive => _keepaliveSessionId != null;
  bool get hasForegroundCapture => _foregroundCaptureClaimed;

  void beginForegroundCapture() {
    _foregroundCaptureClaimed = true;
  }

  void abandonForegroundCapture() {
    _foregroundCaptureClaimed = false;
  }

  /// Explicit handoff used only after the foreground recorder has stopped.
  /// Keeping this separate makes it impossible for a stale background
  /// recovery completion to steal a newer foreground claim.
  @visibleForTesting
  void releaseForegroundForProcessingHandoff() {
    _foregroundCaptureClaimed = false;
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _operationTail = _operationTail.catchError((_) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _deleteKeepaliveFiles(Iterable<String?> paths) async {
    for (final path in paths.whereType<String>().toSet()) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  Future<void> _stopKeepaliveLocked() async {
    if (_keepaliveSessionId == null) return;
    String? stoppedPath;
    try {
      stoppedPath = await _recorder.stop();
    } catch (error) {
      debugPrint('[Recording Keepalive] Could not stop cleanly: $error');
    }
    final keepalivePath = _keepalivePath;
    _keepaliveSessionId = null;
    _keepalivePath = null;
    await _deleteKeepaliveFiles(<String?>[stoppedPath, keepalivePath]);
  }

  /// Claims the microphone synchronously, then removes any older keepalive
  /// before the caller starts the new foreground recording.
  Future<void> takeOverForForegroundCapture() => _serialize(() async {
    await _stopKeepaliveLocked();
  });

  /// Atomically hands the stopped foreground capture to this session's
  /// keepalive. Only one keepalive can own the native recorder at a time.
  Future<bool> startKeepalive({
    required String sessionId,
    required String path,
    required RecordConfig config,
  }) => _serialize(() async {
    if (_foregroundCaptureClaimed) {
      debugPrint(
        '[Recording Keepalive] Skipped stale keepalive for $sessionId while foreground capture is active',
      );
      return false;
    }
    await _stopKeepaliveLocked();
    await _recorder.start(config, path: path);
    _keepaliveSessionId = sessionId;
    _keepalivePath = path;
    // Retrying an interrupted session creates a new lease even though its
    // persistent session ID is unchanged. Its previous release must not
    // prevent this lease from being stopped.
    _releasedSessionIds.remove(sessionId);
    return true;
  });

  /// Releases only [sessionId]'s keepalive. Duplicate or out-of-order
  /// completion callbacks are harmless, and playback/session reset occurs
  /// only when no newer foreground capture or keepalive owns the recorder.
  Future<void> releaseProcessingSession(
    String sessionId, {
    required Future<void> Function() onAudioIdle,
  }) => _serialize(() async {
    if (!_releasedSessionIds.add(sessionId)) return;
    if (_releasedSessionIds.length > 128) {
      _releasedSessionIds.remove(_releasedSessionIds.first);
    }
    if (_keepaliveSessionId == sessionId) {
      await _stopKeepaliveLocked();
    }
    if (!_foregroundCaptureClaimed && _keepaliveSessionId == null) {
      await onAudioIdle();
    }
  });
}

Uint8List _generateWavHeaderStatic(int pcmLength) {
  final header = ByteData(44);

  // RIFF identifier
  header.setUint8(0, 0x52);
  header.setUint8(1, 0x49);
  header.setUint8(2, 0x46);
  header.setUint8(3, 0x46); // "RIFF"
  header.setUint32(4, 36 + pcmLength, Endian.little); // File size - 8

  // WAVE identifier
  header.setUint8(8, 0x57);
  header.setUint8(9, 0x41);
  header.setUint8(10, 0x56);
  header.setUint8(11, 0x45); // "WAVE"

  // fmt chunk
  header.setUint8(12, 0x66);
  header.setUint8(13, 0x6D);
  header.setUint8(14, 0x74);
  header.setUint8(15, 0x20); // "fmt "
  header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
  header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
  header.setUint16(22, 1, Endian.little); // NumChannels (1 for Mono)
  header.setUint32(24, 16000, Endian.little); // SampleRate (16kHz)
  header.setUint32(28, 16000 * 2, Endian.little); // ByteRate (SampleRate * 2)
  header.setUint16(32, 2, Endian.little); // BlockAlign (Channels * 2)
  header.setUint16(34, 16, Endian.little); // BitsPerSample (16-bit)

  // data chunk
  header.setUint8(36, 0x64);
  header.setUint8(37, 0x61);
  header.setUint8(38, 0x74);
  header.setUint8(39, 0x61); // "data"
  header.setUint32(40, pcmLength, Endian.little); // Subchunk2Size

  return header.buffer.asUint8List();
}

class RecordingProvider extends ChangeNotifier {
  final AudioRecorderAdapter _audioRecorder;
  OpenAIService? _aiService;
  OpenAIService? _fastAiService;
  OpenAIService? _groqService;
  OpenAIService? _fallbackTranslationService;
  String? _configuredGroqKey;
  String _groqTranslationKey = '';
  AIOrchestratorService? _orchestrator;
  final StreamController<SessionReadyEvent> _sessionReadyController =
      StreamController<SessionReadyEvent>.broadcast();

  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;

  AIProvider _selectedProvider = AIProvider.groq;
  int _sliceDuration = 5;
  bool _isDarkMode = false;
  bool _enableFinalRecap = false;
  bool _enableLectureDiscovery = false;
  AppMode _currentMode = AppMode.exam;
  PathwaysUnit _currentUnit = PathwaysUnit.none;
  int _autoScrollPauseDuration = 60;
  bool _autoScrollEnabled = false;
  int _autoScrollSecondsPerPage = 30;

  final Map<AIProvider, String> _apiKeys = {
    AIProvider.groq: "",
    AIProvider.gemini: "",
  };

  Timer? _sliceTimer;
  late final RecoveryRetryScheduler _recoveryRetryScheduler;
  bool _disposed = false;
  bool _isRotatingSlice = false;
  bool _isRecording = false;
  bool _isPaused = false; // 暂停录音标志（仅在 _isRecording=true 时有意义）
  bool _isPending = false;
  bool _isRecordingStandby = false;
  String? _standbyAudioPath;
  bool _isRecoveryRunning = false;
  late final ProcessingAudioLeaseCoordinator _processingAudioLease;
  DateTime? _recordingStartedAt;
  static const int kTailSize = 25600;
  static const RecordConfig _recordConfig = RecordConfig(
    encoder: AudioEncoder.wav,
    sampleRate: 16000,
    numChannels: 1,
  );

  final List<InsightNote> _allNotes = [];
  String? _statusMessage;
  bool _isProcessingRecording = false;
  int _processingStep = 0;
  String? _processingSessionId;
  // Every stopped/recovered session remains in this set until its own
  // background processor finishes.  The UI still exposes only the newest
  // session through _processingSessionId.
  final Set<String> _processingSessionIds = <String>{};
  String? _processingErrorMessage;
  String? _processingDeferredMessage;

  String? _finalReviewContent;
  String? _shorthandReviewContent;
  bool _isGeneratingFinalReview = false;
  String? _lastExportedPath;
  String? _lastReadyNotePath;
  String? _lastReadySessionId;
  DateTime? _lastReadyRecordedAt;
  final Map<String, double> _readingOffsets = {};
  // 40秒分段 AI 摘要
  final List<String> _segmentSummaries = [];

  /// Rolling notes update after at least about one minute of valid speech.
  /// This adapts to the user-selectable 5-10 second STT slice duration.
  int get _slicesPerRollingUpdate =>
      ((60 + _sliceDuration - 1) ~/ _sliceDuration).clamp(4, 15);
  String? _identifiedLectureContext;
  bool _hasRecoveredCache = false;
  String _openRouterKey = '';
  final List<String> _sessionAudioPaths = []; // 保存当次 session 所有录音切片路径

  // [Phase 3] 当前活跃的 RecordingSessionContext 实例
  RecordingSessionContext? _activeContext;
  RecordingSessionContext? get activeContext => _activeContext;

  List<InsightNote> get notes =>
      (_activeContext?.notes ?? _allNotes).reversed.toList();
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  bool get isPending => _isPending;
  bool get isRecordingStandby => _isRecordingStandby;
  DateTime? get recordingStartedAt => _recordingStartedAt;
  AIProvider get selectedProvider => _selectedProvider;
  int get sliceDuration => _sliceDuration;
  bool get isDarkMode => _isDarkMode;
  bool get enableFinalRecap => _enableFinalRecap;
  bool get enableLectureDiscovery => _enableLectureDiscovery;
  AppMode get currentMode => _currentMode;
  PathwaysUnit get currentUnit => _currentUnit;
  int get autoScrollPauseDuration => _autoScrollPauseDuration;
  bool get autoScrollEnabled => _autoScrollEnabled;
  int get autoScrollSecondsPerPage => _autoScrollSecondsPerPage;
  String? get statusMessage => _statusMessage;
  bool get isProcessingRecording => _isProcessingRecording;
  int get processingStep => _processingStep;
  String? get processingErrorMessage => _processingErrorMessage;
  String? get processingDeferredMessage => _processingDeferredMessage;
  static const int processingStepCount = 4;
  double get processingProgress {
    switch (_processingStep) {
      case 1:
        return 0.2;
      case 2:
        return 0.45;
      case 3:
        return 0.72;
      case 4:
        return 0.92;
      default:
        return 0;
    }
  }

  String? get finalReviewContent => _finalReviewContent;
  String? get shorthandReviewContent => _shorthandReviewContent;
  bool get isGeneratingFinalReview => _isGeneratingFinalReview;
  String? get lastExportedPath => _lastExportedPath;
  String? get lastReadyNotePath => _lastReadyNotePath;
  String? get lastReadySessionId => _lastReadySessionId;
  String? get identifiedLectureContext => _identifiedLectureContext;
  bool get hasRecoveredCache => _hasRecoveredCache;

  String get latestLiveEnglish {
    final source = _activeContext?.notes ?? _allNotes;
    for (final note in source.reversed) {
      final value = note.transcript.trim();
      if (_isValidTranscript(value) && !value.startsWith('[')) return value;
    }
    return '';
  }

  String get latestLiveChinese {
    final source = _activeContext?.notes ?? _allNotes;
    for (final note in source.reversed) {
      final value = note.translatedContent?.trim() ?? '';
      if (value.isNotEmpty && !value.startsWith('[')) return value;
    }
    return '';
  }

  // 添加缺失的getter方法
  Stream<SessionReadyEvent> get sessionReadyStream =>
      _sessionReadyController.stream;
  AppMode get appMode => currentMode;
  AppMode get currentSessionMode => currentMode;

  String get groqKey => _apiKeys[AIProvider.groq] ?? '';
  String get groqTranslationKey => _groqTranslationKey;
  String get geminiKey => _apiKeys[AIProvider.gemini] ?? '';
  String get openRouterKey => _openRouterKey;

  double readingOffsetFor(String path) => _readingOffsets[path] ?? 0;

  Future<void> updateReadingPreferences({
    bool? autoScrollEnabled,
    int? secondsPerPage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (autoScrollEnabled != null) {
      _autoScrollEnabled = autoScrollEnabled;
      await prefs.setBool('reader_auto_scroll_enabled', autoScrollEnabled);
    }
    if (secondsPerPage != null) {
      final clamped = secondsPerPage.clamp(10, 120);
      _autoScrollSecondsPerPage = clamped;
      await prefs.setInt('reader_seconds_per_page', clamped);
    }
    notifyListeners();
  }

  Future<void> saveReadingOffset(String path, double offset) async {
    if (path.isEmpty || !offset.isFinite) return;
    _readingOffsets[path] = offset < 0 ? 0 : offset;
    if (_readingOffsets.length > 30) {
      _readingOffsets.remove(_readingOffsets.keys.first);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('note_reading_offsets', jsonEncode(_readingOffsets));
  }

  Future<bool> promoteReadyNote(
    SessionReadyEvent event,
    String notePath,
  ) async {
    if (notePath.isEmpty || !File(notePath).existsSync()) return false;

    if (_lastReadySessionId != null) {
      if (event.sessionId == _lastReadySessionId) return false;
      final incomingTime = event.recordedAt;
      final currentTime = _lastReadyRecordedAt;
      final isNewer = incomingTime != null && currentTime != null
          ? incomingTime.isAfter(currentTime)
          : event.sessionId.compareTo(_lastReadySessionId!) > 0;
      if (!isNewer) return false;
    }

    _lastReadyNotePath = notePath;
    _lastReadySessionId = event.sessionId;
    _lastReadyRecordedAt = event.recordedAt;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_ready_note_path', notePath);
    await prefs.setString('last_ready_session_id', event.sessionId);
    if (event.recordedAt != null) {
      await prefs.setString(
        'last_ready_recorded_at',
        event.recordedAt!.toIso8601String(),
      );
    } else {
      await prefs.remove('last_ready_recorded_at');
    }
    notifyListeners();
    return true;
  }

  Future<void> forgetReadyNote(String path) async {
    if (_lastReadyNotePath != path) return;
    _lastReadyNotePath = null;
    _lastReadySessionId = null;
    _lastReadyRecordedAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_ready_note_path');
    await prefs.remove('last_ready_session_id');
    await prefs.remove('last_ready_recorded_at');
    notifyListeners();
  }

  RecordingProvider({AudioRecorderAdapter? audioRecorder})
    : _audioRecorder = audioRecorder ?? RecordAudioRecorderAdapter() {
    _processingAudioLease = ProcessingAudioLeaseCoordinator(_audioRecorder);
    _recoveryRetryScheduler = RecoveryRetryScheduler(
      clock: () => DateTime.now().toUtc(),
      timerFactory: Timer.new,
      isBusy: () =>
          _isRecording ||
          _isPending ||
          _isRecordingStandby ||
          _isProcessingRecording ||
          _isRecoveryRunning ||
          _processingAudioLease.hasForegroundCapture,
      recover: resumeInterruptedSessions,
      onError: (error, stackTrace) =>
          debugPrint('[Recording Recovery] Scheduled retry failed: $error'),
    );
    _init();
  }

  Future<void> _init() async {
    await _loadSettings();
    await _initializeAudioSession();
    await _checkRecoveryCache();
    if (Platform.isIOS) {
      unawaited(resumeInterruptedSessions());
    }
    notifyListeners();
  }

  Future<void> resumeInterruptedSessions() async {
    if (await _scheduleIfSttCooldownActive()) return;
    if (_disposed) return;
    if (_isRecoveryRunning ||
        _isProcessingRecording ||
        !_recordingServicesReady ||
        _isPending ||
        _isRecording ||
        _isRecordingStandby) {
      _scheduleRecoveryRetry(
        DateTime.now().toUtc().add(const Duration(seconds: 30)),
      );
      return;
    }
    _recoveryRetryScheduler.cancel();
    _isRecoveryRunning = true;
    try {
      await _resumeInterruptedSessionsOnce();
    } finally {
      _isRecoveryRunning = false;
    }
  }

  Future<void> _resumeInterruptedSessionsOnce() async {
    final directory = await getApplicationDocumentsDirectory();
    final draftFiles = directory
        .listSync()
        .whereType<File>()
        .where((file) => RegExp(r'/shadow_draft_.+\.json$').hasMatch(file.path))
        .toList();
    final allContexts = <RecordingSessionContext>[];
    for (final draft in draftFiles) {
      final context = await ShadowDraftService.instance.readDraft(draft.path);
      if (context != null) allContexts.add(context);
    }
    final contexts =
        allContexts.where((context) => !context.isCompleted).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final ownershipDrafts = allContexts
        .map(
          (context) => RecoveryDraftAudioOwnership(
            createdAt: context.createdAt,
            rawAudioPaths: context.rawAudioPaths,
            pendingAudioPaths: context.pendingAudioNotes.keys,
            stitchedAudioPaths: context.stitchedAudioPaths,
          ),
        )
        .toList();
    final exportedPaths = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.md'))
        .map((file) => file.path)
        .toList();
    var claimOrphans = true;
    try {
      for (final context in contexts) {
        if (_isRecording || _isPending || _isRecordingStandby) {
          _scheduleRecoveryRetry(
            DateTime.now().toUtc().add(const Duration(seconds: 30)),
          );
          break;
        }
        if (_processingSessionIds.contains(context.sessionId)) continue;
        var claimed = false;
        try {
          if (claimOrphans) {
            claimOrphans = false;
            final audioPaths = directory
                .listSync()
                .whereType<File>()
                .where((file) => file.uri.pathSegments.last.endsWith('.wav'))
                .map((file) => file.path)
                .toList();
            final orphanedPaths = RecoveryAudioOwnership.selectCandidates(
              audioPaths: audioPaths,
              sessionCreatedAt: context.createdAt,
              drafts: ownershipDrafts,
              exportedPaths: exportedPaths,
            );
            for (final path in orphanedPaths) {
              context.pendingAudioNotes.putIfAbsent(path, () => null);
            }
            if (orphanedPaths.isNotEmpty && !await context.saveShadowDraft()) {
              throw StateError('Could not persist recovered audio ownership');
            }
          }

          final recoveryPaths = context.pendingAudioNotes.keys.toList();
          final availableRecoveryPaths = <String>[];
          for (final path in recoveryPaths) {
            if (await File(path).exists()) availableRecoveryPaths.add(path);
          }
          if (recoveryPaths.isNotEmpty && availableRecoveryPaths.isEmpty) {
            unawaited(
              DiagnosticLogService.instance.record(
                'background',
                'recovery_audio_missing',
                sessionId: context.sessionId,
                fields: {'missingCount': recoveryPaths.length},
              ),
            );
            continue;
          }

          unawaited(
            DiagnosticLogService.instance.record(
              'background',
              'recovery_started',
              sessionId: context.sessionId,
              fields: {
                'total': recoveryPaths.length,
                'available': availableRecoveryPaths.length,
                'missing': recoveryPaths.length - availableRecoveryPaths.length,
              },
            ),
          );

          // The app may have changed state while drafts/files were read.
          // Never claim the recorder or publish recovery UI over a newer
          // foreground capture or an already running processing session.
          if (_isRecording ||
              _isPending ||
              _isRecordingStandby ||
              _processingAudioLease.hasForegroundCapture ||
              _processingSessionIds.isNotEmpty) {
            _scheduleRecoveryRetry(
              DateTime.now().toUtc().add(const Duration(seconds: 30)),
            );
            break;
          }

          _configureSessionContext(context);
          _processingSessionIds.add(context.sessionId);
          claimed = true;
          _processingSessionId = context.sessionId;
          _isProcessingRecording = true;
          _processingStep = 1;
          _processingErrorMessage = null;
          _processingDeferredMessage = null;
          if (!_isRecording &&
              !_isRecordingStandby &&
              !_processingAudioLease.hasForegroundCapture) {
            _statusMessage =
                '处理录音切片 0/${availableRecoveryPaths.length} · 失败 0'
                ' · 缺失 ${recoveryPaths.length - availableRecoveryPaths.length}';
            notifyListeners();
          }
          if (await _audioRecorder.hasPermission()) {
            await TtsService().releaseForRecording();
            await _startProcessingKeepalive(context.sessionId);
          }

          final recoveryResult = await _runRecoveryPipelines(
            context,
            availableRecoveryPaths,
          );
          unawaited(
            DiagnosticLogService.instance.record(
              'background',
              'recovery_progress',
              sessionId: context.sessionId,
              fields: {
                'processed': recoveryResult.processed,
                'total': availableRecoveryPaths.length,
                'failed': recoveryResult.failed,
              },
            ),
          );
          if (recoveryResult.pausedAfterConsecutiveFailures) {
            unawaited(
              DiagnosticLogService.instance.record(
                'background',
                'recovery_paused',
                sessionId: context.sessionId,
                fields: {'reason': 'consecutive_processing_failures'},
              ),
            );
          }
          final rateLimit = recoveryResult.rateLimit;
          final pausedExternally = recoveryResult.pausedExternally;
          if (rateLimit != null) {
            await context.saveShadowDraft();
            _scheduleRecoveryRetry(rateLimit.retryAt);
            if (_processingSessionId == context.sessionId &&
                !_isRecording &&
                !_isRecordingStandby &&
                !_processingAudioLease.hasForegroundCapture) {
              _statusMessage = '识别服务限流，已保留录音；将在冷却结束后自动继续';
              _processingErrorMessage =
                  '识别服务暂时达到限制，将在 ${_formatRetryAt(rateLimit.retryAt)} 自动继续';
              notifyListeners();
            }
          }
          if (pausedExternally && rateLimit == null) {
            // The foreground recorder took priority while an old slice was
            // waiting for pacing. Keep it pending and retry after the new
            // session has finished; the normal finalizer below still flushes
            // any already completed transcript/translation work.
            await context.saveShadowDraft();
            _scheduleRecoveryRetry(
              DateTime.now().toUtc().add(const Duration(seconds: 30)),
            );
          }
          context.sealPipelines();
          if (!await context.saveShadowDraft()) {
            throw StateError('Could not persist recovery draft');
          }

          SessionReadyEvent? readyEvent;
          String? processingError;
          String? deferredMessage;
          await SessionBackgroundProcessor.instance.submit(
            HandoverPayload(
              context: context,
              enableFinalRecap:
                  _enableFinalRecap ||
                  context.mode == AppMode.exam ||
                  context.mode == AppMode.lecture,
              onDone: (event) => readyEvent = event,
              onDeferred: (message) {
                deferredMessage = message;
                _handleDeferredProcessing(context, message);
              },
              onStatus: (message) =>
                  _updateBackgroundProcessingStatus(context.sessionId, message),
              onError: (error) => processingError = error,
            ),
          );
          if (readyEvent == null &&
              processingError == null &&
              deferredMessage == null) {
            processingError = '恢复处理未完成，下次启动会继续';
          }
          if (readyEvent != null && deferredMessage != null) {
            processingError = null;
          } else if (readyEvent != null && rateLimit != null) {
            processingError =
                '识别服务暂时达到限制；已保存可用内容，并保留录音草稿，'
                '将在 ${_formatRetryAt(rateLimit.retryAt)} 自动继续。';
          } else if (readyEvent != null &&
              recoveryResult.pausedAfterConsecutiveFailures) {
            processingError =
                '连续处理失败，已暂停自动重试；已处理 '
                '${recoveryResult.processed}/${availableRecoveryPaths.length} 片，'
                '失败 ${recoveryResult.failed} 片。录音与草稿保留，'
                '下次回到 App 时会再次尝试。';
          }
          if (readyEvent != null) {
            _lastExportedPath = readyEvent!.exportPath;
            if (_processingSessionId == context.sessionId &&
                !_isRecording &&
                !_isRecordingStandby &&
                !_processingAudioLease.hasForegroundCapture) {
              _processingStep = RecordingProvider.processingStepCount;
              _processingDeferredMessage = !readyEvent!.isFinal
                  ? '可用内容已保存在本机，剩余处理将自动重试'
                  : null;
              _statusMessage = _processingDeferredMessage != null
                  ? _processingDeferredMessage
                  : pausedExternally && rateLimit == null
                  ? '新录音优先，旧录音已保存，稍后自动继续'
                  : processingError == null
                  ? _localSaveStatus
                  : '已保存可用内容，并保留恢复草稿';
              _processingErrorMessage = pausedExternally && rateLimit == null
                  ? null
                  : processingError;
              _sessionReadyController.add(readyEvent!);
              notifyListeners();
            } else {
              _sessionReadyController.add(readyEvent!);
            }
          } else if (_processingSessionId == context.sessionId &&
              !_isRecording &&
              !_isRecordingStandby &&
              !_processingAudioLease.hasForegroundCapture) {
            _statusMessage = '恢复处理未完成，录音与草稿仍然保留';
            _processingErrorMessage = processingError;
            notifyListeners();
          }
          if (rateLimit != null ||
              pausedExternally ||
              recoveryResult.pausedAfterConsecutiveFailures) {
            break;
          }
        } catch (error, stackTrace) {
          unawaited(
            DiagnosticLogService.instance.record(
              'background',
              'recovery_failed',
              sessionId: context.sessionId,
              fields: {'errorType': error.runtimeType.toString()},
            ),
          );
          debugPrint(
            '[Recording Recovery] Failed for ${context.sessionId}: $error\n$stackTrace',
          );
          try {
            if (!await context.saveShadowDraft()) {
              unawaited(
                DiagnosticLogService.instance.record(
                  'background',
                  'recovery_draft_save_failed',
                  sessionId: context.sessionId,
                ),
              );
            }
          } catch (saveError, saveStack) {
            debugPrint(
              '[Recording Recovery] Draft save failed: $saveError\n$saveStack',
            );
          }
          if (_processingSessionId == context.sessionId &&
              !_isRecording &&
              !_isRecordingStandby &&
              !_processingAudioLease.hasForegroundCapture) {
            _processingErrorMessage = '恢复处理异常，录音草稿已保留；下次启动会继续';
            notifyListeners();
          }
        } finally {
          if (claimed) {
            context.sealPipelines();
            try {
              await _releaseProcessingAudio(context.sessionId);
            } catch (releaseError, releaseStack) {
              debugPrint(
                '[Recording Recovery] Audio release failed: $releaseError\n$releaseStack',
              );
            }
            ApiScheduler().cancelSession(context.sessionId);
            _processingSessionIds.remove(context.sessionId);
            if (_processingSessionId == context.sessionId) {
              _processingSessionId = _processingSessionIds.isEmpty
                  ? null
                  : _processingSessionIds.last;
            }
            _isProcessingRecording = _processingSessionIds.isNotEmpty;
            notifyListeners();
            if (!context.isDisposed) context.dispose();
          }
        }
      }
    } finally {
      for (final context in allContexts) {
        if (!context.isDisposed) context.dispose();
      }
    }
  }

  Future<bool> _scheduleIfSttCooldownActive() async {
    if (_disposed) return true;
    final candidates = <({String provider, String model})>[];
    if ((_apiKeys[AIProvider.groq] ?? '').trim().isNotEmpty) {
      candidates.add((provider: 'groq', model: 'whisper-large-v3'));
    }
    if ((_apiKeys[AIProvider.gemini] ?? '').trim().isNotEmpty) {
      candidates.add((provider: 'gemini', model: 'gemini-2.5-flash'));
    }
    if (candidates.isEmpty) return false;
    // Recovery waits only when every configured STT candidate is blocked.
    final retryAt = await ApiRateLimitService.instance.earliestAvailable(
      candidates,
    );
    if (_disposed) return true;
    if (retryAt == null) return false;
    _scheduleRecoveryRetry(retryAt);
    return true;
  }

  void _scheduleRecoveryRetry(DateTime retryAt) {
    _recoveryRetryScheduler.schedule(retryAt);
  }

  String _formatRetryAt(DateTime retryAt) {
    final local = retryAt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Runs recovered slices with a small fixed worker pool. The runner awaits
  /// both workers before handing the session to final background processing.
  static const int _recoveryPipelineConcurrency = 2;

  Future<RecoveryPipelineResult> _runRecoveryPipelines(
    RecordingSessionContext context,
    List<String> paths,
  ) async {
    return const RecoveryPipelineRunner(
      concurrency: _recoveryPipelineConcurrency,
      maxConsecutiveFailures: 3,
    ).run(
      paths,
      process: (path) async {
        if (_disposed ||
            _isRecording ||
            _isPending ||
            _isRecordingStandby ||
            _processingAudioLease.hasForegroundCapture) {
          throw const RecoveryPausedException();
        }
        await ApiRateLimitService.instance.waitForRecoveryRequest(
          provider: 'groq',
          model: 'whisper-large-v3',
        );
        // A new foreground capture may have started during the pacing wait.
        // Leave this path pending instead of sending it or marking it failed.
        if (_disposed ||
            _isRecording ||
            _isPending ||
            _isRecordingStandby ||
            _processingAudioLease.hasForegroundCapture) {
          throw const RecoveryPausedException();
        }
        await _processAudio(path, context);
        return !context.pendingAudioNotes.containsKey(path);
      },
      onProgress: (processed, total, failed) {
        unawaited(
          DiagnosticLogService.instance.record(
            'background',
            'recovery_progress',
            sessionId: context.sessionId,
            fields: {'processed': processed, 'total': total, 'failed': failed},
          ),
        );
        if (context.sessionId != _processingSessionId ||
            _isRecording ||
            _isRecordingStandby ||
            _processingAudioLease.hasForegroundCapture) {
          return;
        }
        _statusMessage = '处理录音切片 $processed/$total · 失败 $failed';
        notifyListeners();
      },
      shouldPause: () =>
          _isRecording ||
          _isPending ||
          _isRecordingStandby ||
          _processingAudioLease.hasForegroundCapture,
    );
  }

  /// Returns clean Chinese + English full transcript for TTS playback.
  /// Only includes actual spoken content — no markdown headers, bullets or AI summaries.
  String get bilingualTtsText {
    final sourceNotes = _activeContext?.notes ?? _allNotes;
    final transcripts = sourceNotes.where((n) => !n.isSummary).toList();
    if (transcripts.isEmpty) return "";

    final chineseParts = <String>[];
    final englishParts = <String>[];

    for (final note in transcripts) {
      final en = note.transcript.trim();
      if (en.isNotEmpty && en != '...' && !en.startsWith('[')) {
        englishParts.add(en);
      }
      final zh = note.translatedContent?.trim();
      if (zh != null && zh.isNotEmpty && !zh.startsWith('[')) {
        chineseParts.add(zh);
      }
    }

    final buffer = StringBuffer();
    if (chineseParts.isNotEmpty) {
      buffer.write("中文全文：");
      buffer.write(chineseParts.join("。"));
    }
    if (englishParts.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.write("  英文全文：");
      buffer.write(englishParts.join(" "));
    }
    return buffer.toString();
  }

  /// Formats notes into Chinese paragraph followed by English paragraph for FreeTalk export.
  static String formatFreeTalkContent(List<InsightNote> notes) {
    final chinese = <String>[];
    final english = <String>[];
    for (final note in notes.where((note) => !note.isSummary)) {
      final en = note.transcript.trim();
      if (en.isNotEmpty && en != '...' && !en.startsWith('[')) {
        english.add(en);
      }
      final zh = note.translatedContent?.trim();
      if (zh != null && zh.isNotEmpty && !zh.startsWith('[')) {
        chinese.add(zh);
      }
    }

    final buffer = StringBuffer();
    for (final zh in chinese) {
      buffer.writeln(zh);
    }
    if (chinese.isNotEmpty && english.isNotEmpty) {
      buffer.writeln();
    }
    for (final en in english) {
      buffer.writeln(en);
    }
    return buffer.toString();
  }

  Future<void> updateSettings({
    String? groqKey,
    String? groqTranslationKey,
    String? openRouterKey,
    String? geminiKey,

    int? duration,
    bool? isDarkMode,
    bool? enableFinalRecap,
    bool? enableLectureDiscovery,
    AppMode? mode,
    PathwaysUnit? unit,
    int? autoScrollPauseDuration,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (duration != null) {
      final clamped = duration.clamp(5, 10);
      await prefs.setInt('slice_duration', clamped);
      _sliceDuration = clamped;
    }
    if (isDarkMode != null) {
      await prefs.setBool('is_dark_mode', isDarkMode);
      _isDarkMode = isDarkMode;
    }
    if (enableFinalRecap != null) {
      await prefs.setBool('enableFinalRecap', enableFinalRecap);
      _enableFinalRecap = enableFinalRecap;
    }
    if (enableLectureDiscovery != null) {
      await prefs.setBool('enableLectureDiscovery', enableLectureDiscovery);
      _enableLectureDiscovery = enableLectureDiscovery;
    }
    if (mode != null) {
      await prefs.setInt('app_mode', mode.index);
      _currentMode = mode;
    }
    if (unit != null) {
      await prefs.setInt('current_unit', unit.index);
      _currentUnit = unit;
    }
    if (autoScrollPauseDuration != null) {
      await prefs.setInt('autoScrollPauseDuration', autoScrollPauseDuration);
      _autoScrollPauseDuration = autoScrollPauseDuration;
    }

    if (groqKey != null) {
      final trimmedKey = groqKey.trim();
      await CredentialStore.instance.writeKey(
        CredentialStore.keyGroq,
        trimmedKey,
      );
      _apiKeys[AIProvider.groq] = trimmedKey;
      debugPrint("保存 Groq API Key 成功: ${CredentialStore.redact(trimmedKey)}");
    }
    if (groqTranslationKey != null) {
      final trimmedKey = groqTranslationKey.trim();
      await CredentialStore.instance.writeKey(
        CredentialStore.keyGroqTranslation,
        trimmedKey,
      );
      _groqTranslationKey = trimmedKey;
      debugPrint(
        "保存 Groq 中文翻译 API Key 成功: ${CredentialStore.redact(trimmedKey)}",
      );
    }
    if (geminiKey != null) {
      final trimmedKey = geminiKey.trim();
      await CredentialStore.instance.writeKey(
        CredentialStore.keyGemini,
        trimmedKey,
      );
      _apiKeys[AIProvider.gemini] = trimmedKey;
      debugPrint("保存 Gemini API Key 成功: ${CredentialStore.redact(trimmedKey)}");
    }
    if (openRouterKey != null) {
      final trimmedKey = openRouterKey.trim();
      await CredentialStore.instance.writeKey(
        CredentialStore.keyOpenRouter,
        trimmedKey,
      );
      _openRouterKey = trimmedKey;
      debugPrint(
        "保存 OpenRouter API Key 成功: ${CredentialStore.redact(trimmedKey)}",
      );
    }

    _updateService();
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _sliceDuration = (prefs.getInt('slice_duration') ?? 5).clamp(5, 10);
    _isDarkMode = prefs.getBool('is_dark_mode') ?? false;
    _enableFinalRecap = prefs.getBool('enableFinalRecap') ?? false;
    _enableLectureDiscovery = prefs.getBool('enableLectureDiscovery') ?? false;
    _autoScrollPauseDuration = prefs.getInt('autoScrollPauseDuration') ?? 60;
    _autoScrollEnabled = prefs.getBool('reader_auto_scroll_enabled') ?? false;
    _autoScrollSecondsPerPage = (prefs.getInt('reader_seconds_per_page') ?? 30)
        .clamp(10, 120);
    final savedReadyPath = prefs.getString('last_ready_note_path');
    if (savedReadyPath != null && File(savedReadyPath).existsSync()) {
      _lastReadyNotePath = savedReadyPath;
      _lastReadySessionId = prefs.getString('last_ready_session_id');
      _lastReadyRecordedAt = DateTime.tryParse(
        prefs.getString('last_ready_recorded_at') ?? '',
      );
    }
    final savedOffsets = prefs.getString('note_reading_offsets');
    if (savedOffsets != null) {
      try {
        final decoded = jsonDecode(savedOffsets);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final value = entry.value;
            if (value is num) _readingOffsets[entry.key] = value.toDouble();
          }
        }
      } catch (_) {
        await prefs.remove('note_reading_offsets');
      }
    }
    final modeIndex = prefs.getInt('app_mode') ?? AppMode.exam.index;
    _currentMode = AppMode.values[modeIndex];
    _currentUnit = PathwaysUnit.values[prefs.getInt('current_unit') ?? 0];
    final pIndex = prefs.getInt('selected_provider') ?? 0;
    _selectedProvider = AIProvider.values[pIndex];

    _openRouterKey =
        await CredentialStore.instance.readKey(CredentialStore.keyOpenRouter) ??
        '';
    _apiKeys[AIProvider.groq] =
        await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';
    _groqTranslationKey =
        await CredentialStore.instance.readKey(
          CredentialStore.keyGroqTranslation,
        ) ??
        '';
    _apiKeys[AIProvider.gemini] =
        await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';

    _updateService();
  }

  void _updateService() {
    final groqKey = _apiKeys[AIProvider.groq] ?? "";
    if (_configuredGroqKey == groqKey &&
        ((groqKey.isEmpty && _fastAiService == null) ||
            (groqKey.isNotEmpty && _fastAiService != null))) {
      return;
    }
    _fastAiService?.dispose();
    if (!identical(_groqService, _fastAiService)) {
      _groqService?.dispose();
    }
    _configuredGroqKey = groqKey;

    if (groqKey.isNotEmpty) {
      _fastAiService = OpenAIService(
        apiKey: groqKey,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "openai/gpt-oss-120b",
        whisperModel: "whisper-large-v3",
      );
      _groqService = OpenAIService(
        apiKey: groqKey,
        baseUrl: "https://api.groq.com/openai/v1",
        defaultModel: "openai/gpt-oss-120b",
        whisperModel: "whisper-large-v3",
      );
      _aiService = _groqService;
      _fallbackTranslationService = _groqService;
      debugPrint("Groq 服务配置完成");
    } else {
      _fastAiService = null;
      _groqService = null;
      _aiService = null;
      _fallbackTranslationService = null;
      debugPrint("警告：Groq API Key 未设置，AI 功能将不可用");
    }
  }

  Future<void> _initializeAudioSession() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        ),
      );
      // setActive may fail if another app holds the session; safe to ignore at init
      await session.setActive(true);
    } catch (e) {
      debugPrint(
        '[AudioSession] init setActive failed (will retry on record): $e',
      );
    }
  }

  /// 录音结束后重置会话：先 deactivate 释放麦克风独占，再 reactivate 准备下次录音。
  Future<void> _resetAudioSessionAfterRecording() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
      await Future.delayed(const Duration(milliseconds: 150));
      await session.configure(
        const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.defaultToSpeaker,
          avAudioSessionMode: AVAudioSessionMode.spokenAudio,
        ),
      );
      await session.setActive(true);
      debugPrint(
        '[AudioSession] Session reset after recording — ready for next session',
      );
    } catch (e) {
      debugPrint('[AudioSession] resetAfterRecording error: $e');
    }
  }

  bool get _recordingServicesReady {
    _updateService();
    if (_aiService != null && _fastAiService != null) return true;
    _statusMessage = 'Please configure your API Keys in Settings first';
    notifyListeners();
    return false;
  }

  void _configureSessionContext(RecordingSessionContext context) {
    final client = context.sessionHttpClient;
    final translationKey = groqTranslationKey.trim().isNotEmpty
        ? groqTranslationKey.trim()
        : groqKey;
    final stt = OpenAIService(
      apiKey: groqKey,
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'openai/gpt-oss-120b',
      whisperModel: 'whisper-large-v3',
      httpClient: client,
    );
    final trans = OpenAIService(
      apiKey: translationKey,
      baseUrl: 'https://api.groq.com/openai/v1',
      defaultModel: 'openai/gpt-oss-120b',
      whisperModel: 'whisper-large-v3',
      httpClient: client,
    );
    final routerKey = openRouterKey.trim();
    final fallbackTrans = routerKey.isEmpty
        ? null
        : OpenAIService(
            apiKey: routerKey,
            baseUrl: 'https://openrouter.ai/api/v1',
            defaultModel: 'google/gemini-2.5-flash-lite',
            httpClient: client,
          );
    context.sttService = stt;
    context.translationService = trans;
    context.fallbackTranslationService = fallbackTrans;
    context.onChanged = () {
      if (_activeContext == context) notifyListeners();
    };
    final orchestrator = AIOrchestratorService(
      sttService: stt,
      translationService: trans,
      translationFallbackService: fallbackTrans,
      // Cloud translation is intentionally separate from Groq Whisper STT.
      // Keep the local ML Kit translator out of this path so the configured
      // translation key is actually used for Lecture and FreeTalk.
      localTranslator: null,
      sessionId: context.sessionId,
      geminiApiKey: geminiKey,
      httpClient: client,
    );
    context.bindOrchestrator(orchestrator);
    _orchestrator = orchestrator;
  }

  Future<void> toggleRecordingStandby() async {
    if (_isPending || _isRecording) return;
    _isPending = true;
    notifyListeners();
    try {
      if (_isRecordingStandby) {
        await leaveRecordingStandby();
      } else {
        await enterRecordingStandby();
      }
    } finally {
      _isPending = false;
      notifyListeners();
    }
  }

  /// Keeps a real foreground-started microphone session alive so the Watch can
  /// reliably begin the lecture after the phone locks. Standby audio is never
  /// sent to STT and is deleted when the actual session starts or is disarmed.
  Future<bool> enterRecordingStandby() async {
    if (_isRecordingStandby) return true;
    if (_isRecording) return false;
    _processingAudioLease.beginForegroundCapture();
    var standbyStarted = false;
    try {
      if (!await _audioRecorder.hasPermission() || !_recordingServicesReady) {
        return false;
      }
      _processingAudioLease.releaseForegroundForProcessingHandoff();
      await _processingAudioLease.takeOverForForegroundCapture();
      await TtsService().releaseForRecording();
      await _initializeAudioSession();
      final path = await _getTempPath(prefix: 'standby');
      await _audioRecorder.start(_recordConfig, path: path);
      _standbyAudioPath = path;
      _isRecordingStandby = true;
      standbyStarted = true;
      _statusMessage = '录音待命已开启，可以锁屏并从手表开始';
      notifyListeners();
      return true;
    } catch (error) {
      _statusMessage = '录音待命失败：$error';
      TtsService().allowPlaybackAfterRecording();
      notifyListeners();
      return false;
    } finally {
      if (!standbyStarted) {
        _processingAudioLease.abandonForegroundCapture();
      }
    }
  }

  Future<void> leaveRecordingStandby() async {
    if (!_isRecordingStandby) return;
    final recordedPath = await _audioRecorder.stop();
    _isRecordingStandby = false;
    _statusMessage = null;
    final paths = <String?>[recordedPath, _standbyAudioPath];
    _standbyAudioPath = null;
    for (final path in paths.whereType<String>().toSet()) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    _processingAudioLease.abandonForegroundCapture();
    await _resetAudioSessionAfterRecording();
    TtsService().allowPlaybackAfterRecording();
    notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (_isPending) return;
    _isPending = true;
    notifyListeners();
    try {
      if (_isRecording) {
        await stopRecording();
      } else {
        await startRecording();
      }
    } finally {
      _isPending = false;
      notifyListeners();
    }
  }

  Future<void> startRecording() async {
    unawaited(
      DiagnosticLogService.instance.record('recording', 'start_requested'),
    );
    if (_isRecording) return;
    _processingAudioLease.beginForegroundCapture();
    var foregroundCaptureStarted = false;
    try {
      if (!await _audioRecorder.hasPermission()) return;
      if (!_recordingServicesReady) return;
      if (_isRecordingStandby) {
        final standbyPath = await _audioRecorder.stop();
        _isRecordingStandby = false;
        final paths = <String?>[standbyPath, _standbyAudioPath];
        _standbyAudioPath = null;
        for (final path in paths.whereType<String>().toSet()) {
          final file = File(path);
          if (await file.exists()) await file.delete();
        }
      }
      await _processingAudioLease.takeOverForForegroundCapture();
      await TtsService().releaseForRecording();

      // [Phase 3 Fix 2, 4, 10] 创建专属 RecordingSessionContext 和底层专有 http.Client
      final docsDir = await getApplicationDocumentsDirectory();
      final context = RecordingSessionContext.create(
        mode: _currentMode,
        unit: _currentUnit,
        baseDirectory: docsDir.path,
      );

      _configureSessionContext(context);
      _activeContext = context;
      await context.saveShadowDraft();
      unawaited(
        DiagnosticLogService.instance.record(
          'recording',
          'session_started',
          sessionId: context.sessionId,
          fields: {'mode': context.mode.name, 'sliceSeconds': _sliceDuration},
        ),
      );

      _isRecording = true;
      _isPaused = false;
      _recordingStartedAt = DateTime.now();
      _sessionAudioPaths.clear();
      _allNotes.clear();
      _segmentSummaries.clear();
      _finalReviewContent = null;
      _processingErrorMessage = null;
      _processingDeferredMessage = null;
      _statusMessage = null;
      notifyListeners();

      try {
        final path = await _getTempPath();
        await _audioRecorder.start(_recordConfig, path: path);
        foregroundCaptureStarted = true;
        _startSmartSliceTimer(context);
      } catch (_) {
        _isRecording = false;
        _recordingStartedAt = null;
        _activeContext = null;
        context.dispose();
        TtsService().allowPlaybackAfterRecording();
        notifyListeners();
        rethrow;
      }
    } finally {
      if (!foregroundCaptureStarted) {
        _processingAudioLease.abandonForegroundCapture();
      }
    }
  }

  Future<void> _queueAudioSlice(
    String path,
    RecordingSessionContext context,
  ) async {
    if (path.isEmpty || context.isDisposed) return;
    context.registerPendingAudio(path);
    await context.saveShadowDraft();
    context.runPipeline(() => _processAudio(path, context));
  }

  Future<void> _startProcessingKeepalive(String sessionId) async {
    try {
      final path = await _getTempPath(prefix: 'processing_keepalive');
      await _processingAudioLease.startKeepalive(
        sessionId: sessionId,
        path: path,
        config: _recordConfig,
      );
    } catch (error) {
      debugPrint('[Recording Keepalive] Could not start: $error');
    }
  }

  Future<void> _releaseProcessingAudio(String sessionId) async {
    await _processingAudioLease.releaseProcessingSession(
      sessionId,
      onAudioIdle: () async {
        if (_isRecording || _isRecordingStandby) return;
        await _resetAudioSessionAfterRecording();
        if (!_isRecording && !_isRecordingStandby) {
          TtsService().allowPlaybackAfterRecording();
        }
      },
    );
  }

  void _handleSessionReady(
    RecordingSessionContext context,
    SessionReadyEvent event,
  ) {
    if (_processingSessionId == context.sessionId) {
      _lastExportedPath = event.exportPath;
      _isProcessingRecording = _processingSessionIds.length > 1;
      _processingStep = RecordingProvider.processingStepCount;
      if (!_isRecording &&
          !_isRecordingStandby &&
          !_processingAudioLease.hasForegroundCapture) {
        _processingDeferredMessage = event.isFinal
            ? null
            : '可用内容已保存在本机，剩余处理将自动重试';
        _processingErrorMessage = null;
        _statusMessage = _processingDeferredMessage ?? _localSaveStatus;
      }
      _processingSessionIds.remove(context.sessionId);
      _processingSessionId = _processingSessionIds.isEmpty
          ? null
          : _processingSessionIds.last;
      notifyListeners();
    } else {
      _processingSessionIds.remove(context.sessionId);
    }
    unawaited(
      _releaseProcessingAudio(context.sessionId).then((_) {
        _sessionReadyController.add(event);
        notifyListeners();
      }),
    );
  }

  void _handleSessionProcessingError(
    RecordingSessionContext context,
    String error,
  ) {
    if (_processingSessionId == context.sessionId) {
      _isProcessingRecording = _processingSessionIds.length > 1;
      if (!_isRecording &&
          !_isRecordingStandby &&
          !_processingAudioLease.hasForegroundCapture) {
        _processingDeferredMessage = null;
        _statusMessage = '本机保存未完成，请保留原始录音';
        _processingErrorMessage = error;
      }
      _processingSessionIds.remove(context.sessionId);
      _processingSessionId = _processingSessionIds.isEmpty
          ? null
          : _processingSessionIds.last;
      notifyListeners();
    } else {
      _processingSessionIds.remove(context.sessionId);
    }
    unawaited(_releaseProcessingAudio(context.sessionId));
  }

  void _handleDeferredProcessing(
    RecordingSessionContext context,
    String message,
  ) {
    if (_disposed) return;
    _scheduleRecoveryRetry(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    );
    if (_processingSessionId != context.sessionId) return;
    if (!_isRecording &&
        !_isRecordingStandby &&
        !_processingAudioLease.hasForegroundCapture) {
      _processingDeferredMessage = '可用内容已保存在本机，剩余处理将自动重试';
      _statusMessage = _processingDeferredMessage;
      _processingErrorMessage = null;
      notifyListeners();
    }
  }

  String get _localSaveStatus => SupabaseConfig.hasValidSession
      ? '笔记与录音已保存在本机；云同步结果单独确认'
      : '笔记与录音已保存在本机；云同步暂停：原云账号未恢复';

  void _startSmartSliceTimer(RecordingSessionContext context) {
    _sliceTimer?.cancel();
    _sliceTimer = Timer.periodic(Duration(seconds: _sliceDuration), (
      timer,
    ) async {
      if (_isRotatingSlice) return;
      _isRotatingSlice = true;
      try {
        if (!_isRecording || _isPaused || _activeContext != context) {
          timer.cancel();
          return;
        }
        final path = await _audioRecorder.stop();
        if (path != null) {
          await _queueAudioSlice(path, context);
        }

        await Future.delayed(const Duration(milliseconds: 100));
        if (_isRecording && !_isPaused && _activeContext == context) {
          final nextPath = await _getTempPath();
          await _audioRecorder.start(_recordConfig, path: nextPath);
        }
      } catch (e) {
        debugPrint("Slice timer error: $e");
      } finally {
        _isRotatingSlice = false;
      }
    });
  }

  Future<void> stopRecording() async {
    _isRecording = false;
    _recordingStartedAt = null;
    _sliceTimer?.cancel();

    RecordingSessionContext? stoppedContext;
    try {
      final context = _activeContext;
      stoppedContext = context;
      if (context != null) {
        _processingSessionIds.add(context.sessionId);
        _processingSessionId = context.sessionId;
        _isProcessingRecording = true;
        _processingStep = 1;
        _processingErrorMessage = null;
        _processingDeferredMessage = null;
        _statusMessage = '正在整理最后一批录音并完成识别';
        notifyListeners();
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'recording',
          'stop_requested',
          sessionId: context?.sessionId,
        ),
      );
      // A Watch stop tap can land while the 5-second recorder rotation owns
      // AudioRecorder.stop(). Never issue a second concurrent stop call.
      final rotationDeadline = DateTime.now().add(const Duration(seconds: 8));
      while (_isRotatingSlice && DateTime.now().isBefore(rotationDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final rotationSettled = !_isRotatingSlice;
      unawaited(
        DiagnosticLogService.instance.record(
          'recording',
          rotationSettled ? 'slice_rotation_settled' : 'slice_rotation_timeout',
          sessionId: context?.sessionId,
        ),
      );

      String? path;
      var recorderStopSettled = false;
      if (rotationSettled) {
        try {
          path = await _audioRecorder.stop().timeout(
            const Duration(seconds: 5),
          );
          recorderStopSettled = true;
          unawaited(
            DiagnosticLogService.instance.record(
              'recording',
              'recorder_stopped',
              sessionId: context?.sessionId,
              fields: {'hasFinalSlice': path != null},
            ),
          );
        } catch (error) {
          unawaited(
            DiagnosticLogService.instance.record(
              'recording',
              'recorder_stop_failed',
              sessionId: context?.sessionId,
              fields: {'errorType': error.runtimeType},
            ),
          );
          debugPrint('[Recording Stop] Recorder did not stop cleanly: $error');
        }
      }

      if (path != null && context != null) {
        try {
          await _queueAudioSlice(
            path,
            context,
          ).timeout(const Duration(seconds: 5));
        } catch (error) {
          // registerPendingAudio happens before the save. Even if this times
          // out, the WAV remains recoverable on the next launch.
          unawaited(
            DiagnosticLogService.instance.record(
              'recording',
              'final_slice_queue_failed',
              sessionId: context.sessionId,
              fields: {'errorType': error.runtimeType},
            ),
          );
        }
      }
      try {
        await context?.saveShadowDraft().timeout(const Duration(seconds: 5));
      } catch (error) {
        unawaited(
          DiagnosticLogService.instance.record(
            'recording',
            'final_draft_save_failed',
            sessionId: context?.sessionId,
            fields: {'errorType': error.runtimeType},
          ),
        );
      }
      context?.sealPipelines();
      _activeContext = null;

      if (context != null) {
        // The saved lecture ends at the Watch stop tap. This separate discarded
        // capture only keeps iOS background execution alive until the original
        // finalization pipeline has safely written the MD and WAV files.
        // Keepalive is helpful but must never prevent handover. If recorder
        // shutdown was uncertain, starting it again could race the late stop.
        if (recorderStopSettled) {
          try {
            _processingAudioLease.releaseForegroundForProcessingHandoff();
            await _startProcessingKeepalive(
              context.sessionId,
            ).timeout(const Duration(seconds: 4));
          } catch (error) {
            unawaited(
              DiagnosticLogService.instance.record(
                'recording',
                'keepalive_start_failed',
                sessionId: context.sessionId,
                fields: {'errorType': error.runtimeType},
              ),
            );
          }
        } else {
          _processingAudioLease.abandonForegroundCapture();
        }
        final payload = HandoverPayload(
          context: context,
          // Exam/Lecture always produce complete first-listening documents.
          enableFinalRecap:
              _enableFinalRecap ||
              context.mode == AppMode.exam ||
              context.mode == AppMode.lecture,
          onDone: (event) {
            unawaited(
              DiagnosticLogService.instance.record(
                'recording',
                'session_ready',
                sessionId: event.sessionId,
                fields: {'mode': event.mode.name},
              ),
            );
            _handleSessionReady(context, event);
          },
          onDeferred: (message) => _handleDeferredProcessing(context, message),
          onStatus: (msg) {
            _updateBackgroundProcessingStatus(context.sessionId, msg);
          },
          onError: (err) {
            unawaited(
              DiagnosticLogService.instance.record(
                'recording',
                'handover_failed',
                sessionId: context.sessionId,
                fields: {'errorType': 'handover'},
              ),
            );
            debugPrint('[Handover Error] $err');
            _handleSessionProcessingError(context, err);
          },
        );

        // Submit to SessionBackgroundProcessor — returns immediately (<200ms)
        unawaited(SessionBackgroundProcessor.instance.submit(payload));
        unawaited(
          DiagnosticLogService.instance.record(
            'recording',
            'handover_submitted',
            sessionId: context.sessionId,
            fields: {'keepalive': _processingAudioLease.hasKeepalive},
          ),
        );
      }
    } finally {
      _activeContext = null;
      _resetForNextSession();
      if (stoppedContext == null) {
        _processingAudioLease.abandonForegroundCapture();
        await _resetAudioSessionAfterRecording();
        TtsService().allowPlaybackAfterRecording();
      }
    }
  }

  /// [Phase 3] Resets Provider state so next recording session can start immediately.
  void _resetForNextSession() {
    _orchestrator = null;
    _allNotes.clear();
    _segmentSummaries.clear();
    _finalReviewContent = null;
    _shorthandReviewContent = null;
    _identifiedLectureContext = null;
    _sessionAudioPaths.clear();
    // A stopped session keeps reporting its background finalization progress.
    // Do not erase that status while preparing the provider for another session.
    if (!_isProcessingRecording) _statusMessage = null;
    notifyListeners();
  }

  void _updateBackgroundProcessingStatus(String sessionId, String rawStatus) {
    if (_processingSessionId != sessionId) return;

    final status = rawStatus.toLowerCase();
    var nextStep = _processingStep;
    var label = '正在处理录音内容';

    if (status.contains('saving markdown')) {
      nextStep = 4;
      label = '总结已生成，正在保存 MD 文档和录音';
    } else if (status.contains('saved ok') ||
        status.contains('saved available')) {
      nextStep = 4;
      label = '总结与录音已保存';
    } else if (status.contains('generating final ai')) {
      nextStep = 3;
      label = '已发送给 AI，正在生成讲座总结';
    } else if (status.contains('finalizing translations')) {
      nextStep = 2;
      label = '正在完成转写和翻译';
    } else if (status.contains('translation') ||
        status.contains('chinese ready')) {
      nextStep = 2;
      label = '正在完成最后一批翻译';
    } else if (status.contains('finalizing audio') ||
        status.contains('flushing') ||
        status.contains('stt') ||
        status.contains('cleaning') ||
        status.contains('displaying english')) {
      nextStep = 1;
      label = '正在整理最后一批录音并完成识别';
    }

    // Late callbacks from an earlier sub-step must never make progress go back.
    if (nextStep < _processingStep) return;
    if (nextStep > _processingStep) _processingStep = nextStep;
    if (!_isRecording &&
        !_isRecordingStandby &&
        !_processingAudioLease.hasForegroundCapture) {
      _statusMessage = label;
    }
    notifyListeners();
  }

  /// 暂停录音：停止当前切片计时器和录音器，保留所有已有笔记，不做任何导出。
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused || _isPending) return;
    _isPaused = true;
    _sliceTimer?.cancel();
    // 处理暂停前的最后一段音频切片
    final path = await _audioRecorder.stop();
    if (path != null && _activeContext != null) {
      final context = _activeContext!;
      await _queueAudioSlice(path, context);
    }
    _statusMessage = "⏸ Paused";
    notifyListeners();
  }

  /// 继续录音：重启录音器和切片计时器，无缝衔接上次内容。
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused || _isPending) return;
    _isPaused = false;
    _statusMessage = null;
    final nextPath = await _getTempPath();
    await _audioRecorder.start(_recordConfig, path: nextPath);
    if (_activeContext != null) {
      _startSmartSliceTimer(_activeContext!);
    }
    notifyListeners();
  }

  /// 切换暂停/继续。
  Future<void> togglePause() async {
    if (_isPaused) {
      await resumeRecording();
    } else {
      await pauseRecording();
    }
  }

  Future<String> _getTempPath({String prefix = 'rec'}) async {
    final directory = await getApplicationDocumentsDirectory();
    return '${directory.path}/${prefix}_${DateTime.now().millisecondsSinceEpoch}.wav';
  }

  /// 有效性判断：过滤静音/填充词
  bool _isValidTranscript(String text) {
    final t = text.trim().toLowerCase();
    if (t.isEmpty || t == '...') return false;
    final fillerWords = ['嗯', '呃', '那个', 'um', 'uh', 'like', 'so'];
    if (fillerWords.contains(t)) return false;
    return true;
  }

  Future<void> _processAudio(
    String path,
    RecordingSessionContext context,
  ) async {
    if (context.isDisposed || context.orchestrator == null || path.isEmpty)
      return;
    context.registerPendingAudio(path);
    try {
      final stitchResult = await compute(
        _backgroundStitchTask,
        StitchData(context.lastAudioTail, path, kTailSize),
      );
      final processedPath = stitchResult['path'] as String;
      context.lastAudioTail = Uint8List.fromList(
        stitchResult['newTail'] as List<int>,
      );
      // Keep the original non-overlapped slice for faithful WAV playback.
      // The stitched slice contains a small previous-tail overlap and is used
      // only for safer STT across word boundaries.
      context.addRawAudioPath(path);
      context.addStitchedAudioPath(processedPath);

      final pendingNoteId = context.pendingAudioNotes[path];
      final pendingNoteIndex = pendingNoteId == null
          ? -1
          : context.notes.indexWhere((note) => note.id == pendingNoteId);
      late final String noteId;
      if (pendingNoteIndex >= 0) {
        noteId = context.notes[pendingNoteIndex].id;
        context.notes[pendingNoteIndex].isProcessing = true;
      } else {
        final currentNote = InsightNote(
          summary: '',
          transcript: '...',
          timestamp: DateTime.now(),
          isProcessing: true,
        );
        noteId = currentNote.id;
        context.bindPendingAudioToNote(path, noteId);
        context.addAudioNote(path, currentNote);
      }
      if (context == _activeContext) {
        notifyListeners();
      }

      // 提取最近两次的翻译历史作为上下文
      final List<Map<String, String>> historyList = [];
      final List<InsightNote> nonSummaryNotes = context.notes
          .where(
            (n) =>
                !n.isSummary &&
                n.transcript.isNotEmpty &&
                n.transcript != '...' &&
                n.translatedContent != null &&
                n.translatedContent!.isNotEmpty &&
                !n.translatedContent!.startsWith('['),
          )
          .toList();

      if (nonSummaryNotes.length >= 2) {
        for (
          var i = nonSummaryNotes.length - 2;
          i < nonSummaryNotes.length;
          i++
        ) {
          historyList.add({
            'english': nonSummaryNotes[i].transcript,
            'chinese': nonSummaryNotes[i].translatedContent!,
          });
        }
      } else if (nonSummaryNotes.isNotEmpty) {
        historyList.add({
          'english': nonSummaryNotes.first.transcript,
          'chinese': nonSummaryNotes.first.translatedContent!,
        });
      }

      await context.orchestrator!.processAudioSegment(
        noteId,
        processedPath,
        context: context.lastTranscript,
        translationHistory: historyList,
        onStatus: (msg) {
          if (context == _activeContext) {
            _statusMessage = msg;
            notifyListeners();
          }
        },
      );

      final index = context.notes.indexWhere((n) => n.id == noteId);
      if (index != -1) {
        context.notes[index].isProcessing = false;
        context.completeTranscriptForAudio(
          path,
          context.notes[index].transcript,
        );
        // 闲谈模式：对每个有效 STT 结果进行实时多平台翻译
        if (context.mode == AppMode.freeTalk &&
            _isValidTranscript(context.notes[index].transcript)) {
          await context.saveShadowDraft();
        }
        if (context == _activeContext) {
          notifyListeners();
        }

        // 每40秒分段 AI 摘要积累
        if (context.mode != AppMode.freeTalk) {
          final transcript = context.notes[index].transcript;
          if (_isValidTranscript(transcript)) {
            context.segmentTranscriptBuffer.add(transcript);
            context.segmentSummaryCounter++;
            if (context.segmentSummaryCounter >= _slicesPerRollingUpdate &&
                !context.isGeneratingSegmentSummary) {
              context.segmentSummaryCounter = 0;
              await _generateSegmentSummaryForContext(context);
            }
          }
        }
      }
      context.completePendingAudio(path);
      await context.saveShadowDraft();
    } catch (e) {
      if (e is ApiRateLimitException) {
        await context.saveShadowDraft();
        _scheduleRecoveryRetry(e.retryAt);
        if (context == _activeContext) {
          _statusMessage = '识别服务限流，录音已保留；稍后自动继续';
          notifyListeners();
        }
        rethrow;
      }
      if (e is SttUnavailableException) {
        final pendingNoteId = context.pendingAudioNotes[path];
        final pendingNoteIndex = pendingNoteId == null
            ? -1
            : context.notes.indexWhere((note) => note.id == pendingNoteId);
        if (pendingNoteIndex >= 0) {
          final note = context.notes[pendingNoteIndex];
          note.isProcessing = false;
          if (note.transcript == '...') {
            note.transcript = '[等待重新识别]';
          }
        }
        await context.saveShadowDraft();
        if (context == _activeContext) {
          _statusMessage = '识别服务暂时不可用，录音已保留；恢复连接后可重试';
          notifyListeners();
        }
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'recording',
          'pipeline_failed',
          sessionId: context.sessionId,
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint("Pipeline Error: $e");
      if (e is SttUnavailableException) rethrow;
    }
  }

  /// Updates one stable working-note draft from each ~60 second window.
  Future<void> _generateSegmentSummaryForContext(
    RecordingSessionContext context,
  ) async {
    if (context.isGeneratingSegmentSummary ||
        context.segmentTranscriptBuffer.isEmpty ||
        context.translationService == null) {
      return;
    }
    context.isGeneratingSegmentSummary = true;
    final material = context.segmentTranscriptBuffer.join(' ');
    context.segmentTranscriptBuffer.clear();
    final previousDraft = context.segmentSummaries.isEmpty
        ? '(No previous draft. Build the first working note.)'
        : context.segmentSummaries.last;
    try {
      final isRollingNotesMode =
          context.mode == AppMode.exam || context.mode == AppMode.lecture;
      final summary = await ApiScheduler().enqueue(
        () => context.translationService!.summarize(
          isRollingNotesMode
              ? '[CURRENT DRAFT]\n$previousDraft\n\n'
                    '[NEW TRANSCRIPT]\n$material'
              : material,
          strategy: isRollingNotesMode
              ? PromptStrategy.rollingNotes
              : PromptStrategy.recap,
          mode: context.mode,
          unit: context.unit,
        ),
        sessionId: context.sessionId,
      );
      if (summary.trim().isNotEmpty) {
        if (isRollingNotesMode) {
          context.segmentSummaries
            ..clear()
            ..add(summary.trim());
        } else {
          context.segmentSummaries.add(summary.trim());
        }
        await context.saveShadowDraft();
        unawaited(
          DiagnosticLogService.instance.record(
            'notes',
            isRollingNotesMode
                ? 'rolling_draft_updated'
                : 'segment_summary_completed',
            sessionId: context.sessionId,
            fields: {'inputChars': material.length},
          ),
        );
      }
    } catch (e) {
      unawaited(
        DiagnosticLogService.instance.record(
          'notes',
          'rolling_update_failed',
          sessionId: context.sessionId,
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint('[Segment Summary ${context.sessionId}] $e');
      context.segmentTranscriptBuffer.insert(0, material);
    } finally {
      context.isGeneratingSegmentSummary = false;
    }
  }

  /// Gemini 通用调用（用于 Groq 兜底）
  Future<String?> _callGemini(String systemPrompt, String userMessage) async {
    final key = _apiKeys[AIProvider.gemini] ?? '';
    if (key.isEmpty) return null;
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$key',
      );
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {'text': systemPrompt},
                ],
              },
              'contents': [
                {
                  'parts': [
                    {'text': userMessage},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.5},
            }),
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final text = parts[0]['text'] as String?;
            if (text != null && text.trim().isNotEmpty) return text.trim();
          }
        }
      }
    } catch (e) {
      debugPrint('[Gemini Fallback] Error: $e');
    }
    return null;
  }

  Future<void> _checkRecoveryCache() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) {
      _hasRecoveredCache = true;
      notifyListeners();
    }
  }

  Future<void> recoverFromCache() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) {
      final content = await file.readAsString();
      final Map<String, dynamic> data = jsonDecode(content);
      _allNotes.clear();
      _allNotes.addAll(
        (data['notes'] as List).map((i) => InsightNote.fromJson(i)).toList(),
      );
      _hasRecoveredCache = false;
      notifyListeners();
    }
  }

  Future<void> dismissRecovery() async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}/shadow_draft.json');
    if (await file.exists()) await file.delete();
    _hasRecoveredCache = false;
    notifyListeners();
  }

  Future<void> generateFinalAcademicReview() async {
    // ⚠️ Bug fix: 即使 _aiService 为 null 或 AI 调用失败，也必须保证 _exportToMarkdown()
    // 被执行（用 try/finally），否则 Discussion/Lecture 模式在开启 Final Recap 时将
    // 因服务未就绪而导致 MD 文件永远无法生成。
    _isGeneratingFinalReview = true;
    notifyListeners();
    try {
      if (_aiService == null) {
        _finalReviewContent = "[AI service not ready — recap skipped]";
        _shorthandReviewContent = null;
        debugPrint(
          "[Final Academic Review] _aiService is null, skipping recap.",
        );
      } else {
        final material = _allNotes
            .where((n) => !n.isSummary)
            .map((n) => n.transcript)
            .join(" ");
        if (material.isEmpty) {
          _finalReviewContent = "Not enough material.";
          _shorthandReviewContent = null;
        } else {
          if (_currentMode == AppMode.exam) {
            // 1. 生成 Exam 考点大纲
            final examPrompt = PromptProvider.getFinalReviewPrompt(
              AppMode.exam,
              _currentUnit,
            );
            final geminiExam = await _callGemini(examPrompt, material);
            if (geminiExam != null && !geminiExam.startsWith('[')) {
              _finalReviewContent = geminiExam;
            } else {
              try {
                _finalReviewContent = await _aiService!.summarize(
                  material,
                  strategy: PromptStrategy.recap,
                  mode: AppMode.exam,
                  unit: _currentUnit,
                );
              } catch (_) {
                _finalReviewContent =
                    await _fallbackTranslationService?.summarize(
                      material,
                      strategy: PromptStrategy.recap,
                      mode: AppMode.exam,
                      unit: _currentUnit,
                    ) ??
                    "Exam recap failed.";
              }
            }

            // 2. 生成 Lecture/速记 学术讲座笔记 (用于浮窗显示与导出 Jeff_速记_xxx.md)
            final shorthandPrompt = PromptProvider.getFinalReviewPrompt(
              AppMode.lecture,
              _currentUnit,
            );
            final geminiShorthand = await _callGemini(
              shorthandPrompt,
              material,
            );
            if (geminiShorthand != null && !geminiShorthand.startsWith('[')) {
              _shorthandReviewContent = geminiShorthand;
            } else {
              try {
                _shorthandReviewContent = await _aiService!.summarize(
                  material,
                  strategy: PromptStrategy.recap,
                  mode: AppMode.lecture,
                  unit: _currentUnit,
                );
              } catch (_) {
                _shorthandReviewContent = await _fallbackTranslationService
                    ?.summarize(
                      material,
                      strategy: PromptStrategy.recap,
                      mode: AppMode.lecture,
                      unit: _currentUnit,
                    );
              }
            }
            // 浮窗弹出的总结直接展现【速记】
            // _shorthandReviewContent 已赋值供导出和浮窗展示
          } else {
            final recapPrompt = PromptProvider.getFinalReviewPrompt(
              _currentMode,
              _currentUnit,
            );
            final geminiRecap = await _callGemini(recapPrompt, material);
            if (geminiRecap != null && !geminiRecap.startsWith('[')) {
              _finalReviewContent = geminiRecap;
            } else {
              try {
                _finalReviewContent = await _aiService!.summarize(
                  material,
                  strategy: PromptStrategy.recap,
                  mode: _currentMode,
                  unit: _currentUnit,
                );
              } catch (mainError) {
                if (_fallbackTranslationService != null) {
                  try {
                    _finalReviewContent = await _fallbackTranslationService!
                        .summarize(
                          material,
                          strategy: PromptStrategy.recap,
                          mode: _currentMode,
                          unit: _currentUnit,
                        );
                  } catch (_) {
                    _finalReviewContent = "Recap failed all services.";
                  }
                } else {
                  _finalReviewContent =
                      "Recap failed and no fallback configured.";
                }
              }
            }
          }
        }
      }
    } finally {
      // 无论 AI 是否成功，始终执行导出，确保 MD 文件一定被写入磁盘。
      _isGeneratingFinalReview = false;
      notifyListeners();
      await _exportToMarkdown();
    }
  }

  String _highlightText(String text) {
    String result = text;
    // Numbers / statistics
    result = result.replaceAllMapped(
      RegExp(
        r'(\d+(?:\.\d+)?\s*(?:%|percent|million|billion|thousand|trillion))',
        caseSensitive: false,
      ),
      (m) => '==${m[1]}==',
    );
    // Academic signal words
    const signalWords = [
      'however',
      'therefore',
      'because of',
      'as a result',
      'consequently',
      'in contrast',
      'on the other hand',
      'for example',
      'for instance',
      'in addition',
      'moreover',
      'furthermore',
      'nevertheless',
      'notably',
      'importantly',
      'specifically',
      'in particular',
    ];
    for (final word in signalWords) {
      result = result.replaceAllMapped(
        RegExp(
          '(?<![=])\\b${RegExp.escape(word)}\\b(?![=])',
          caseSensitive: false,
        ),
        (m) => '==${m[0]}==',
      );
    }
    return result;
  }

  /// Wraps Pathways 3 Target Vocabulary words with ==word== in the English script.
  /// Skips words that are already highlighted. Only runs when a unit is selected.
  String _applyVocabularyHighlight(String text, PathwaysUnit unit) {
    if (unit == PathwaysUnit.none) return text;
    final vocab = PromptProvider.getUnitVocabularyList(unit);
    String result = text;
    for (final word in vocab) {
      // Match whole word only, case-insensitive, skip if already inside ==...==
      final pattern = RegExp(
        '(?<!==)(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])(?!==)',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(pattern, (m) => '==${m[0]}==');
    }
    return result;
  }

  String _generateFallbackShorthandFromTranscripts() {
    final transcripts = _allNotes.where((n) => !n.isSummary).toList();
    if (transcripts.isEmpty) return "";
    return '【全篇逻辑播报·可播放】\n'
        'AI逻辑播报整理未完成，请直接使用后方中英文全文核对讲座内容。\n'
        '━━━━━━━━━━━━\n'
        '【答题重点与危险位置·可播放】\n'
        'AI答题证据整理未完成，请根据全文核对英文原词、数字、否定、转折和限定范围。';
  }

  String _compactShorthandLayout(String content) => content
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .join('\n')
      .trim();

  Future<void> _exportToMarkdown() async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmm').format(now);
      final isDiscussion = _currentMode == AppMode.discussion;
      final isExam = _currentMode == AppMode.exam;
      final prefix = isDiscussion
          ? "Jeff_Discussion"
          : isExam
          ? "Jeff_Exam"
          : "Jeff_Notes";
      final filename = "${prefix}_$dateStr.md";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$filename');

      final StringBuffer sb = StringBuffer();

      if (isDiscussion) {
        sb.writeln("# Group Discussion Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln(
          "**Context:** ${_identifiedLectureContext ?? 'Group Discussion'}",
        );
      } else if (isExam) {
        sb.writeln("# Exam Listening Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln(
          "**Context:** ${_identifiedLectureContext ?? 'Exam Listening'}",
        );
      } else {
        sb.writeln("# Academic Lecture Session");
        sb.writeln("**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}");
        sb.writeln(
          "**Context:** ${_identifiedLectureContext ?? 'General Academic Lecture'}",
        );
      }
      sb.writeln();

      // ── Part 1: AI Review ──────────────────────────────────
      if (_finalReviewContent != null && _finalReviewContent!.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        if (isDiscussion) {
          sb.writeln("## Part 1 · AI Discussion Recap");
        } else if (isExam) {
          sb.writeln("## Part 1 · Exam Answer Card");
        } else {
          sb.writeln("## Part 1 · AI Academic Review");
        }
        sb.writeln();
        sb.writeln(_finalReviewContent);
        sb.writeln();
      }

      // ── Part 2: Full Script ────────────────────────────────
      final transcripts = _allNotes.where((n) => !n.isSummary).toList();
      if (transcripts.isNotEmpty) {
        sb.writeln("---");
        sb.writeln();
        sb.writeln("## Part 2 · Full Script");
        sb.writeln();

        final List<String> chineseSegments = [];
        final List<String> englishSegments = [];

        for (int i = 0; i < transcripts.length; i++) {
          final note = transcripts[i];
          final engText = note.transcript.trim();
          if (engText.isEmpty ||
              engText == '...' ||
              engText.startsWith('[Silence') ||
              engText.startsWith('[Error'))
            continue;

          englishSegments.add(engText);

          final zhText = note.translatedContent?.trim();
          if (zhText != null && zhText.isNotEmpty && !zhText.startsWith('[')) {
            chineseSegments.add(zhText);
          }
        }

        sb.writeln("### 中文全文 (Chinese Transcript)");
        sb.writeln();
        sb.writeln(chineseSegments.join(" "));
        sb.writeln();
        sb.writeln();

        sb.writeln("### 英文全文 (English Transcript)");
        sb.writeln();
        sb.writeln(
          _highlightText(
            _applyVocabularyHighlight(englishSegments.join(" "), _currentUnit),
          ),
        );
        sb.writeln();
      }

      await file.writeAsString(sb.toString());
      debugPrint("\x1B[32m[Export OK] ${file.absolute.path}\x1B[0m");

      // ── Exam 模式下，额外独立保存一份《Jeff_速记_yyyyMMdd_HHmm.md》（浮窗同款学术速记） ──
      final shorthandContentToUse =
          (_shorthandReviewContent != null &&
              _shorthandReviewContent!.isNotEmpty)
          ? _shorthandReviewContent
          : _generateFallbackShorthandFromTranscripts();

      if (isExam &&
          shorthandContentToUse != null &&
          shorthandContentToUse.isNotEmpty) {
        try {
          final shorthandFilename = "Jeff_速记_$dateStr.md";
          final shorthandFile = File('${directory.path}/$shorthandFilename');
          final StringBuffer sbShort = StringBuffer();
          sbShort.writeln(_compactShorthandLayout(shorthandContentToUse));

          final transcripts = _allNotes.where((n) => !n.isSummary).toList();
          if (transcripts.isNotEmpty) {
            final List<String> chineseSegments = [];
            final List<String> englishSegments = [];

            for (int i = 0; i < transcripts.length; i++) {
              final note = transcripts[i];
              final engText = note.transcript.trim();
              if (engText.isEmpty ||
                  engText == '...' ||
                  engText.startsWith('[Silence') ||
                  engText.startsWith('[Error'))
                continue;
              englishSegments.add(engText);
              final zhText = note.translatedContent?.trim();
              if (zhText != null &&
                  zhText.isNotEmpty &&
                  !zhText.startsWith('[')) {
                chineseSegments.add(zhText);
              }
            }

            sbShort.writeln("━━━━━━━━━━━━");
            sbShort.writeln("【中文全文】");
            sbShort.writeln(chineseSegments.join(" "));
            sbShort.writeln("━━━━━━━━━━━━");
            sbShort.writeln("【英文全文】");
            sbShort.writeln(
              _highlightText(
                _applyVocabularyHighlight(
                  englishSegments.join(" "),
                  _currentUnit,
                ),
              ),
            );
          }

          await shorthandFile.writeAsString(sbShort.toString());
          debugPrint(
            "\x1B[32m[Shorthand Export OK] ${shorthandFile.absolute.path}\x1B[0m",
          );
          await _uploadToSupabase(shorthandFile, 'notes');
        } catch (shorthandError) {
          debugPrint("[Shorthand Export Error] $shorthandError");
        }
      }

      // ── 缝合当次 session 所有的真实录音切片，导出为同名的 .wav 录音文件 ──
      if (_sessionAudioPaths.isNotEmpty) {
        final wavFilename = filename.replaceAll('.md', '.wav');
        final wavPath = '${directory.path}/$wavFilename';
        await _stitchSessionAudioFiles(_sessionAudioPaths, wavPath);
      }

      final module = isDiscussion
          ? 'discussion'
          : isExam
          ? 'exam'
          : 'listening';
      await _uploadToSupabase(file, module);
      _lastExportedPath = file.absolute.path;
      notifyListeners();
    } catch (e) {
      debugPrint("[Export Error] $e");
    }
  }

  Future<void> _stitchSessionAudioFiles(
    List<String> paths,
    String outputPath,
  ) async {
    try {
      final List<int> allPcm = [];
      for (final p in paths) {
        final f = File(p);
        if (!await f.exists()) continue;
        final bytes = await f.readAsBytes();
        final offset = _findDataChunkOffset(bytes);
        if (bytes.length > offset) {
          allPcm.addAll(bytes.sublist(offset));
        }
      }
      if (allPcm.isNotEmpty) {
        final header = _generateWavHeaderStatic(allPcm.length);
        final stitchedBytes = Uint8List.fromList([...header, ...allPcm]);
        await File(outputPath).writeAsBytes(stitchedBytes);
        debugPrint(
          '[SessionAudio] Successfully stitched ${paths.length} audio slices to $outputPath',
        );
      }
    } catch (e) {
      debugPrint('[SessionAudio] Stitch error: $e');
    }
  }

  Future<void> _uploadToSupabase(File file, String module) async {
    try {
      final bytes = await file.readAsBytes();
      final hash = md5.convert(bytes).toString();
      final title = file.path.split('/').last;

      var userId = '';
      try {
        userId = SupabaseConfig.currentUserId;
      } catch (_) {
        await SupabaseConfig.signInAnonymously();
        try {
          userId = SupabaseConfig.currentUserId;
        } catch (_) {}
      }

      final map = <String, dynamic>{
        'file_hash': hash,
        'module': module,
        'title': title,
        'content_md': utf8.decode(bytes),
        'file_size': bytes.length,
      };
      // Do not create an unscoped archive row. FileSyncAgent will retry this
      // file once authentication provides a stable user identity.
      if (userId.isEmpty) return;
      map['user_id'] = userId;
      final uploaded = await UploadCache.runSingleFlight(
        hash,
        userId: userId,
        operation: () async {
          if (!CloudIdentityGuard.stillCurrent(userId)) {
            throw StateError('Authentication identity changed during sync');
          }
          await SupabaseConfig.client.from('archives').insert(map);
          return true;
        },
      );
      if (uploaded) debugPrint('[Supabase Upload OK] $title ($module)');
    } catch (e) {
      debugPrint('[Supabase Upload Error] $e');
    }
  }

  @visibleForTesting
  static String buildEssayTopicPriorityRules() =>
      """### USER TOPIC HAS CONTENT PRIORITY:
The user's topic, keywords, named subjects, and explicit position are the primary source of meaning.
The selected essay type and comparison direction are also explicit user choices and must be followed.
Do not replace the user's intended issue with an easier or unrelated topic merely to fit the essay structure or preferred aspects.

The user's input may be a short keyword phrase, an incomplete question, or grammatically incorrect English.
Before planning the essay, silently reconstruct it as the clearest natural English topic or question while preserving every meaningful keyword and the likely intended position.
Correct grammar, spelling, word forms, and missing function words without commenting on the correction.
If an essential subject or context is omitted, infer only the most common school-essay interpretation needed to make the keywords coherent.
If more than one interpretation remains possible, use the narrowest, most ordinary meaning directly supported by the input and avoid adding unrelated details.
Do not print a topic-correction explanation; simply write the essay about the reconstructed meaning.

Examples of silent reconstruction:
- "subsidy school lunches" can be understood as "Should students be provided with subsidized school lunches?"
- "required wear a helmets" can be understood in the common school-essay context as "Should bicycle riders be required to wear helmets?"
These examples show how to repair an incomplete topic; they are not fixed subjects for other essays.

All structure, aspect, and style rules below are secondary to the user's intended topic. Apply them without distorting that topic.""";

  @visibleForTesting
  static String buildComparisonTopicRoutingRules() =>
      """### NORMALIZE INPUT AS A COMPARISON ESSAY:
The user has selected Comparison mode. Keep the input inside the comparison-contrast genre even when its surface wording is incomplete or resembles another question type.

Common comparison prompt forms include:
- direct instructions using compare, contrast, distinguish, similarities, or differences;
- questions such as "How are A and B alike?", "How are they different?", or "What similarities/differences do they share?";
- short pairs such as "A and B", "A vs. B", "A versus B", or "A compared with B";
- selection prompts such as "Choose two people/places/events/things";
- a category fragment such as "two singers" or a single named subject that still needs a suitable counterpart.

Routing rules:
- If two subjects are named, preserve and compare exactly those two subjects.
- If the user asks the writer to choose two subjects, choose two familiar subjects from the requested category.
- If only one specific subject is supplied, keep it and add only one closely matched, familiar subject from the same category when a second subject is necessary.
- Treat "A vs. B" as two subjects to compare, not as an instruction to choose a winner.
- Follow the separately selected Similarities-only or Differences-only direction even when the raw topic merely says "compare" or "vs."
- Never turn the result into a recommendation, agree/disagree response, advantages/disadvantages list, or argumentative essay.""";

  @visibleForTesting
  static String buildArgumentativeTopicRoutingRules() =>
      """### NORMALIZE INPUT AS AN ARGUMENTATIVE ESSAY:
The user has selected Argumentative mode. Silently turn the input into one clear, debatable issue and keep the essay inside the argumentative genre.

Common argumentative prompt forms include:
- policy or obligation questions using should, should not, must, require, allow, prohibit, or ban;
- opinion questions such as "Do you agree or disagree?", "What do you think?", "Is this right/fair/a good idea?";
- choice questions such as "Which is better?", "Which should people choose?", "Do you prefer A or B?", or "A vs. B";
- evaluation questions about whether advantages outweigh disadvantages, or whether benefits are greater than problems;
- a statement, noun phrase, or keyword fragment that names an issue but omits the full question.

Routing rules:
- Preserve the user's named subject, action, policy, alternatives, and any explicit position.
- If the user states a position, argue for that position rather than reversing it.
- If the input is neutral, choose one clear position that can be supported naturally without claiming that it is the user's personal belief.
- If two alternatives are given, take a clear position on which alternative should be preferred while still treating the other side fairly in the concession paragraph.
- If the input only names an issue, reconstruct the most ordinary debatable question suggested by those keywords before choosing a position.
- Do not write a neutral comparison, a simple list of pros and cons, an informational report, or a cause-and-effect-only essay.
- The final essay must contain a clear thesis, supporting reasons, and a fair opposing view followed by refutation.""";

  @visibleForTesting
  static String buildComparisonEssayPrompt(String? comparisonFocus) {
    final similarities = comparisonFocus == 'Similarities';
    final focusLabel = similarities ? 'SIMILARITIES ONLY' : 'DIFFERENCES ONLY';
    final focusNoun = similarities ? 'similarities' : 'differences';
    final thesisVerb = similarities ? 'are similar' : 'are different';
    final topicPriorityRules = buildEssayTopicPriorityRules();
    final topicRoutingRules = buildComparisonTopicRoutingRules();

    return """You are a simple, accessible English essay generator for English learners.
Your task is to generate a standardized 5-paragraph comparison-contrast essay based on the user's two subjects, followed by its precise Chinese translation.

$topicPriorityRules

$topicRoutingRules

### REQUIRED COMPARISON DIRECTION: $focusLabel
The entire essay must compare $focusNoun only.
Body 1, Body 2, and Body 3 must all follow this same direction.
Do NOT mix similarities and differences.
Do NOT turn the essay into an argumentative essay, choose a winner, present an opposing view, or write a refutation.

### TOPICS THAT ASK THE WRITER TO CHOOSE TWO SUBJECTS:
If the topic asks you to choose two people, places, events, or things, select two widely familiar subjects from the same category before writing.
Name both selected subjects clearly in the introduction and use the same two subjects throughout the essay.
Choose subjects that can be compared naturally through three clear, practical aspects.

### THREE FLEXIBLE COMPARISON ASPECTS:
First consider these preferred aspects:
1. Cost: money, expenses, savings, or financial pressure.
2. Time: speed, convenience, flexibility, schedules, or time required.
3. Happiness: comfort, stress, enjoyment, satisfaction, or feelings.

Before writing, choose exactly three simple, practical comparison aspects that fit both subjects naturally.
Use Cost, Time, and Happiness when they genuinely fit the topic.
If one or more preferred aspects do not fit, replace only the unsuitable ones with clearer topic-related aspects such as safety, health, access, learning, experience, or environmental impact.
Never force an awkward connection merely to include Cost, Time, or Happiness.
Keep the three chosen aspects distinct and use the same aspects consistently in the thesis, body paragraphs, and conclusion.
Do not choose abstract or academic criteria that require difficult vocabulary.

### CRITICAL RULES (MUST FOLLOW STRICTLY):
1. ENGLISH PARAGRAPH COUNT: EXACTLY 5 PARAGRAPHS.
2. SENTENCE COUNT: 4 TO 5 SENTENCES PER PARAGRAPH. Never exceed 5 sentences.
3. PERSPECTIVE: Objective 3rd-person.
4. VOCABULARY: Very simple, everyday English (Junior High / High School level). NEVER use complex academic words such as "indispensable", "crucial", "facilitate", "paramount", "furthermore", or "moreover".
5. TRANSITIONS: Paragraphs 2 to 5 must include natural highlighted transitions wrapped in ==double equals==.
6. EXAMPLES: Body 1 and Body 2 must each include one short, realistic example that fits the topic. Body 3 does not require an example.
7. EVIDENCE: Never invent statistics, surveys, research, experts, or quotations.

### REQUIRED 5-PARAGRAPH STRUCTURE:

- Paragraph 1 (Introduction — Exactly 4 Sentences):
  Sentence 1: Introduce the general topic naturally and simply.
  Sentence 2: Introduce both Subject A and Subject B.
  Sentence 3: Explain why people may compare these two subjects without arguing that one is better.
  Sentence 4 (Thesis): State clearly that Subject A and Subject B $thesisVerb in terms of the three chosen practical aspects, and name all three aspects.

- Paragraph 2 (Body 1 — Chosen Aspect 1, 4-5 Sentences):
  Begin with ==First== and compare both subjects only in terms of the first chosen aspect.
  Explain one clear $focusNoun point involving both Subject A and Subject B.
  Include one short, concrete example that fits the topic using ==For example==.
  End with a simple sentence summarizing this $focusNoun point.

- Paragraph 3 (Body 2 — Chosen Aspect 2, 4-5 Sentences):
  Begin with ==Second== and compare both subjects only in terms of the second chosen aspect.
  Explain one clear $focusNoun point involving both Subject A and Subject B.
  Include one short, concrete example that fits the topic using ==For instance==.
  End with a simple sentence summarizing this $focusNoun point.

- Paragraph 4 (Body 3 — Chosen Aspect 3, 4-5 Sentences):
  Begin with ==Finally== and compare both subjects only in terms of the third chosen aspect.
  Explain one clear $focusNoun point involving both Subject A and Subject B.
  Do not introduce either of the first two chosen aspects in this paragraph.
  Do not use an opposing-view/refutation structure.

- Paragraph 5 (Conclusion — Exactly 4 Sentences):
  Begin with ==In conclusion==.
  Restate that the two subjects $thesisVerb in the same three chosen aspects.
  Summarize the three $focusNoun points without introducing a new idea.
  End with a neutral comparison statement. Do not choose a winner.

### NATURAL ESL STYLE:
- Prefer short, direct sentences with one main idea.
- Use ordinary examples that fit the specific topic naturally.
- Avoid exaggerated claims and AI-sounding expressions such as "In today's rapidly changing world", "It is undeniable that", "plays a crucial role", "a multifaceted issue", "a myriad of", "profound impact", "delve into", or "navigate the complexities".
- Do not use semicolons or long, complicated clauses.
- Do not repeat the same sentence pattern unnecessarily.

### OUTPUT FORMAT REQUIREMENT:
The output must strictly contain two parts separated by ---:

Part 1: The English Essay with == highlighters.
---
Part 2: The sentence-by-sentence Chinese translation.

### FINAL SILENT CHECK:
Before answering, silently verify that:
- the English essay has exactly 5 paragraphs;
- all three body paragraphs discuss both subjects;
- all three body paragraphs contain $focusNoun only;
- Body 1 and Body 2 each contain one realistic, topic-related example;
- exactly three suitable aspects are chosen and used in the same order throughout;
- Cost, Time, or Happiness is not forced when it does not fit the topic naturally;
- the essay does not choose a winner or become argumentative.
If any check fails, revise the essay before returning it.""";
  }

  @visibleForTesting
  static String buildArgumentativeBody3Rules() =>
      """- Paragraph 4 (Body 3 - Main Concession & Refutation Paragraph, 5-7 Sentences):
  This is the most important body paragraph. Use the remaining third chosen aspect.
  Sentence 1: Present one clear opposing view using ==On the other hand== or ==Some people argue==.
  Sentence 2: Explain briefly why this opposing concern may seem reasonable.
  Sentence 3: Acknowledge a limited part of the concern using ==Although== or another simple concession.
  Sentence 4: Use ==However== to state the main refutation clearly.
  Sentences 5-6: Explain the refutation with a simple reason and, when natural, one short everyday example using ==For example==.
  Sentence 7 (Optional): End by connecting the refutation back to the essay's main position.
  Keep the logic natural and simple. Do not use complex academic refutation language.""";

  Future<String> generateEssayMatrix(
    String finalTopic, {
    String essayType = 'Argumentative',
    String? comparisonFocus,
  }) async {
    final topicPriorityRules = buildEssayTopicPriorityRules();
    final topicRoutingRules = buildArgumentativeTopicRoutingRules();
    final argumentativeBody3Rules = buildArgumentativeBody3Rules();
    final argumentativePrompt =
        """You are a simple, accessible English essay generator for English learners.
Your task is to generate a standardized 5-paragraph essay based on the user's provided topic, followed by its precise Chinese translation.

$topicPriorityRules

$topicRoutingRules

### CORE CONCEPT (THREE FLEXIBLE PRACTICAL ASPECTS):
First consider Cost (money/expenses), Happiness (mental state/feelings), and Time (convenience/efficiency) as preferred aspects.
Before writing, choose exactly three simple, practical aspects that support the main position and fit the specific topic naturally.
Use each preferred aspect when it genuinely fits. If one or more do not fit, replace only the unsuitable ones with clearer topic-related aspects such as safety, health, access, learning, experience, or environmental impact.
Never force a weak or awkward connection merely to include Cost, Happiness, or Time.
Use the same three chosen aspects consistently in the thesis, Body 1, Body 2, Body 3, and conclusion, in whichever order best fits the topic.

### CRITICAL RULES (MUST FOLLOW STRICTLY):
1. PARAGRAPH COUNT: EXACTLY 5 PARAGRAPHS.
2. SENTENCE COUNT: Paragraphs 1, 2, 3, and 5 must contain 4 to 5 sentences. Body 3 (Paragraph 4) may contain 5 to 7 sentences because it is the main concession and refutation paragraph. Never exceed 7 sentences in Body 3!
3. PERSPECTIVE: Objective 3rd-person.
4. VOCABULARY: Very simple, everyday English (Junior High / High School level). NEVER use complex academic words (e.g., avoid "indispensable", "crucial", "facilitate", "paramount", "furthermore", "moreover").
5. TRANSITIONS: Paragraphs 2 to 5 MUST include highlighted transitions wrapped in ==double equals== (e.g., ==First==, ==Second==, ==For example==, ==On the other hand==, ==However==, ==In conclusion==).

### FLEXIBLE 5-PARAGRAPH SKELETON:

- Paragraph 1 (Intro - Standard 4-Step Structure):
  Sentence 1 [Hook]: Write one simple, natural hook that fits the specific topic. Vary the hook style instead of using a fixed sentence pattern. Do not assume the topic is about students, schools, families, or daily life unless the user's topic says so.
  Sentence 2 [Background Info]: Give one short piece of background information that is directly relevant to the specific topic.
  Sentence 3 [Controversy/Problem]: Explain the topic's main disagreement or problem in simple terms. Mention particular people, groups, or institutions only when they are relevant to the user's topic.
  Sentence 4 [Thesis Statement]: State a clear main position and name the three chosen practical aspects that support it, in the same order as the body paragraphs. Do not automatically call something "the best choice" or assume that the topic must have a positive effect.

- Paragraph 2 (Body 1 - Support Aspect A):
  Use the first chosen aspect that supports the main position most directly.
  Sentence 1: Begin with ==First== and write a simple topic sentence that connects the essay's main position to Aspect A.
  Sentence 2-5: Use 3 to 4 simple sentences to explain why or how, ending with a clean summary sentence.

- Paragraph 3 (Body 2 - Support Aspect B + Example):
  Use the second chosen aspect, which should naturally fit a short, realistic example.
  Sentence 1: Begin with ==Second== and write a simple topic sentence that connects the essay's main position to Aspect B.
  Sentence 2: Explain the main point simply.
  Sentence 3-4 [Concrete Example]: Introduce a short, topic-related example using ==For example==.
  Sentence 5 (Optional): Summarize the benefit.

$argumentativeBody3Rules

- Paragraph 5 (Conclusion):
  Sentence 1: Begin with ==In conclusion== and restate the essay's main position in a simple sentence that fits the specific topic.
  Sentences 2-4: Summarize how the same three chosen aspects support that position in simple sentences. Do not introduce a new idea.

### FINAL SILENT CHECK:
Before answering, silently verify that:
- all three chosen aspects fit the topic naturally;
- no preferred aspect is forced when it creates a weak or awkward point;
- the same three aspects appear consistently in the thesis, body paragraphs, and conclusion;
- the wording is simple, natural, and easy for an English learner to understand.
If any check fails, revise the essay before returning it.

### OUTPUT FORMAT REQUIREMENT:
The output MUST strictly contain two parts separated by ---:

Part 1: The English Essay with == highlighters.
---
Part 2: The sentence-by-sentence Chinese translation.""";

    final isComparison = essayType == 'Comparison';
    final systemPrompt = isComparison
        ? buildComparisonEssayPrompt(comparisonFocus)
        : argumentativePrompt;
    final focusLine = isComparison
        ? '\nComparison Focus: ${comparisonFocus ?? 'Differences'}'
        : '';
    final userRequest = 'Type: $essayType$focusLine\nTopic: $finalTopic';
    final generationTemperature = isComparison ? 0.3 : 0.7;

    // Try Gemini 2.5 Flash first
    final geminiKey = this.geminiKey.trim();
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$geminiKey",
        );

        final response = await http
            .post(
              url,
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({
                "system_instruction": {
                  "parts": [
                    {"text": systemPrompt},
                  ],
                },
                "contents": [
                  {
                    "parts": [
                      {"text": userRequest},
                    ],
                  },
                ],
                "generationConfig": {"temperature": generationTemperature},
              }),
            )
            .timeout(const Duration(seconds: 120));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) {
                return text.trim();
              }
            }
          }
        }
        debugPrint(
          "[Essay] Gemini failed (${response.statusCode}), falling back to Groq...",
        );
      } catch (e) {
        debugPrint("[Essay] Gemini exception: $e, falling back to Groq...");
      }
    } else {
      debugPrint("[Essay] No Gemini key configured, using Groq...");
    }

    final groqResult = await _generateEssayWithChatCompletion(
      baseUrl: 'https://api.groq.com/openai/v1/chat/completions',
      apiKey: groqKey.trim(),
      model: 'openai/gpt-oss-120b',
      systemPrompt: systemPrompt,
      userRequest: userRequest,
      temperature: generationTemperature,
      providerName: 'Groq',
    );
    if (groqResult != null) return groqResult;

    final openRouterResult = await _generateEssayWithChatCompletion(
      baseUrl: 'https://openrouter.ai/api/v1/chat/completions',
      apiKey: openRouterKey.trim(),
      model: 'google/gemini-2.5-flash-lite',
      systemPrompt: systemPrompt,
      userRequest: userRequest,
      temperature: generationTemperature,
      providerName: 'OpenRouter',
    );
    if (openRouterResult != null) return openRouterResult;

    throw Exception('作文生成失败：Gemini、Groq 和 OpenRouter 都没有返回可用内容。');
  }

  Future<String?> _generateEssayWithChatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userRequest,
    required double temperature,
    required String providerName,
  }) async {
    if (apiKey.isEmpty) {
      debugPrint('[Essay] $providerName API Key is not configured.');
      return null;
    }
    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userRequest},
              ],
              'temperature': temperature,
              'max_tokens': 4096,
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        debugPrint('[Essay] $providerName failed (${response.statusCode}).');
        return null;
      }
      final data = jsonDecode(response.body);
      final text = data['choices']?[0]?['message']?['content'] as String?;
      if (text == null || text.trim().isEmpty) {
        debugPrint('[Essay] $providerName returned an empty essay.');
        return null;
      }
      return text.trim();
    } catch (e) {
      debugPrint('[Essay] $providerName exception: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _fastSub?.cancel();
    _accurateSub?.cancel();
    _orchestrator?.dispose();
    _fastAiService?.dispose();
    if (!identical(_groqService, _fastAiService)) {
      _groqService?.dispose();
    }
    _sliceTimer?.cancel();
    _recoveryRetryScheduler.dispose();
    _audioRecorder.dispose();
    _sessionReadyController.close();
    super.dispose();
  }
}
