import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/diagnostic_log_service.dart';
import 'package:jeff_notes/services/file_sync_agent.dart';
import 'package:jeff_notes/services/upload_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('jeff_sync_test_');
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test(
    'unauthenticated scan leaves file pending, later restored user uploads once',
    () async {
      final file = File(
        '${directory.path}/Jeff_FreeTalk_20260827_130412_468_468744.md',
      );
      await file.writeAsString('first draft');
      var uploads = 0;

      final blocked = FileSyncAgent.forTesting(
        authenticatedUser: () async => null,
        archiveUpload: (payload) async {
          uploads++;
          return payload;
        },
        documentsDirectory: () async => directory,
      );
      await blocked.syncNow();
      expect(uploads, 0);

      final restored = FileSyncAgent.forTesting(
        authenticatedUser: () async => 'original-user',
        archiveUpload: (payload) async {
          uploads++;
          return payload;
        },
        documentsDirectory: () async => directory,
      );
      await restored.syncNow();
      expect(uploads, 1);
      expect(
        await UploadCache.exists('ignored', userId: 'original-user'),
        isFalse,
      );
    },
  );

  test(
    '401-like upload failure remains pending and retries successfully once',
    () async {
      final file = File(
        '${directory.path}/Jeff_FreeTalk_20260827_130412_468_468744.md',
      );
      await file.writeAsString('retry me');
      var calls = 0;
      final agent = FileSyncAgent.forTesting(
        authenticatedUser: () async => 'original-user',
        archiveUpload: (payload) async {
          calls++;
          if (calls == 1) throw StateError('401');
          return payload;
        },
        documentsDirectory: () async => directory,
      );

      await agent.syncNow();
      expect(calls, 1);
      await agent.syncNow();
      expect(calls, 2);
      await agent.syncNow();
      expect(calls, 2);
    },
  );

  test(
    'identity change immediately before upsert rejects the old payload',
    () async {
      final file = File(
        '${directory.path}/Jeff_FreeTalk_20260827_130412_468_468744.md',
      );
      await file.writeAsString('identity guard');
      var authCalls = 0;
      var uploads = 0;
      final agent = FileSyncAgent.forTesting(
        authenticatedUser: () async {
          authCalls++;
          return authCalls == 1 ? 'user-A' : 'user-B';
        },
        archiveUpload: (payload) async {
          uploads++;
          return payload;
        },
        documentsDirectory: () async => directory,
      );

      await agent.syncNow();
      expect(uploads, 0);
      expect(await UploadCache.load(userId: 'user-A'), isEmpty);
    },
  );

  test('updating same recording Markdown keeps its session id', () async {
    final file = File(
      '${directory.path}/Jeff_FreeTalk_20260827_130412_468_468744.md',
    );
    await file.writeAsString('version one');
    final payloads = <Map<String, dynamic>>[];
    final agent = FileSyncAgent.forTesting(
      authenticatedUser: () async => 'original-user',
      archiveUpload: (payload) async {
        payloads.add(payload);
        return payload;
      },
      documentsDirectory: () async => directory,
    );
    await agent.syncNow();
    await file.writeAsString('version two');
    await agent.syncNow();
    expect(payloads, hasLength(2));
    expect(payloads[0]['session_id'], payloads[1]['session_id']);
    expect(payloads[0]['file_hash'], isNot(payloads[1]['file_hash']));
  });

  test('mismatched remote receipt stays pending and is retried', () async {
    final file = File(
      '${directory.path}/Jeff_FreeTalk_20260827_130412_468_468744.md',
    );
    await file.writeAsString('receipt check');
    var calls = 0;
    final agent = FileSyncAgent.forTesting(
      authenticatedUser: () async => 'original-user',
      archiveUpload: (payload) async {
        calls++;
        return calls == 1
            ? <String, dynamic>{'user_id': 'other-user'}
            : payload;
      },
      documentsDirectory: () async => directory,
    );
    await agent.syncNow();
    await agent.syncNow();
    expect(calls, 2);
  });

  test(
    'remote confirmation is logged once per verified write, not cache hit',
    () async {
      final file = File('${directory.path}/Jeff_Notes_receipt.md');
      await file.writeAsString(
        'only a matching server receipt confirms upload',
      );
      await DiagnosticLogService.instance.initialize(
        file: File('${directory.path}/diagnostic.log'),
      );
      var uploads = 0;
      final agent = FileSyncAgent.forTesting(
        authenticatedUser: () async => 'confirmed-user',
        archiveUpload: (payload) async {
          uploads++;
          return payload;
        },
        documentsDirectory: () async => directory,
      );
      await agent.syncNow();
      await agent.syncNow();
      final log = await DiagnosticLogService.instance.readForSharing();
      expect(uploads, 1);
      expect(RegExp(r'\| remote_confirmed \|').allMatches(log), hasLength(1));
    },
  );
}
