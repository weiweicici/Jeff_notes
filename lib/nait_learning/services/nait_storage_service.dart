import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/nait_course.dart';
import '../models/nait_week.dart';
import '../models/nait_class_session.dart';
import '../models/nait_review_progress.dart';

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
      return NaitWeek.fromJson(jsonDecode(str) as Map<String, dynamic>);
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
            weeks.add(NaitWeek.fromJson(jsonDecode(str) as Map<String, dynamic>));
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
      return NaitClassSession.fromJson(jsonDecode(str) as Map<String, dynamic>);
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
            sessions.add(NaitClassSession.fromJson(jsonDecode(str) as Map<String, dynamic>));
          } catch (_) {}
        }
      }
    }
    sessions.sort((a, b) => a.classDate.compareTo(b.classDate));
    return sessions;
  }

  Future<void> deleteSession(String courseId, int weekNumber, String sessionId) async {
    final dir = await getSessionDir(courseId, weekNumber, sessionId);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
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
