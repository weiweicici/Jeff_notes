import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_course.dart';
import 'package:jeff_notes/nait_learning/models/nait_week.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_analysis.dart';
import 'package:jeff_notes/nait_learning/models/nait_english_chunk.dart';
import 'package:jeff_notes/nait_learning/models/nait_audio_clip.dart';
import 'package:jeff_notes/nait_learning/services/nait_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late NaitStorageService storage;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nait_storage_test_');
    storage = NaitStorageService();
    storage.setBaseDir(tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('1. Create and save course', () async {
    final course = NaitCourse(
      id: 'SYSA1010',
      courseCode: 'SYSA1010',
      displayName: 'System Administration',
    );
    await storage.saveCourse(course);

    final loaded = await storage.loadCourse('SYSA1010');
    expect(loaded, isNotNull);
    expect(loaded!.courseCode, 'SYSA1010');
    expect(loaded.displayName, 'System Administration');

    final courseIds = await storage.getCourseIds();
    expect(courseIds, contains('SYSA1010'));
  });

  test('2. Create and save week', () async {
    final week = NaitWeek(
      courseId: 'SYSA1010',
      weekNumber: 1,
    );
    await storage.saveWeek(week);

    final loaded = await storage.loadWeek('SYSA1010', 1);
    expect(loaded, isNotNull);
    expect(loaded!.courseId, 'SYSA1010');
    expect(loaded.weekNumber, 1);
  });

  test('3. Create and save class session with analysis', () async {
    final session = NaitClassSession(
      id: '20260902',
      courseId: 'SYSA1010',
      weekNumber: 1,
      classDate: DateTime(2026, 9, 2),
      status: NaitSessionStatus.processed,
      analysis: NaitClassAnalysis(
        mustDo: ['Complete Lab 1 by Friday'],
        lab: ['Step 1: Set adapter to NAT'],
        classroomEnglish: [
          NaitEnglishChunk(
            id: 'chunk_1',
            phrase: 'leave it at the default',
            chineseMeaning: '保持默认',
          ),
        ],
      ),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await storage.saveSession(session);

    final loaded = await storage.loadSession('SYSA1010', 1, '20260902');
    expect(loaded, isNotNull);
    expect(loaded!.id, '20260902');
    expect(loaded.status, NaitSessionStatus.processed);
    expect(loaded.analysis?.mustDo.first, 'Complete Lab 1 by Friday');
    expect(loaded.analysis?.classroomEnglish.first.phrase, 'leave it at the default');
  });

  test('4. Reload after simulated restart preserves data', () async {
    final course = NaitCourse(id: 'NETW1111', courseCode: 'NETW1111', displayName: 'Networking');
    await storage.saveCourse(course);

    // Simulate restart with a brand new storage instance pointing to same dir
    final freshStorage = NaitStorageService();
    freshStorage.setBaseDir(tempDir);

    final allCourses = await freshStorage.loadAllCourses();
    expect(allCourses.length, 1);
    expect(allCourses.first.id, 'NETW1111');
  });

  test('5. Delete only target class, preserves other sessions and weeks', () async {
    final s1 = NaitClassSession(
      id: 's1',
      courseId: 'SYSA1010',
      weekNumber: 1,
      classDate: DateTime(2026, 9, 2),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    final s2 = NaitClassSession(
      id: 's2',
      courseId: 'SYSA1010',
      weekNumber: 1,
      classDate: DateTime(2026, 9, 4),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await storage.saveSession(s1);
    await storage.saveSession(s2);

    expect((await storage.loadSessionsForWeek('SYSA1010', 1)).length, 2);

    // Delete s1 only
    await storage.deleteSession('SYSA1010', 1, 's1');

    final remaining = await storage.loadSessionsForWeek('SYSA1010', 1);
    expect(remaining.length, 1);
    expect(remaining.first.id, 's2');
  });

  test('6. No NAIT file appears in regular Documents root (.md files)', () async {
    // Normal History scan searches `Documents/*.md` (e.g. `2026-09-02_14-30-00.md`)
    // Verify NAIT storage creates everything inside dedicated subfolder
    final course = NaitCourse(id: 'SYSA1010', courseCode: 'SYSA1010', displayName: 'Admin');
    await storage.saveCourse(course);

    final entities = tempDir.listSync();
    // In root, only index.json and course subfolders exist; no regular note markdown files
    for (final e in entities) {
      if (e is File) {
        expect(e.path.endsWith('.md'), isFalse, reason: 'NAIT must never create top-level .md files');
      }
    }
  });

  test('7. Cleanup preserves study audio and rebases stale iOS paths', () async {
    final session = NaitClassSession(
      id: 'cleanup', courseId: 'SYSA1010', weekNumber: 1,
      classDate: DateTime(2026, 9, 6), status: NaitSessionStatus.processed,
      analysis: NaitClassAnalysis(mustDo: ['Keep this analysis']),
      createdAt: DateTime.now(), updatedAt: DateTime.now(),
    );
    await storage.saveSession(session);
    final dir = await storage.getSessionDir('SYSA1010', 1, 'cleanup');
    final original = File('${dir.path}/original_audio.mp4')..writeAsBytesSync(List.filled(100, 1));
    final normalized = File('${dir.path}/normalized.wav')..writeAsBytesSync(List.filled(200, 1));
    final temporary = File('${dir.path}/processing.tmp')..writeAsBytesSync(List.filled(50, 1));
    final transcript = File('${dir.path}/transcript.json')..writeAsStringSync('{}');
    final chunks = Directory('${dir.path}/chunks')..createSync();
    final manifest = File('${chunks.path}/chunk_manifest.json')..writeAsStringSync('{}');
    final clipDir = Directory('${dir.path}/clips')..createSync();
    final clip = File('${clipDir.path}/clip_001.wav')..writeAsBytesSync(List.filled(80, 1));
    final weekDir = await storage.getWeekDir('SYSA1010', 1);
    final weekPack = File('${weekDir.path}/listening_pack.wav')..writeAsBytesSync(List.filled(90, 1));
    await storage.saveWeek(NaitWeek(
      courseId: 'SYSA1010', weekNumber: 1,
      packAudioPath: '/old/ios/container/Documents/nait/SYSA1010/week_01/listening_pack.wav',
    ));
    session.clips = [NaitAudioClip(
      id: 'clip_001', classSessionId: session.id, courseId: session.courseId,
      weekNumber: session.weekNumber, label: 'Keep clip', phrase: 'Keep clip',
      start: Duration.zero, end: const Duration(seconds: 1),
      filePath: '/old/ios/container/Documents/nait/SYSA1010/week_01/class_cleanup/clips/clip_001.wav',
      durationMs: 1000,
    )];
    await storage.saveSession(session);

    final listed = await storage.loadSessionsForWeek('SYSA1010', 1);
    expect(listed.single.clips.single.filePath, clip.path);
    final preview = await storage.previewProcessedClassCleanup(
      courseId: 'SYSA1010', weekNumber: 1, sessionId: 'cleanup');
    expect(preview.files, containsAll([original.path, normalized.path, temporary.path]));
    expect(preview.bytes, 350);
    final result = await storage.cleanupProcessedClass(
      courseId: 'SYSA1010', weekNumber: 1, sessionId: 'cleanup');
    expect(result.bytes, 350);
    expect(await original.exists(), isFalse);
    expect(await normalized.exists(), isFalse);
    expect(await temporary.exists(), isFalse);
    expect(await transcript.exists(), isTrue);
    expect(await manifest.exists(), isTrue);
    expect(await clip.exists(), isTrue);
    expect(await weekPack.exists(), isTrue);
    final loaded = await storage.loadSession('SYSA1010', 1, 'cleanup');
    expect(loaded!.sourceAudioCleanedUp, isTrue);
    expect(loaded.originalAudioPath, isNull);
    expect(loaded.normalizedAudioPath, isNull);
    expect(await File(loaded.clips.single.filePath).exists(), isTrue);
    final loadedWeek = await storage.loadWeek('SYSA1010', 1);
    expect(loadedWeek!.packAudioPath, weekPack.path);
    expect(await File(loadedWeek.packAudioPath!).exists(), isTrue);
  });

  test('8. Cleanup refuses unprocessed classes', () async {
    final session = NaitClassSession(
      id: 'not_ready', courseId: 'SYSA1010', weekNumber: 1,
      classDate: DateTime(2026, 9, 7), createdAt: DateTime.now(), updatedAt: DateTime.now());
    await storage.saveSession(session);
    expect(
      () => storage.cleanupProcessedClass(courseId: 'SYSA1010', weekNumber: 1, sessionId: 'not_ready'),
      throwsStateError,
    );
  });
}
