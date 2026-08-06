import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/api_scheduler.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/models/session_ready_event.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/shadow_draft_service.dart';
import 'package:jeff_notes/services/session_background_processor.dart';

class _RetryingSummaryService extends OpenAIService {
  _RetryingSummaryService()
    : super(
        apiKey: 'test',
        baseUrl: 'https://example.invalid',
        defaultModel: 'test',
      );

  int callCount = 0;

  @override
  Future<String> summarize(
    String text, {
    PromptStrategy strategy = PromptStrategy.general,
    AIProvider provider = AIProvider.groq,
    AppMode mode = AppMode.lecture,
    PathwaysUnit unit = PathwaysUnit.none,
  }) async {
    callCount++;
    if (mode == AppMode.exam) return 'Exam review generated';
    if (callCount == 2) throw Exception('Summarize error 429');
    return '【30秒理解·可播放】\n'
        '这是一份成功重试后生成的紧凑速记。\n'
        '━━━━━━━━━━━━\n'
        '【Purpose（目的）】\n'
        'retry（重试）→ success（成功）\n'
        '━━━━━━━━━━━━\n'
        '【Main Points（要点）】\n'
        '── retry path（重试路径）──\n'
        'primary failure（主服务失败）→ retry success（重试成功）\n'
        '━━━━━━━━━━━━\n'
        '【Conclusion（结论）】\n'
        'failover works（故障转移有效）\n'
        '━━━━━━━━━━━━\n'
        '【二听】\n'
        '✓（已确认）no critical gaps（无关键缺口）\n'
        '━━━━━━━━━━━━\n'
        '【符号】\n'
        '→ 导致/过程/结果';
  }
}

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
    test(
      '1. [Fix 1] Queued tasks (> maxConcurrentRequests) are tracked by sessionId and waited by drain()',
      () async {
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
      },
    );

    test(
      '2. [Fix 9] sealSession() prevents new tasks from being enqueued under sealed session',
      () async {
        final scheduler = ApiScheduler();
        const sid = 'sealed_session_test';

        scheduler.sealSession(sid);

        expect(
          () => scheduler.enqueue<void>(() async {}, sessionId: sid),
          throwsA(isA<StateError>()),
        );

        scheduler.cancelSession(sid);
      },
    );

    test(
      '3. [Fix 2] Closing dedicated sessionHttpClient disposes client safely and closes context',
      () async {
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
      },
    );

    test(
      '4. [Fix 4] Audio slice processing bound to session context does not contaminate other sessions',
      () async {
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
      },
    );

    test(
      '5. [Fix 5 & 6] Shadow Draft is kept intact if Markdown export fails',
      () async {
        final context = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
          customSessionId: 'export_fail_test',
        );

        context.addNote(
          InsightNote(
            summary: 'Test Note',
            transcript: 'Speech for recovery',
            timestamp: DateTime.now(),
          ),
        );

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
      },
    );

    test(
      '6. [Fix 6] Shadow Draft is deleted ONLY when Markdown export is verified successful',
      () async {
        final context = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
          customSessionId: 'export_success_test',
        );

        context.addNote(
          InsightNote(
            summary: 'Successful Note',
            transcript: 'Speech to be saved',
            timestamp: DateTime.now(),
          ),
        );

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
      },
    );

    test(
      '7. Exam handover exports answer card and shorthand documents',
      () async {
        final context = RecordingSessionContext.create(
          mode: AppMode.exam,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
          customSessionId: 'exam_double_export_test',
        );
        context.addNote(
          InsightNote(
            summary: 'Exam note',
            transcript: 'The lecture explains an important concept.',
            translatedContent: '这节课解释了一个重要概念。',
            timestamp: DateTime.now(),
          ),
        );

        var doneTriggered = false;
        await SessionBackgroundProcessor.instance.submit(
          HandoverPayload(
            context: context,
            enableFinalRecap: false,
            onDone: (_) => doneTriggered = true,
            onStatus: (_) {},
          ),
        );

        expect(doneTriggered, isTrue);
        expect(File(context.exportPath).existsSync(), isTrue);
        final shorthand = File(
          '${tempDir.path}/Jeff_速记_exam_double_export_test.md',
        );
        expect(shorthand.existsSync(), isTrue);
        final shorthandText = await shorthand.readAsString();
        expect(shorthandText, startsWith('【30秒理解·可播放】'));
        expect(shorthandText, contains('【中文全文】'));
        expect(shorthandText, contains('这节课解释了一个重要概念。'));
        expect(shorthandText, contains('【英文全文】'));
        expect(shorthandText, contains('━━━━━━━━━━━━'));
        expect(shorthandText, isNot(contains('Academic Shorthand')));
        expect(shorthandText, isNot(contains('Part 1')));
        expect(shorthandText, isNot(contains('**Point')));
        expect(shorthandText, isNot(contains('\n\n')));
      },
    );

    test('8. Shorthand retries primary service after a 429 failure', () async {
      final context = RecordingSessionContext.create(
        mode: AppMode.exam,
        unit: PathwaysUnit.unit8,
        baseDirectory: tempDir.path,
        customSessionId: 'shorthand_retry_test',
      );
      context.addNote(
        InsightNote(
          summary: 'Plant medicine',
          transcript: 'Plant chemicals can be reproduced in a laboratory.',
          translatedContent: '植物化学物质可以在实验室中重新合成。',
          timestamp: DateTime.now(),
        ),
      );
      final service = _RetryingSummaryService();
      context.translationService = service;
      addTearDown(service.dispose);

      await SessionBackgroundProcessor.instance.submit(
        HandoverPayload(
          context: context,
          enableFinalRecap: true,
          onDone: (_) {},
          onStatus: (_) {},
        ),
      );

      final shorthand = File('${tempDir.path}/Jeff_速记_shorthand_retry_test.md');
      final content = await shorthand.readAsString();
      expect(service.callCount, 3);
      expect(content, contains('成功重试后生成的紧凑速记'));
      expect(content, isNot(contains('AI速记整理未完成')));
      expect(content, isNot(contains('\n\n')));
    });

    test(
      '9. FreeTalk saves available transcript and keeps recovery draft when finalization fails',
      () async {
        final context = RecordingSessionContext.create(
          mode: AppMode.freeTalk,
          unit: PathwaysUnit.none,
          baseDirectory: tempDir.path,
          customSessionId: 'freetalk_partial_export_test',
        );
        context.addNote(
          InsightNote(
            summary: '',
            transcript: 'The available transcript must still be saved.',
            translatedContent: '现有转写仍然必须保存。',
            timestamp: DateTime.now(),
          ),
        );
        expect(await context.saveShadowDraft(), isTrue);
        context.runPipeline(() async {
          throw StateError('simulated finalization failure');
        });
        context.sealPipelines();

        SessionReadyEvent? readyEvent;
        String? warning;
        await SessionBackgroundProcessor.instance.submit(
          HandoverPayload(
            context: context,
            enableFinalRecap: false,
            onDone: (event) => readyEvent = event,
            onStatus: (_) {},
            onError: (message) => warning = message,
          ),
        );

        final markdown = File(context.exportPath);
        expect(readyEvent, isNotNull);
        expect(await markdown.exists(), isTrue);
        expect(
          await markdown.readAsString(),
          contains('The available transcript must still be saved.'),
        );
        expect(await File(context.shadowDraftPath).exists(), isTrue);
        expect(warning, contains('recovery draft'));
      },
    );
  });
}
