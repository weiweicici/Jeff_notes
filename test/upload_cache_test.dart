import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/upload_cache.dart';
import 'package:jeff_notes/services/file_sync_agent.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('same hash uses one in-process upload and marks it once', () async {
    var calls = 0;
    final gate = Completer<void>();

    Future<bool> upload() async {
      calls++;
      await gate.future;
      return true;
    }

    final first = UploadCache.runSingleFlight(
      'same',
      userId: 'userA',
      operation: upload,
    );
    final second = UploadCache.runSingleFlight(
      'same',
      userId: 'userA',
      operation: upload,
    );
    gate.complete();

    expect(await Future.wait([first, second]), [true, true]);
    expect(calls, 1);
    expect(await UploadCache.exists('same', userId: 'userA'), isTrue);
  });

  test(
    'different hashes retain both marks under concurrent completion',
    () async {
      final first = UploadCache.runSingleFlight(
        'one',
        userId: 'userA',
        operation: () async => true,
      );
      final second = UploadCache.runSingleFlight(
        'two',
        userId: 'userA',
        operation: () async => true,
      );

      expect(await Future.wait([first, second]), [true, true]);
      expect(
        await UploadCache.load(userId: 'userA'),
        containsAll(<String>['one', 'two']),
      );
    },
  );

  test('failed upload is not marked and can be retried', () async {
    var calls = 0;
    final failed = await UploadCache.runSingleFlight(
      'retry',
      userId: 'userA',
      operation: () async {
        calls++;
        return false;
      },
    );
    final succeeded = await UploadCache.runSingleFlight(
      'retry',
      userId: 'userA',
      operation: () async {
        calls++;
        return true;
      },
    );

    expect(failed, isFalse);
    expect(succeeded, isTrue);
    expect(calls, 2);
    expect(await UploadCache.exists('retry', userId: 'userA'), isTrue);
  });

  test('legacy unscoped mark never suppresses a different user', () async {
    await UploadCache.mark('shared-hash');
    var userACalls = 0;
    var userBCalls = 0;

    final userA = await UploadCache.runSingleFlight(
      'shared-hash',
      userId: 'userA',
      operation: () async {
        userACalls++;
        return true;
      },
    );
    final userB = await UploadCache.runSingleFlight(
      'shared-hash',
      userId: 'userB',
      operation: () async {
        userBCalls++;
        return true;
      },
    );
    final userARepeat = await UploadCache.runSingleFlight(
      'shared-hash',
      userId: 'userA',
      operation: () async {
        userACalls++;
        return true;
      },
    );

    expect(userA, isTrue);
    expect(userB, isTrue);
    expect(userARepeat, isTrue);
    expect(userACalls, 1);
    expect(userBCalls, 1);
  });

  test(
    'revisions of one session serialize while different sessions can run independently',
    () async {
      final firstGate = Completer<void>();
      var active = 0;
      var maxActive = 0;
      final first = UploadCache.runSingleFlight(
        'revision-one',
        userId: 'userA',
        sessionId: 'sessionA',
        operation: () async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          await firstGate.future;
          active--;
          return true;
        },
      );
      final second = UploadCache.runSingleFlight(
        'revision-two',
        userId: 'userA',
        sessionId: 'sessionA',
        operation: () async {
          active++;
          maxActive = active > maxActive ? active : maxActive;
          active--;
          return true;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(maxActive, 1);
      firstGate.complete();
      await Future.wait([first, second]);
      expect(maxActive, 1);

      final otherGate = Completer<void>();
      final independent = UploadCache.runSingleFlight(
        'other-session',
        userId: 'userA',
        sessionId: 'sessionB',
        operation: () async {
          await otherGate.future;
          return true;
        },
      );
      otherGate.complete();
      await independent;
    },
  );

  test(
    'background export keeps one archive id when Markdown content changes',
    () {
      expect(
        FileSyncAgent.sessionIdForFileName(
          '/Documents/Jeff_FreeTalk_20260827_130412_468_468744.md',
        ),
        '20260827_130412_468_468744',
      );
      expect(
        FileSyncAgent.sessionIdForFileName(
          '/Documents/Jeff_速记_20260827_130412_468_468744.md',
        ),
        isNull,
      );
    },
  );
}
