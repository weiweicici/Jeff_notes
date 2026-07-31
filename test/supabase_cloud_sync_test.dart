import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/services/cloud_sync_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('supabase_cloud_sync_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 5 Supabase & CloudSyncService Unit Tests', () {
    test('1. FakeCloudSyncService records synced session details correctly', () async {
      final cloudService = FakeCloudSyncService();
      final context = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'cloud_sync_session_001',
      );

      final file = File('${tempDir.path}/test_notes.md');
      await file.writeAsString('# Test Markdown Content\n\n- Key point 1');

      final success = await cloudService.syncArchiveSession(
        context: context,
        file: file,
      );

      expect(success, isTrue);
      expect(cloudService.syncedRecords.length, 1);
      final record = cloudService.syncedRecords.first;

      expect(record['session_id'], 'cloud_sync_session_001');
      expect(record['user_id'], 'fake_user_123');
      expect(record['module'], 'lecture');
      expect(record['title'], 'test_notes.md');
      expect(record['file_hash'], isNotEmpty);

      context.dispose();
    });

    test('2. FakeCloudSyncService fails gracefully when shouldFail is true (Fail-Closed)', () async {
      final cloudService = FakeCloudSyncService(shouldFail: true);
      final context = RecordingSessionContext.create(
        mode: AppMode.exam,
        unit: PathwaysUnit.unit2,
        baseDirectory: tempDir.path,
        customSessionId: 'cloud_sync_session_002',
      );

      final file = File('${tempDir.path}/exam_notes.md');
      await file.writeAsString('# Exam Markdown Content');

      final success = await cloudService.syncArchiveSession(
        context: context,
        file: file,
      );

      expect(success, isFalse);
      expect(cloudService.syncedRecords.isEmpty, isTrue);

      context.dispose();
    });

    test('3. Non-existent file sync returns false (fail-closed guard)', () async {
      final cloudService = FakeCloudSyncService();
      final context = RecordingSessionContext.create(
        mode: AppMode.freeTalk,
        unit: PathwaysUnit.none,
        baseDirectory: tempDir.path,
        customSessionId: 'cloud_sync_session_003',
      );

      final nonExistentFile = File('${tempDir.path}/does_not_exist.md');

      final success = await cloudService.syncArchiveSession(
        context: context,
        file: nonExistentFile,
      );

      expect(success, isFalse);
      context.dispose();
    });
  });
}
