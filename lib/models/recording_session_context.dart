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

  /// Audio slices are registered here before any STT work starts. The value
  /// becomes the placeholder note id once one is created. Keeping this map in
  /// the shadow draft lets a relaunched app resume exactly the unfinished
  /// slices without duplicating completed transcript rows.
  final Map<String, String?> pendingAudioNotes = {};

  /// Stable capture ordering for unfinished audio.  STT may complete out of
  /// order, but transcript context must advance only through contiguous audio
  /// slices.
  final Map<String, int> pendingAudioSequences = {};
  int _nextAudioSequence = 0;
  int _lastCompletedAudioSequence = 0;
  final Map<int, String> _completedTranscriptBySequence = {};
  final Map<String, String> pendingTranslations = {};

  /// Number of automatic full-sentence repair attempts per note. Kept after
  /// success so a restart cannot give the same note another automatic retry.
  final Map<String, int> translationRepairAttempts = {};
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
    service.restorePendingTranslations(
      pendingTranslations.entries.map(
        (entry) => PendingTranslation(entry.key, entry.value),
      ),
    );
    service.restoreTranslationRepairAttempts(translationRepairAttempts.keys);
    // These callbacks update durable session state without requiring the
    // orchestrator to know about shadow draft storage.
    service.onTranslationsDeferred = deferTranslations;
    // Clear durable pending state only when the accurate stream has actually
    // delivered the translated content below; this keeps draft state atomic.
    service.onTranslationsCompleted = null;
    service.onTranslationRepairRequested = claimTranslationRepair;
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
        // The first result remains visible immediately, but a claimed repair
        // stays recoverable until its one background request settles.
        if (result.isRepair ||
            !translationRepairAttempts.containsKey(result.noteId)) {
          pendingTranslations.remove(result.noteId);
        } else {
          pendingTranslations[result.noteId] = notes[index].transcript;
        }
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

  /// Inserts a capture placeholder at its original audio position even when a
  /// later slice completed stitching first.  Summary notes are never created
  /// by this path.
  void addAudioNote(String path, InsightNote note) {
    final sequence = pendingAudioSequences[path];
    if (sequence == null) {
      addNote(note);
      return;
    }
    var insertionIndex = notes.length;
    for (final entry in pendingAudioNotes.entries) {
      final existingId = entry.value;
      final existingSequence = pendingAudioSequences[entry.key];
      if (existingId == null || existingSequence == null) continue;
      if (existingSequence > sequence) {
        final index = notes.indexWhere((item) => item.id == existingId);
        if (index >= 0) {
          insertionIndex = index;
          break;
        }
      }
    }
    notes.insert(insertionIndex, note);
    _saveShadowDraft();
    onChanged?.call();
  }

  void addRawAudioPath(String path) {
    if (!rawAudioPaths.contains(path)) rawAudioPaths.add(path);
  }

  void addStitchedAudioPath(String path) {
    if (!stitchedAudioPaths.contains(path)) stitchedAudioPaths.add(path);
  }

  void registerPendingAudio(String path) {
    pendingAudioNotes.putIfAbsent(path, () {
      _nextAudioSequence++;
      pendingAudioSequences[path] = _nextAudioSequence;
      return null;
    });
    _saveShadowDraft();
  }

  void bindPendingAudioToNote(String path, String noteId) {
    pendingAudioNotes[path] = noteId;
    _saveShadowDraft();
  }

  void completePendingAudio(String path) {
    pendingAudioNotes.remove(path);
    pendingAudioSequences.remove(path);
    _saveShadowDraft();
  }

  /// Advances [lastTranscript] only in capture order. A later STT result may
  /// finish first, but cannot become context until every earlier slice has
  /// completed. This prevents both regression and future-context leakage.
  void completeTranscriptForAudio(String path, String transcript) {
    final sequence = pendingAudioSequences[path];
    if (sequence == null) return;
    _completedTranscriptBySequence[sequence] = transcript;
    while (_completedTranscriptBySequence.containsKey(
      _lastCompletedAudioSequence + 1,
    )) {
      _lastCompletedAudioSequence++;
      lastTranscript = _completedTranscriptBySequence.remove(
        _lastCompletedAudioSequence,
      );
    }
  }

  /// Restores the ordering of unfinished slices without trusting paths from a
  /// previous app container. Legacy drafts use their JSON insertion order.
  void restorePendingAudioSequence(String path, int? sequence) {
    final safeSequence = sequence != null && sequence > 0
        ? sequence
        : _nextAudioSequence + 1;
    pendingAudioSequences[path] = safeSequence;
    if (safeSequence > _nextAudioSequence) _nextAudioSequence = safeSequence;
  }

  void deferTranslations(Iterable<PendingTranslation> items) {
    for (final item in items) {
      pendingTranslations[item.noteId] = item.text;
    }
    _saveShadowDraft();
  }

  void completeTranslations(Iterable<String> noteIds) {
    for (final id in noteIds) {
      pendingTranslations.remove(id);
    }
    _saveShadowDraft();
  }

  bool claimTranslationRepair(String noteId) {
    if ((translationRepairAttempts[noteId] ?? 0) >= 1) return false;
    translationRepairAttempts[noteId] = 1;
    final index = notes.indexWhere((item) => item.id == noteId);
    if (index >= 0) pendingTranslations[noteId] = notes[index].transcript;
    _saveShadowDraft();
    return true;
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
