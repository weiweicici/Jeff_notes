import 'dart:async';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../ai_orchestrator_service.dart';
import '../models.dart';
import '../openai_service.dart';
import '../services/shadow_draft_service.dart';

/// [Phase 3 Architecture]
/// Self-contained session context holding all state, notes, audio slice paths,
/// dedicated http.Client, and AI orchestrator instance isolated to a single recording session.
class RecordingSessionContext {
  final String sessionId;
  final AppMode mode;
  final PathwaysUnit unit;
  final DateTime createdAt;
  final String exportPath;
  final String shadowDraftPath;

  final List<InsightNote> notes = [];
  final List<String> segmentSummaries = [];
  final List<String> rawAudioPaths = [];
  final List<String> stitchedAudioPaths = [];
  Uint8List lastAudioTail = Uint8List(0);
  String? lastTranscript;
  final List<String> segmentTranscriptBuffer = [];
  int segmentSummaryCounter = 0;
  bool isGeneratingSegmentSummary = false;

  final Set<Future<void>> _pipelineTasks = {};
  bool _pipelinesSealed = false;

  final http.Client sessionHttpClient;
  OpenAIService? sttService;
  OpenAIService? translationService;
  OpenAIService? fallbackTranslationService;
  AIOrchestratorService? orchestrator;

  StreamSubscription? _fastSub;
  StreamSubscription? _accurateSub;

  String? finalReviewContent;
  String? shorthandReviewContent;
  String? identifiedLectureContext;
  bool isCompleted = false;
  bool isDisposed = false;
  void Function()? onChanged;

  RecordingSessionContext({
    required this.sessionId,
    required this.mode,
    required this.unit,
    required this.exportPath,
    required this.shadowDraftPath,
    DateTime? createdAt,
    http.Client? sessionHttpClient,
    this.orchestrator,
  }) : createdAt = createdAt ?? DateTime.now(),
       sessionHttpClient = sessionHttpClient ?? http.Client();

  /// Helper factory to generate a fresh RecordingSessionContext with fixed export and shadow paths.
  factory RecordingSessionContext.create({
    required AppMode mode,
    required PathwaysUnit unit,
    required String baseDirectory,
    String? customSessionId,
    http.Client? httpClient,
  }) {
    final now = DateTime.now();
    final timeStr = DateFormat('yyyyMMdd_HHmmss_SSS').format(now);

    final sanitizedCustom = customSessionId?.trim().replaceAll(
      RegExp(r'[<>:"/\\|?*\x00-\x1F]'),
      '_',
    );
    final sid = sanitizedCustom == null || sanitizedCustom.isEmpty
        ? '${timeStr}_${now.microsecondsSinceEpoch % 1000000}'
        : sanitizedCustom.substring(0, sanitizedCustom.length.clamp(0, 80));

    final prefix = mode == AppMode.discussion
        ? 'Jeff_Discussion'
        : mode == AppMode.exam
        ? 'Jeff_Exam'
        : mode == AppMode.freeTalk
        ? 'Jeff_FreeTalk'
        : 'Jeff_Notes';

    final exportFileName = '${prefix}_$sid.md';
    final shadowFileName = 'shadow_draft_$sid.json';

    return RecordingSessionContext(
      sessionId: sid,
      mode: mode,
      unit: unit,
      exportPath: '$baseDirectory/$exportFileName',
      shadowDraftPath: '$baseDirectory/$shadowFileName',
      createdAt: now,
      sessionHttpClient: httpClient ?? http.Client(),
    );
  }

  /// [Phase 3 Fix 3 & 5] Bind orchestrator streams directly to this session context.
  /// Note updates and Shadow Draft auto-saves happen on the context, surviving handover.
  void bindOrchestrator(AIOrchestratorService service) {
    orchestrator = service;
    _fastSub?.cancel();
    _accurateSub?.cancel();

    _fastSub = service.fastEnglishStream.listen((result) {
      if (isDisposed) return;
      final index = notes.indexWhere((n) => n.id == result.noteId);
      if (index != -1) {
        notes[index].transcript = result.content;
        _saveShadowDraft();
        onChanged?.call();
      }
    });

    _accurateSub = service.accurateChineseStream.listen((result) {
      if (isDisposed) return;
      final index = notes.indexWhere((n) => n.id == result.noteId);
      if (index != -1) {
        notes[index].translatedContent = result.content;
        _saveShadowDraft();
        onChanged?.call();
      }
    });
  }

  void addNote(InsightNote note) {
    notes.add(note);
    _saveShadowDraft();
    onChanged?.call();
  }

  void addRawAudioPath(String path) {
    rawAudioPaths.add(path);
  }

  void addStitchedAudioPath(String path) {
    stitchedAudioPaths.add(path);
  }

  void runPipeline(Future<void> Function() operation) {
    if (_pipelinesSealed || isDisposed) return;
    final completer = Completer<void>();
    final tracked = completer.future;
    _pipelineTasks.add(tracked);
    Future<void>.sync(operation).then(
      completer.complete,
      onError: (Object error, StackTrace stackTrace) {
        completer.completeError(error, stackTrace);
      },
    );
    unawaited(
      tracked
          .whenComplete(() => _pipelineTasks.remove(tracked))
          .catchError((Object _) {}),
    );
  }

  void sealPipelines() {
    _pipelinesSealed = true;
  }

  Future<void> drainPipelines({
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final stopwatch = Stopwatch()..start();
    while (_pipelineTasks.isNotEmpty) {
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Session $sessionId pipeline drain timed out');
      }
      await Future.wait(
        List<Future<void>>.from(_pipelineTasks),
        eagerError: false,
      ).timeout(remaining);
    }
  }

  Future<bool> saveShadowDraft() {
    if (isDisposed) return Future<bool>.value(false);
    return ShadowDraftService.instance.saveDraft(this);
  }

  void _saveShadowDraft() {
    if (isDisposed) return;
    unawaited(saveShadowDraft());
  }

  void dispose() {
    isDisposed = true;
    _fastSub?.cancel();
    _accurateSub?.cancel();
    orchestrator?.dispose();
    try {
      sessionHttpClient.close();
    } catch (_) {}
  }
}
