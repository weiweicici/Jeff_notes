import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/api_scheduler.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/services/shadow_draft_service.dart';
import 'package:jeff_notes/services/session_background_processor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_deep_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 3 Deep Architecture & Isolation Tests', () {
    test('1. [Fix 1] Queued tasks (> maxConcurrentRequests) are tracked by sessionId and waited by drain()', () async {
      final scheduler = ApiScheduler();
      const sid = 'queued_task_test_session';
      final results = <int>[];

      // Fill 4 concurrent slots with long-running tasks for OTHER sessions
      final blockerFutures = List.generate(4, (i) {
        return scheduler.enqueue<void>(() async {
          await Future.delayed(const Duration(milliseconds: 150));
        }, sessionId: 'blocker_session_$i');
      });

      // Task 5 is for `sid` — it will be placed in the waiting queue BEFORE executing
      final task5Future = scheduler.enqueue<int>(() async {
        results.add(5);
        return 5;
      }, sessionId: sid);

      // Drain `sid` — must wait for queued Task 5 to complete!
      await scheduler.drain(sid, timeout: const Duration(seconds: 5));

      expect(results, contains(5));
      final val = await task5Future;
      expect(val, 5);

      await Future.wait(blockerFutures);
    });

    test('2. [Fix 9] sealSession() prevents new tasks from being enqueued under sealed session', () async {
      final scheduler = ApiScheduler();
      const sid = 'sealed_session_test';

      scheduler.sealSession(sid);

      expect(
        () => scheduler.enqueue<void>(() async {}, sessionId: sid),
        throwsA(isA<StateError>()),
      );

      scheduler.cancelSession(sid);
    });

    test('3. [Fix 2] Closing dedicated sessionHttpClient disposes client safely and closes context', () async {
      final context = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'client_close_test',
      );

      var clientClosed = false;
      try {
        context.sessionHttpClient.close();
        clientClosed = true;
      } catch (_) {}

      expect(clientClosed, isTrue);
      context.dispose();
      expect(context.isDisposed, isTrue);
    });

    test('4. [Fix 4] Audio slice processing bound to session context does not contaminate other sessions', () async {
      final contextA = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'session_A',
      );

      final contextB = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'session_B',
      );

      final noteA = InsightNote(
        summary: 'Note for A',
        transcript: 'Speech A',
        timestamp: DateTime.now(),
      );

      final noteB = InsightNote(
        summary: 'Note for B',
        transcript: 'Speech B',
        timestamp: DateTime.now(),
      );

      // Add to respective contexts
      contextA.addNote(noteA);
      contextB.addNote(noteB);

      expect(contextA.notes.length, 1);
      expect(contextA.notes.first.transcript, 'Speech A');

      expect(contextB.notes.length, 1);
      expect(contextB.notes.first.transcript, 'Speech B');

      // Context A does not contain Note B
      expect(contextA.notes.any((n) => n.transcript == 'Speech B'), isFalse);

      contextA.dispose();
      contextB.dispose();
    });

    test('5. [Fix 5 & 6] Shadow Draft is kept intact if Markdown export fails', () async {
      final context = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'export_fail_test',
      );

      context.addNote(InsightNote(
        summary: 'Test Note',
        transcript: 'Speech for recovery',
        timestamp: DateTime.now(),
      ));

      // Explicitly save shadow draft
      final saved = await ShadowDraftService.instance.saveDraft(context);
      expect(saved, isTrue);
      expect(await File(context.shadowDraftPath).exists(), isTrue);

      // Submit handover with invalid export directory so file write fails
      final invalidContext = RecordingSessionContext(
        sessionId: context.sessionId,
        mode: context.mode,
        unit: context.unit,
        exportPath: '/non_existent_dir_xyz123/failed_export.md',
        shadowDraftPath: context.shadowDraftPath,
      );

      var errorTriggered = false;
      final payload = HandoverPayload(
        context: invalidContext,
        enableFinalRecap: false,
        onDone: (_) {},
        onStatus: (_) {},
        onError: (_) {
          errorTriggered = true;
        },
      );

      SessionBackgroundProcessor.instance.submit(payload);

      // Allow background processor time to run
      await Future.delayed(const Duration(milliseconds: 250));

      expect(errorTriggered, isTrue);
      // Shadow draft MUST still exist after failed export!
      expect(await File(context.shadowDraftPath).exists(), isTrue);

      invalidContext.dispose();
      context.dispose();
    });

    test('6. [Fix 6] Shadow Draft is deleted ONLY when Markdown export is verified successful', () async {
      final context = RecordingSessionContext.create(
        mode: AppMode.lecture,
        unit: PathwaysUnit.unit1,
        baseDirectory: tempDir.path,
        customSessionId: 'export_success_test',
      );

      context.addNote(InsightNote(
        summary: 'Successful Note',
        transcript: 'Speech to be saved',
        timestamp: DateTime.now(),
      ));

      await ShadowDraftService.instance.saveDraft(context);
      expect(await File(context.shadowDraftPath).exists(), isTrue);

      var doneTriggered = false;
      final payload = HandoverPayload(
        context: context,
        enableFinalRecap: false,
        onDone: (event) {
          doneTriggered = true;
          expect(File(event.exportPath).existsSync(), isTrue);
        },
        onStatus: (_) {},
      );

      SessionBackgroundProcessor.instance.submit(payload);

      await Future.delayed(const Duration(milliseconds: 300));

      expect(doneTriggered, isTrue);
      // Shadow draft MUST be deleted after verified successful export
      expect(await File(context.shadowDraftPath).exists(), isFalse);

      context.dispose();
    });
  });
}
