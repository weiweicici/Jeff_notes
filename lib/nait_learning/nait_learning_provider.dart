import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'models/nait_course.dart';
import 'models/nait_week.dart';
import 'models/nait_class_session.dart';
import 'models/nait_english_chunk.dart';
import 'models/nait_review_progress.dart';
import 'services/nait_storage_service.dart';
import 'services/nait_audio_import_service.dart';
import 'services/nait_processing_service.dart';
import 'services/nait_audio_playback_service.dart';
import 'services/nait_week_consolidation_service.dart';
import 'services/nait_english_bank_service.dart';

class NaitLearningProvider extends ChangeNotifier {
  final NaitStorageService _storageService;
  final NaitProcessingService _processingService;
  final NaitAudioPlaybackService _playbackService;
  final NaitWeekConsolidationService _consolidationService;
  final NaitEnglishBankService _bankService;
  final Uuid _uuid = const Uuid();

  NaitLearningProvider({
    NaitStorageService? storageService,
    NaitProcessingService? processingService,
    NaitAudioPlaybackService? playbackService,
    NaitWeekConsolidationService? consolidationService,
    NaitEnglishBankService? bankService,
  })  : _storageService = storageService ?? NaitStorageService(),
        _processingService = processingService ?? NaitProcessingService(),
        _playbackService = playbackService ?? NaitAudioPlaybackService(),
        _consolidationService = consolidationService ?? NaitWeekConsolidationService(),
        _bankService = bankService ?? NaitEnglishBankService();

  // State
  List<NaitCourse> _courses = [];
  List<NaitCourse> get courses => _courses;

  NaitCourse? _selectedCourse;
  NaitCourse? get selectedCourse => _selectedCourse;

  List<NaitWeek> _weeks = [];
  List<NaitWeek> get weeks => _weeks;

  int? _selectedWeekNumber;
  int? get selectedWeekNumber => _selectedWeekNumber;

  List<NaitClassSession> _sessions = [];
  List<NaitClassSession> get sessions => _sessions;

  NaitClassSession? _selectedSession;
  NaitClassSession? get selectedSession => _selectedSession;

  NaitReviewProgress? _reviewProgress;
  NaitReviewProgress? get reviewProgress => _reviewProgress;

  List<NaitBankItem> _bankItems = [];
  List<NaitBankItem> get bankItems => _bankItems;

  bool _isProcessing = false;
  bool get isProcessing => _isProcessing;

  String _processingMessage = '';
  String get processingMessage => _processingMessage;

  String? _currentlyPlayingPath;
  String? get currentlyPlayingPath => _currentlyPlayingPath;

  NaitAudioPlaybackService get playbackService => _playbackService;

  // ---------------------------------------------------------------------------
  // Initialization
  // ---------------------------------------------------------------------------
  Future<void> init() async {
    await loadCourses();
  }

  Future<void> loadCourses() async {
    _courses = await _storageService.loadAllCourses();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Course Management
  // ---------------------------------------------------------------------------
  Future<NaitCourse> createCourse({
    required String courseCode,
    required String displayName,
  }) async {
    final cleanCode = courseCode.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final course = NaitCourse(
      id: cleanCode,
      courseCode: cleanCode,
      displayName: displayName.trim(),
    );
    await _storageService.saveCourse(course);
    await loadCourses();
    return course;
  }

  Future<void> updateCourse({
    required String courseId,
    required String courseCode,
    required String displayName,
  }) async {
    final course = await _storageService.loadCourse(courseId);
    if (course != null) {
      course.courseCode = courseCode.toUpperCase().trim();
      course.displayName = displayName.trim();
      course.updatedAt = DateTime.now();
      await _storageService.saveCourse(course);
      await loadCourses();
      if (_selectedCourse?.id == courseId) {
        _selectedCourse = course;
      }
    }
  }

  Future<void> deleteCourse(String courseId) async {
    await _storageService.deleteCourse(courseId);
    if (_selectedCourse?.id == courseId) {
      _selectedCourse = null;
      _weeks = [];
      _sessions = [];
    }
    await loadCourses();
  }

  Future<void> selectCourse(String courseId) async {
    _selectedCourse = await _storageService.loadCourse(courseId);
    _selectedWeekNumber = null;
    _selectedSession = null;
    if (_selectedCourse != null) {
      await loadWeeksForSelectedCourse();
      _reviewProgress = await _storageService.loadReviewProgress(courseId);
    }
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Week Management
  // ---------------------------------------------------------------------------
  Future<void> loadWeeksForSelectedCourse() async {
    if (_selectedCourse == null) return;
    _weeks = await _storageService.loadWeeksForCourse(_selectedCourse!.id);
    notifyListeners();
  }

  Future<NaitWeek> createWeek({
    required String courseId,
    required int weekNumber,
  }) async {
    final week = NaitWeek(courseId: courseId, weekNumber: weekNumber);
    await _storageService.saveWeek(week);
    await loadWeeksForSelectedCourse();
    return week;
  }

  Future<void> deleteWeek(String courseId, int weekNumber) async {
    await _storageService.deleteWeek(courseId, weekNumber);
    if (_selectedWeekNumber == weekNumber) {
      _selectedWeekNumber = null;
      _sessions = [];
    }
    await loadWeeksForSelectedCourse();
  }

  Future<void> selectWeek(int weekNumber) async {
    _selectedWeekNumber = weekNumber;
    _selectedSession = null;
    await loadSessionsForSelectedWeek();
  }

  // ---------------------------------------------------------------------------
  // Session Management & Processing
  // ---------------------------------------------------------------------------
  Future<void> loadSessionsForSelectedWeek() async {
    if (_selectedCourse == null || _selectedWeekNumber == null) return;
    _sessions = await _storageService.loadSessionsForWeek(
      _selectedCourse!.id,
      _selectedWeekNumber!,
    );
    notifyListeners();
  }

  Future<void> selectSession(String sessionId) async {
    if (_selectedCourse == null || _selectedWeekNumber == null) return;
    _selectedSession = await _storageService.loadSession(
      _selectedCourse!.id,
      _selectedWeekNumber!,
      sessionId,
    );
    notifyListeners();
  }

  /// Imports files and immediately starts processing the session.
  Future<NaitClassSession> importAndProcessClass({
    required String courseId,
    required int weekNumber,
    required DateTime classDate,
    required File audioSource,
    required File transcriptSource,
  }) async {
    _isProcessing = true;
    _processingMessage = 'Importing files...';
    notifyListeners();

    try {
      final sessionId = '${classDate.year}${classDate.month.toString().padLeft(2, '0')}${classDate.day.toString().padLeft(2, '0')}_${_uuid.v4().substring(0, 4)}';
      final sessionDir = await _storageService.getSessionDir(courseId, weekNumber, sessionId);

      // 1. Preserve original audio (never modified)
      _processingMessage = 'Saving original audio...';
      notifyListeners();
      final origAudio = await NaitAudioImportService.preserveOriginalAudio(
        sourceAudio: audioSource,
        sessionDir: sessionDir,
      );

      // 2. Import transcript
      _processingMessage = 'Reading transcript...';
      notifyListeners();
      final transcriptResult = await NaitAudioImportService.importTranscript(
        sourceTranscript: transcriptSource,
        sessionDir: sessionDir,
      );

      // 3. Normalize audio to standard mono 16kHz 16-bit PCM WAV
      _processingMessage = 'Normalizing audio format...';
      notifyListeners();
      final normWavFile = File('${sessionDir.path}/normalized.wav');
      await NaitAudioImportService.normalizeAudio(
        inputFile: origAudio,
        outputWavFile: normWavFile,
      );

      // 4. Create initial session record
      var session = NaitClassSession(
        id: sessionId,
        courseId: courseId,
        weekNumber: weekNumber,
        classDate: classDate,
        originalAudioPath: origAudio.path,
        normalizedAudioPath: normWavFile.path,
        transcriptPath: transcriptResult.file.path,
        status: NaitSessionStatus.readyToProcess,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await _storageService.saveSession(session);

      // 5. Run AI Analysis and audio clipping
      session = await _processingService.processClassSession(
        session: session,
        onProgress: (msg) {
          _processingMessage = msg;
          notifyListeners();
        },
      );

      _selectedSession = session;
      await loadSessionsForSelectedWeek();
      return session;
    } finally {
      _isProcessing = false;
      _processingMessage = '';
      notifyListeners();
    }
  }

  /// Retries processing an already imported session without re-importing audio.
  Future<void> retryProcessing(String sessionId) async {
    if (_selectedCourse == null || _selectedWeekNumber == null) return;
    final session = await _storageService.loadSession(
      _selectedCourse!.id,
      _selectedWeekNumber!,
      sessionId,
    );
    if (session == null) return;

    _isProcessing = true;
    _processingMessage = 'Retrying analysis...';
    notifyListeners();

    try {
      final updated = await _processingService.processClassSession(
        session: session,
        onProgress: (msg) {
          _processingMessage = msg;
          notifyListeners();
        },
      );
      _selectedSession = updated;
      await loadSessionsForSelectedWeek();
    } finally {
      _isProcessing = false;
      _processingMessage = '';
      notifyListeners();
    }
  }

  Future<void> deleteSession(String sessionId) async {
    if (_selectedCourse == null || _selectedWeekNumber == null) return;
    await _storageService.deleteSession(_selectedCourse!.id, _selectedWeekNumber!, sessionId);
    if (_selectedSession?.id == sessionId) {
      _selectedSession = null;
    }
    await loadSessionsForSelectedWeek();
  }

  // ---------------------------------------------------------------------------
  // Week Consolidation & Listening Pack
  // ---------------------------------------------------------------------------
  Future<ConsolidatedEnglishResult?> consolidateWeek(int weekNumber) async {
    if (_selectedCourse == null) return null;
    final result = await _consolidationService.consolidateWeek(
      courseId: _selectedCourse!.id,
      weekNumber: weekNumber,
    );
    await loadWeeksForSelectedCourse();
    return result;
  }

  // ---------------------------------------------------------------------------
  // English Bank
  // ---------------------------------------------------------------------------
  Future<void> loadEnglishBank({String? courseId}) async {
    _bankItems = await _bankService.getEnglishBank(courseId: courseId);
    notifyListeners();
  }

  Future<void> toggleChunkLearned(String courseId, String chunkId) async {
    await _bankService.toggleLearned(courseId: courseId, chunkId: chunkId);
    if (_selectedCourse != null) {
      _reviewProgress = await _storageService.loadReviewProgress(_selectedCourse!.id);
    }
    await loadEnglishBank(courseId: _selectedCourse?.id);
  }

  Future<void> toggleChunkStarred(String courseId, String chunkId) async {
    await _bankService.toggleStarred(courseId: courseId, chunkId: chunkId);
    if (_selectedCourse != null) {
      _reviewProgress = await _storageService.loadReviewProgress(_selectedCourse!.id);
    }
    await loadEnglishBank(courseId: _selectedCourse?.id);
  }

  // ---------------------------------------------------------------------------
  // Playback Controls
  // ---------------------------------------------------------------------------
  Future<void> playAudio(String filePath) async {
    _currentlyPlayingPath = filePath;
    notifyListeners();
    try {
      await _playbackService.playWav(filePath);
    } catch (e) {
      _currentlyPlayingPath = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> stopAudio() async {
    _currentlyPlayingPath = null;
    await _playbackService.stop();
    notifyListeners();
  }
}
