import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/nait_course.dart';
import '../models/nait_week.dart';
import '../models/nait_class_session.dart';
import '../models/nait_audio_clip.dart';
import '../models/nait_review_progress.dart';

class NaitClassStorageCleanup {
  final List<String> files;
  final int bytes;

  const NaitClassStorageCleanup({required this.files, required this.bytes});

  bool get hasFiles => files.isNotEmpty;
}

class NaitStorageService {
  Directory? _baseDir;

  Future<Directory> getBaseDir() async {
    if (_baseDir != null) return _baseDir!;
    final docsDir = await getApplicationDocumentsDirectory();
    final naitDir = Directory(p.join(docsDir.path, 'nait'));
    if (!await naitDir.exists()) {
      await naitDir.create(recursive: true);
    }
    _baseDir = naitDir;
    return _baseDir!;
  }

  /// Sets an explicit base directory (useful for unit testing with TempDirectory).
  void setBaseDir(Directory dir) {
    _baseDir = dir;
  }

  // ---------------------------------------------------------------------------
  // Atomic file write helper
  // ---------------------------------------------------------------------------
  Future<void> _atomicWrite(File file, String content) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final tempFile = File('${file.path}.tmp_${DateTime.now().microsecondsSinceEpoch}');
    await tempFile.writeAsString(content, flush: true);
    if (await file.exists()) {
      await file.delete();
    }
    await tempFile.rename(file.path);
  }

  // ---------------------------------------------------------------------------
  // Index & Course operations
  // ---------------------------------------------------------------------------
  Future<File> _getIndexFile() async {
    final base = await getBaseDir();
    return File(p.join(base.path, 'index.json'));
  }

  Future<List<String>> getCourseIds() async {
    final indexFile = await _getIndexFile();
    if (!await indexFile.exists()) return [];
    try {
      final str = await indexFile.readAsString();
      final data = jsonDecode(str) as Map<String, dynamic>;
      final list = (data['courses'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      return list;
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveCourseIds(List<String> courseIds) async {
    final indexFile = await _getIndexFile();
    final data = {'courses': courseIds, 'updatedAt': DateTime.now().toIso8601String()};
    await _atomicWrite(indexFile, const JsonEncoder.withIndent('  ').convert(data));
  }

  Future<Directory> getCourseDir(String courseId) async {
    final base = await getBaseDir();
    final dir = Directory(p.join(base.path, courseId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveCourse(NaitCourse course) async {
    final dir = await getCourseDir(course.id);
    final file = File(p.join(dir.path, 'course.json'));
    await _atomicWrite(file, const JsonEncoder.withIndent('  ').convert(course.toJson()));

    final courseIds = await getCourseIds();
    if (!courseIds.contains(course.id)) {
      courseIds.add(course.id);
      await _saveCourseIds(courseIds);
    }
  }

  Future<NaitCourse?> loadCourse(String courseId) async {
    final dir = await getCourseDir(courseId);
    final file = File(p.join(dir.path, 'course.json'));
    if (!await file.exists()) return null;
    try {
      final str = await file.readAsString();
      return NaitCourse.fromJson(jsonDecode(str) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<List<NaitCourse>> loadAllCourses() async {
    final ids = await getCourseIds();
    final List<NaitCourse> courses = [];
    for (final id in ids) {
      final c = await loadCourse(id);
      if (c != null) courses.add(c);
    }
    return courses;
  }

  Future<void> deleteCourse(String courseId) async {
    final dir = await getCourseDir(courseId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final courseIds = await getCourseIds();
    courseIds.remove(courseId);
    await _saveCourseIds(courseIds);
  }

  // ---------------------------------------------------------------------------
  // Week operations
  // ---------------------------------------------------------------------------
  String _weekDirName(int weekNumber) => 'week_${weekNumber.toString().padLeft(2, '0')}';

  Future<Directory> getWeekDir(String courseId, int weekNumber) async {
    final cDir = await getCourseDir(courseId);
    final dir = Directory(p.join(cDir.path, _weekDirName(weekNumber)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveWeek(NaitWeek week) async {
    final dir = await getWeekDir(week.courseId, week.weekNumber);
    final file = File(p.join(dir.path, 'week.json'));
    await _atomicWrite(file, const JsonEncoder.withIndent('  ').convert(week.toJson()));
  }

  Future<NaitWeek?> loadWeek(String courseId, int weekNumber) async {
    final dir = await getWeekDir(courseId, weekNumber);
    final file = File(p.join(dir.path, 'week.json'));
    if (!await file.exists()) {
      return NaitWeek(courseId: courseId, weekNumber: weekNumber);
    }
    try {
      final str = await file.readAsString();
      final week = NaitWeek.fromJson(jsonDecode(str) as Map<String, dynamic>);
      await _rebaseWeekAudioPath(week, dir);
      return week;
    } catch (_) {
      return NaitWeek(courseId: courseId, weekNumber: weekNumber);
    }
  }

  Future<List<NaitWeek>> loadWeeksForCourse(String courseId) async {
    final cDir = await getCourseDir(courseId);
    if (!await cDir.exists()) return [];
    final List<NaitWeek> weeks = [];
    final entities = await cDir.list().toList();
    for (final e in entities) {
      if (e is Directory && p.basename(e.path).startsWith('week_')) {
        final wFile = File(p.join(e.path, 'week.json'));
        if (await wFile.exists()) {
          try {
            final str = await wFile.readAsString();
            final week = NaitWeek.fromJson(jsonDecode(str) as Map<String, dynamic>);
            await _rebaseWeekAudioPath(week, e);
            weeks.add(week);
          } catch (_) {}
        } else {
          final parts = p.basename(e.path).split('_');
          final num = int.tryParse(parts.last) ?? 1;
          weeks.add(NaitWeek(courseId: courseId, weekNumber: num));
        }
      }
    }
    weeks.sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
    return weeks;
  }

  Future<void> deleteWeek(String courseId, int weekNumber) async {
    final dir = await getWeekDir(courseId, weekNumber);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Session operations
  // ---------------------------------------------------------------------------
  String _sessionDirName(String sessionId) => 'class_$sessionId';

  Future<Directory> getSessionDir(String courseId, int weekNumber, String sessionId) async {
    final wDir = await getWeekDir(courseId, weekNumber);
    final dir = Directory(p.join(wDir.path, _sessionDirName(sessionId)));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<void> saveSession(NaitClassSession session) async {
    final dir = await getSessionDir(session.courseId, session.weekNumber, session.id);
    final file = File(p.join(dir.path, 'session.json'));
    await _atomicWrite(file, const JsonEncoder.withIndent('  ').convert(session.toJson()));
  }

  Future<NaitClassSession?> loadSession(String courseId, int weekNumber, String sessionId) async {
    final dir = await getSessionDir(courseId, weekNumber, sessionId);
    final file = File(p.join(dir.path, 'session.json'));
    if (!await file.exists()) return null;
    try {
      final str = await file.readAsString();
      final session = NaitClassSession.fromJson(jsonDecode(str) as Map<String, dynamic>);
      await _rebaseSessionPaths(session, dir);
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<List<NaitClassSession>> loadSessionsForWeek(String courseId, int weekNumber) async {
    final wDir = await getWeekDir(courseId, weekNumber);
    if (!await wDir.exists()) return [];
    final List<NaitClassSession> sessions = [];
    final entities = await wDir.list().toList();
    for (final e in entities) {
      if (e is Directory && p.basename(e.path).startsWith('class_')) {
        final sFile = File(p.join(e.path, 'session.json'));
        if (await sFile.exists()) {
          try {
            final str = await sFile.readAsString();
            final session = NaitClassSession.fromJson(jsonDecode(str) as Map<String, dynamic>);
            await _rebaseSessionPaths(session, e);
            sessions.add(session);
          } catch (_) {}
        }
      }
    }
    sessions.sort((a, b) => a.classDate.compareTo(b.classDate));
    return sessions;
  }

  Future<String?> _rebaseExistingFile(
    String? storedPath,
    Directory parent, {
    String? subdirectory,
  }) async {
    if (storedPath == null || storedPath.isEmpty) return storedPath;
    if (await File(storedPath).exists()) return storedPath;
    final pathParts = <String>[parent.path];
    if (subdirectory != null) pathParts.add(subdirectory);
    pathParts.add(p.basename(storedPath));
    final candidate = File(p.joinAll(pathParts));
    return await candidate.exists() ? candidate.path : storedPath;
  }

  Future<void> _rebaseWeekAudioPath(NaitWeek week, Directory weekDir) async {
    week.packAudioPath = await _rebaseExistingFile(week.packAudioPath, weekDir);
  }

  /// Sideloaded iOS updates can preserve Documents while assigning the app a
  /// new data-container UUID. Rebase stale absolute paths to canonical local
  /// files without changing the stored study data.
  Future<void> _rebaseSessionPaths(
    NaitClassSession session,
    Directory sessionDir,
  ) async {
    session.originalAudioPath = await _rebaseExistingFile(session.originalAudioPath, sessionDir);
    session.normalizedAudioPath = await _rebaseExistingFile(session.normalizedAudioPath, sessionDir);
    session.transcriptPath = await _rebaseExistingFile(session.transcriptPath, sessionDir);
    session.clips = [
      for (final clip in session.clips)
        NaitAudioClip.fromJson({
          ...clip.toJson(),
          'filePath': await _rebaseExistingFile(
            clip.filePath,
            sessionDir,
            subdirectory: 'clips',
          ),
        }),
    ];
  }

  Future<void> deleteSession(String courseId, int weekNumber, String sessionId) async {
    final dir = await getSessionDir(courseId, weekNumber, sessionId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Returns only source/intermediate files eligible for explicit cleanup.
  /// Study outputs (chunks, clips, transcripts, analysis, and the week-level
  /// listening pack) are never candidates.
  Future<NaitClassStorageCleanup> previewProcessedClassCleanup({
    required String courseId,
    required int weekNumber,
    required String sessionId,
  }) async {
    final session = await loadSession(courseId, weekNumber, sessionId);
    if (session == null || !session.isProcessed) {
      throw StateError('Only successfully processed classes can be cleaned up');
    }
    final dir = await getSessionDir(courseId, weekNumber, sessionId);
    final files = <String>[];
    var bytes = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      // Never treat permanent study-audio locations as cleanup targets,
      // even if a future writer happens to use a temporary-looking name.
      final relative = p.relative(entity.path, from: dir.path);
      final firstComponent = relative.split(p.separator).first;
      if (firstComponent == 'clips' || name == 'listening_pack.wav') continue;
      final isSource = name == 'normalized.wav' || name.startsWith('original_audio.');
      final isTemp = name.endsWith('.tmp') || name.contains('.tmp_');
      if (!isSource && !isTemp) continue;
      files.add(entity.path);
      bytes += await entity.length();
    }
    files.sort();
    return NaitClassStorageCleanup(files: files, bytes: bytes);
  }

  /// Deletes source/intermediate files and records that source audio is gone.
  Future<NaitClassStorageCleanup> cleanupProcessedClass({
    required String courseId,
    required int weekNumber,
    required String sessionId,
  }) async {
    final session = await loadSession(courseId, weekNumber, sessionId);
    if (session == null || !session.isProcessed) {
      throw StateError('Only successfully processed classes can be cleaned up');
    }
    final cleanup = await previewProcessedClassCleanup(
      courseId: courseId, weekNumber: weekNumber, sessionId: sessionId,
    );
    for (final path in cleanup.files) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    session.originalAudioPath = null;
    session.normalizedAudioPath = null;
    session.sourceAudioCleanedUp = true;
    session.updatedAt = DateTime.now();
    await saveSession(session);
    return cleanup;
  }

  // ---------------------------------------------------------------------------
  // Review progress operations
  // ---------------------------------------------------------------------------
  Future<File> _getProgressFile(String courseId) async {
    final dir = await getCourseDir(courseId);
    return File(p.join(dir.path, 'progress.json'));
  }

  Future<NaitReviewProgress> loadReviewProgress(String courseId) async {
    final file = await _getProgressFile(courseId);
    if (!await file.exists()) {
      return NaitReviewProgress(courseId: courseId);
    }
    try {
      final str = await file.readAsString();
      return NaitReviewProgress.fromJson(jsonDecode(str) as Map<String, dynamic>);
    } catch (_) {
      return NaitReviewProgress(courseId: courseId);
    }
  }

  Future<void> saveReviewProgress(NaitReviewProgress progress) async {
    final file = await _getProgressFile(progress.courseId);
    await _atomicWrite(file, const JsonEncoder.withIndent('  ').convert(progress.toJson()));
  }
}
