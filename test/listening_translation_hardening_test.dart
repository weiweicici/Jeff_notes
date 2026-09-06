import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/api_scheduler.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/local_translation_service.dart';
import 'package:jeff_notes/services/shadow_draft_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _SlowTranslator implements LocalTextTranslator {
  final gates = <Completer<String>>[];
  var active = 0;
  var peakActive = 0;

  @override
  Future<String> translateEnglishToChinese(String text) async {
    active++;
    if (active > peakActive) peakActive = active;
    final gate = Completer<String>();
    gates.add(gate);
    try {
      return await gate.future;
    } finally {
      active--;
    }
  }
}

class _RepairTranslator implements LocalTextTranslator {
  var calls = 0;

  @override
  Future<String> translateEnglishToChinese(String text) async {
    calls++;
    return calls == 1 ? text : '已补译：$text';
  }
}

class _FailingRepairTranslator implements LocalTextTranslator {
  var calls = 0;

  @override
  Future<String> translateEnglishToChinese(String text) async {
    calls++;
    if (calls == 1) return text;
    throw StateError('repair unavailable');
  }
}

class _AbortAwareClient extends http.BaseClient {
  var aborted = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortable = request as http.Abortable;
    await abortable.abortTrigger;
    aborted = true;
    throw http.RequestAbortedException(request.url);
  }
}

class _DelayedGeminiClient extends http.BaseClient {
  var calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls++;
    await Future<void>.delayed(const Duration(seconds: 12));
    final body = utf8.encode(
      jsonEncode({
        'candidates': [
          {
            'content': {
              'parts': [
                {'text': '已翻译。'},
              ],
            },
          },
        ],
      }),
    );
    return http.StreamedResponse(Stream<List<int>>.value(body), 200);
  }
}

OpenAIService _unusedService(http.Client client) => OpenAIService(
  apiKey: 'test',
  baseUrl: 'https://unused.example',
  defaultModel: 'test',
  rateLimitService: ApiRateLimitService.forTesting(
    prefsLoader: () async => throw StateError('test preferences'),
    clock: () => DateTime.utc(2026, 9, 5),
  ),
  httpClient: client,
);

void main() {
  test('conservative full-sentence detector preserves technical literals', () {
    expect(
      needsTranslationRepair(
        'This complete English sentence was returned without translation.',
        'This complete English sentence was returned without translation.',
      ),
      isTrue,
    );
    expect(needsTranslationRepair('git status', 'git status'), isFalse);
    expect(needsTranslationRepair('192.168.1.1', '192.168.1.1'), isFalse);
    expect(
      needsTranslationRepair(
        'This complete English sentence was returned without translation.',
        '这句已经翻译。',
      ),
      isFalse,
    );
  });

  test('one repair claim persists and old drafts remain valid', () async {
    final directory = await Directory.systemTemp.createTemp('repair_state_');
    addTearDown(() => directory.delete(recursive: true));
    final context = RecordingSessionContext.create(
      mode: AppMode.lecture,
      unit: PathwaysUnit.none,
      baseDirectory: directory.path,
      customSessionId: 'repair-state',
    );
    context.addNote(
      InsightNote(
        id: 'note-1',
        summary: '',
        transcript:
            'This complete English sentence was returned without translation.',
        timestamp: DateTime.now(),
      ),
    );
    expect(context.claimTranslationRepair('note-1'), isTrue);
    expect(context.claimTranslationRepair('note-1'), isFalse);
    await context.saveShadowDraft();
    await ShadowDraftService.instance.waitForPendingWrites(
      context.shadowDraftPath,
    );
    final restored = await ShadowDraftService.instance.readDraft(
      context.shadowDraftPath,
    );
    expect(restored!.translationRepairAttempts['note-1'], 1);
    expect(
      restored.pendingTranslations['note-1'],
      contains('complete English'),
    );
  });

  test('scheduler counts a real task until it settles', () async {
    const sessionId = 'real-inflight-count';
    final scheduler = ApiScheduler();
    final release = Completer<void>();
    final task = scheduler.enqueue<void>(
      () => release.future,
      sessionId: sessionId,
      lane: ApiTaskLane.translation,
    );
    await Future<void>.delayed(Duration.zero);
    expect(scheduler.activeRequestCountForSession(sessionId), 1);
    expect(scheduler.activeRequestCount, greaterThanOrEqualTo(1));
    var drained = false;
    unawaited(scheduler.drain(sessionId).then((_) => drained = true));
    await Future<void>.delayed(Duration.zero);
    expect(drained, isFalse);
    release.complete();
    await task;
    await scheduler.drain(sessionId);
    expect(scheduler.activeRequestCountForSession(sessionId), 0);
    scheduler.cancelSession(sessionId);
  });

  test(
    'translation timeout aborts its transport without closing a client',
    () async {
      final client = _AbortAwareClient();
      final service = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://abort.example',
        defaultModel: 'test',
        translationTimeout: Duration.zero,
        rateLimitService: ApiRateLimitService.forTesting(
          prefsLoader: () async => throw StateError('test preferences'),
          clock: () => DateTime.utc(2026, 9, 5),
        ),
        httpClient: client,
      );
      await expectLater(
        service.translate('A complete English sentence.'),
        throwsA(isA<Exception>()),
      );
      expect(client.aborted, isTrue);
      // The injected client remains owned by its context, not by this service.
      service.dispose();
    },
  );

  test('slow virtual lecture drains a bounded per-note queue', () async {
    const sessionId = 'slow-lecture-throughput';
    final client = MockClient((_) async => http.Response('unused', 500));
    final slow = _SlowTranslator();
    final orchestrator = AIOrchestratorService(
      sttService: _unusedService(client),
      translationService: _unusedService(client),
      localTranslator: slow,
      sessionId: sessionId,
      httpClient: client,
    );
    addTearDown(() {
      orchestrator.dispose();
      ApiScheduler().cancelSession(sessionId);
    });
    final received = <String>[];
    final subscription = orchestrator.accurateChineseStream.listen(
      (result) => received.add(result.noteId),
    );
    addTearDown(subscription.cancel);
    orchestrator.restorePendingTranslations([
      for (var index = 0; index < 8; index++)
        PendingTranslation(
          'note-$index',
          'Slice $index is a complete lecture sentence.',
        ),
    ]);
    await orchestrator.retryPendingTranslations();
    await Future<void>.delayed(Duration.zero);
    expect(slow.peakActive, 2);
    expect(orchestrator.translationQueuePeak, 8);

    var released = 0;
    while (released < 8) {
      await Future<void>.delayed(Duration.zero);
      while (released < slow.gates.length) {
        slow.gates[released].complete('第 $released 段。');
        released++;
      }
    }
    await orchestrator.drain(timeout: const Duration(seconds: 2));
    expect(received, [for (var index = 0; index < 8; index++) 'note-$index']);
    expect(orchestrator.activeTranslationWorkers, 0);
    expect(orchestrator.pendingTranslations, isEmpty);
  });

  test('three-hour virtual input bounds production orchestrator backlog', () {
    fakeAsync((async) {
      const sessionId = 'three-hour-production-throughput';
      final client = _DelayedGeminiClient();
      final limiter = ApiRateLimitService.forTesting(
        prefsLoader: () async => throw StateError('test preferences'),
        clock: () => DateTime.utc(2026, 9, 5),
      );
      final orchestrator = AIOrchestratorService(
        sttService: OpenAIService(
          apiKey: 'test',
          baseUrl: 'https://unused.example',
          defaultModel: 'test',
          rateLimitService: limiter,
          httpClient: client,
        ),
        translationService: OpenAIService(
          apiKey: 'test',
          baseUrl: 'https://unused.example',
          defaultModel: 'test',
          rateLimitService: limiter,
          httpClient: client,
        ),
        sessionId: sessionId,
        geminiApiKey: 'test',
        rateLimitService: limiter,
        httpClient: client,
      );
      for (var slice = 0; slice < 2160; slice++) {
        orchestrator.enqueueTranslationForTesting(
          'note-$slice',
          'Slice $slice is a complete lecture sentence.',
        );
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
      }
      // 12s/provider with two workers is below the 5s input rate. The
      // required behavior is bounded live memory and durable deferral, not a
      // false claim of real-time Chinese stability.
      expect(orchestrator.translationQueuePeak, 22);
      expect(orchestrator.activeTranslationWorkers, 2);
      expect(
        orchestrator.translationQueuePeak +
            orchestrator.activeTranslationWorkers,
        AIOrchestratorService.maxInMemoryTranslationBacklog,
      );
      // The global scheduler is intentionally shared with the other lanes,
      // so admission count is bounded rather than exact under parallel tests.
      expect(client.calls, inInclusiveRange(1700, 1900));
      expect(orchestrator.pendingTranslations.length, inInclusiveRange(300, 400));
      orchestrator.dispose();
      ApiScheduler().cancelSession(sessionId);
    });
  });

  test(
    'obvious untranslated prose gets one nonblocking durable repair',
    () async {
      const sessionId = 'one-repair';
      final directory = await Directory.systemTemp.createTemp('one_repair_');
      addTearDown(() => directory.delete(recursive: true));
      final client = MockClient((_) async => http.Response('unused', 500));
      final repair = _RepairTranslator();
      final orchestrator = AIOrchestratorService(
        sttService: _unusedService(client),
        translationService: _unusedService(client),
        localTranslator: repair,
        sessionId: sessionId,
        httpClient: client,
      );
      final context = RecordingSessionContext(
        sessionId: sessionId,
        mode: AppMode.lecture,
        unit: PathwaysUnit.none,
        exportPath: '${directory.path}/notes.md',
        shadowDraftPath: '${directory.path}/shadow.json',
        orchestrator: orchestrator,
      );
      context.addNote(
        InsightNote(
          id: 'note-1',
          summary: '',
          transcript:
              'This complete English sentence was returned without translation.',
          timestamp: DateTime.now(),
        ),
      );
      context.bindOrchestrator(orchestrator);
      addTearDown(() {
        context.dispose();
        ApiScheduler().cancelSession(sessionId);
      });
      orchestrator.restorePendingTranslations([
        const PendingTranslation(
          'note-1',
          'This complete English sentence was returned without translation.',
        ),
      ]);
      await orchestrator.retryPendingTranslations();
      await orchestrator.drain(timeout: const Duration(seconds: 2));
      expect(repair.calls, 2);
      expect(context.translationRepairAttempts['note-1'], 1);
      expect(context.notes.single.translatedContent, startsWith('已补译'));
      expect(context.pendingTranslations, isEmpty);
      await context.saveShadowDraft();
      await ShadowDraftService.instance.waitForPendingWrites(
        context.shadowDraftPath,
      );
    },
  );

  test(
    'failed repair is not resent across repeated recovery and restart',
    () async {
      const sessionId = 'failed-repair-once';
      const source =
          'This complete English sentence was returned without translation.';
      final directory = await Directory.systemTemp.createTemp('failed_repair_');
      addTearDown(() => directory.delete(recursive: true));
      final client = MockClient((_) async => http.Response('unused', 500));
      final firstTranslator = _FailingRepairTranslator();
      final first = AIOrchestratorService(
        sttService: _unusedService(client),
        translationService: _unusedService(client),
        localTranslator: firstTranslator,
        sessionId: sessionId,
        httpClient: client,
      );
      final context = RecordingSessionContext(
        sessionId: sessionId,
        mode: AppMode.lecture,
        unit: PathwaysUnit.none,
        exportPath: '${directory.path}/notes.md',
        shadowDraftPath: '${directory.path}/shadow.json',
        orchestrator: first,
      );
      context.addNote(
        InsightNote(
          id: 'note-1',
          summary: '',
          transcript: source,
          timestamp: DateTime.now(),
        ),
      );
      context.bindOrchestrator(first);
      first.restorePendingTranslations([
        const PendingTranslation('note-1', source),
      ]);
      await first.retryPendingTranslations();
      await expectLater(
        first.drain(timeout: const Duration(seconds: 2)),
        throwsA(isA<TranslationDeferredException>()),
      );
      expect(firstTranslator.calls, 2); // original result + exactly one repair
      expect(context.notes.single.translatedContent, source);
      expect(context.translationRepairAttempts['note-1'], 1);
      expect(context.pendingTranslations['note-1'], source);

      // Repeated finalization in the same process cannot create repair #2.
      await first.retryPendingTranslations();
      expect(firstTranslator.calls, 2);
      await context.saveShadowDraft();
      await ShadowDraftService.instance.waitForPendingWrites(
        context.shadowDraftPath,
      );
      first.dispose();

      final restored = await ShadowDraftService.instance.readDraft(
        context.shadowDraftPath,
      );
      final restartedTranslator = _FailingRepairTranslator();
      final restarted = AIOrchestratorService(
        sttService: _unusedService(client),
        translationService: _unusedService(client),
        localTranslator: restartedTranslator,
        sessionId: sessionId,
        httpClient: client,
      );
      restored!.bindOrchestrator(restarted);
      await restarted.retryPendingTranslations();
      expect(restartedTranslator.calls, 0);
      expect(restored.pendingTranslations['note-1'], source);
      expect(restored.notes.single.translatedContent, source);
      restarted.dispose();
      restored.dispose();
    },
  );
}
