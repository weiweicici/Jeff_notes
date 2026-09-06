import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/models/session_ready_event.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/shadow_draft_service.dart';
import 'package:jeff_notes/services/cloud_sync_service.dart';
import 'package:jeff_notes/services/session_background_processor.dart';
import 'package:jeff_notes/api_scheduler.dart';

ApiRateLimitService _limiter() => ApiRateLimitService.forTesting(
  prefsLoader: () async => throw StateError('no prefs'),
  clock: () => DateTime.utc(2026, 8, 30),
);

class _FakeCloudSync implements CloudSyncService {
  @override
  Future<bool> syncArchiveSession({
    required RecordingSessionContext context,
    required File file,
  }) async => true;
}

void main() {
  test(
    'Gemini is primary for Chinese translation and receives text only',
    () async {
      const sessionId = 'gemini-primary-translation';
      final directory = await Directory.systemTemp.createTemp(
        'gemini_primary_translation_',
      );
      addTearDown(() async {
        ApiScheduler().cancelSession(sessionId);
        await ShadowDraftService.instance.waitForPendingWrites(
          '${directory.path}/shadow.json',
        );
        await directory.delete(recursive: true);
      });
      final wav = File('${directory.path}/slice.wav')
        ..writeAsBytesSync(List<int>.filled(200, 1));
      var geminiCalls = 0;
      var groqTranslationCalls = 0;
      String? geminiRequestBody;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          return http.Response(
            jsonEncode({'text': 'Current lecture text.'}),
            200,
          );
        }
        if (request.url.host == 'generativelanguage.googleapis.com') {
          geminiCalls++;
          geminiRequestBody = request.body;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Translation: “当前讲座内容。”'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          groqTranslationCalls++;
          return http.Response('unexpected Groq translation', 500);
        }
        return http.Response('unexpected', 404);
      });
      final limiter = _limiter();
      final service = OpenAIService(
        apiKey: 'groq-test',
        baseUrl: 'https://groq.example',
        defaultModel: 'test',
        rateLimitService: limiter,
        httpClient: client,
      );
      final orchestrator = AIOrchestratorService(
        sttService: service,
        translationService: service,
        sessionId: sessionId,
        geminiApiKey: 'gemini-test',
        rateLimitService: limiter,
        httpClient: client,
      );
      addTearDown(orchestrator.dispose);
      final chinese = <String>[];
      final subscription = orchestrator.accurateChineseStream.listen(
        (result) => chinese.add(result.content),
      );
      addTearDown(subscription.cancel);

      await orchestrator.processAudioSegment('note-1', wav.path);
      await orchestrator.drain(timeout: const Duration(seconds: 2));

      expect(geminiCalls, 1);
      expect(groqTranslationCalls, 0);
      expect(chinese, ['当前讲座内容。']);
      expect(geminiRequestBody, contains('Current lecture text.'));
      expect(geminiRequestBody, isNot(contains('audio')));
    },
  );

  test(
    'label-only translation stays pending instead of completing as blank',
    () async {
      const sessionId = 'empty-translation-recovery';
      final directory = await Directory.systemTemp.createTemp(
        'empty_translation_recovery_',
      );
      addTearDown(() async {
        ApiScheduler().cancelSession(sessionId);
        await directory.delete(recursive: true);
      });
      final wav = File('${directory.path}/slice.wav')
        ..writeAsBytesSync(List<int>.filled(200, 1));
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          return http.Response(
            jsonEncode({'text': 'Recover this sentence.'}),
            200,
          );
        }
        if (request.url.host == 'generativelanguage.googleapis.com') {
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '```text\\nTranslation:\\n```'},
                    ],
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '翻译：'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('unexpected', 404);
      });
      final limiter = _limiter();
      final service = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://groq.example',
        defaultModel: 'test',
        rateLimitService: limiter,
        httpClient: client,
      );
      final orchestrator = AIOrchestratorService(
        sttService: service,
        translationService: service,
        sessionId: sessionId,
        geminiApiKey: 'gemini-test',
        rateLimitService: limiter,
        httpClient: client,
      );
      addTearDown(orchestrator.dispose);
      final context = RecordingSessionContext(
        sessionId: sessionId,
        mode: AppMode.lecture,
        unit: PathwaysUnit.none,
        exportPath: '${directory.path}/notes.md',
        shadowDraftPath: '${directory.path}/shadow.json',
        orchestrator: orchestrator,
      );
      context.bindOrchestrator(orchestrator);
      addTearDown(context.dispose);
      context.addNote(
        InsightNote(summary: '', transcript: '...', timestamp: DateTime.now()),
      );
      final noteId = context.notes.single.id;
      final delivered = <PipelineResult>[];
      final subscription = orchestrator.accurateChineseStream.listen(
        delivered.add,
      );
      addTearDown(subscription.cancel);

      await orchestrator.processAudioSegment(noteId, wav.path);
      await expectLater(
        orchestrator.drain(timeout: const Duration(seconds: 2)),
        throwsA(isA<TranslationDeferredException>()),
      );

      expect(delivered, isEmpty);
      expect(context.notes.single.translatedContent, isNull);
      expect(context.pendingTranslations[noteId], 'Recover this sentence.');
      expect(
        orchestrator.pendingTranslations.single.text,
        'Recover this sentence.',
      );
      // Stream callbacks persist asynchronously; finish their draft writes
      // before this test's temporary directory is removed.
      await context.saveShadowDraft();
      await ShadowDraftService.instance.waitForPendingWrites(
        context.shadowDraftPath,
      );
    },
  );

  test('legacy draft hydrates only genuinely untranslated notes', () async {
    final directory = await Directory.systemTemp.createTemp(
      'legacy_translation_',
    );
    addTearDown(() => directory.delete(recursive: true));
    final context = RecordingSessionContext.create(
      mode: AppMode.lecture,
      unit: PathwaysUnit.none,
      baseDirectory: directory.path,
      customSessionId: 'legacy',
    );
    context.notes.addAll([
      InsightNote(
        id: 'valid',
        summary: '',
        transcript: 'Real English.',
        timestamp: DateTime.now(),
      ),
      InsightNote(
        id: 'silence',
        summary: '',
        transcript: '[Silence]',
        timestamp: DateTime.now(),
      ),
      InsightNote(
        id: 'space',
        summary: '',
        transcript: 'Blank',
        translatedContent: ' ',
        timestamp: DateTime.now(),
      ),
      InsightNote(
        id: 'failed',
        summary: '',
        transcript: 'Retry sentence.',
        translatedContent: '[Translation unavailable]',
        timestamp: DateTime.now(),
      ),
    ]);
    final snapshot = <String, dynamic>{
      'schemaVersion': ShadowDraftService.currentSchemaVersion,
      'sessionId': context.sessionId,
      'mode': context.mode.index,
      'unit': context.unit.index,
      'createdAt': context.createdAt.toIso8601String(),
      'exportPath': context.exportPath,
      'notes': context.notes.map((note) => note.toJson()).toList(),
      'segmentSummaries': <String>[],
      'rawAudioPaths': <String>[],
      'stitchedAudioPaths': <String>[],
      'pendingAudioNotes': <String, String?>{},
      'finalReviewContent': null,
      'shorthandReviewContent': null,
      'identifiedLectureContext': null,
      'isCompleted': false,
    };
    await File(context.shadowDraftPath).writeAsString(jsonEncode(snapshot));
    final restored = await ShadowDraftService.instance.readDraft(
      context.shadowDraftPath,
    );
    expect(
      restored!.pendingTranslations.keys,
      containsAll(['valid', 'failed']),
    );
    expect(restored.pendingTranslations.keys, isNot(contains('silence')));
    expect(restored.pendingTranslations.keys, isNot(contains('space')));
    await restored.saveShadowDraft();
    final reread = await ShadowDraftService.instance.readDraft(
      context.shadowDraftPath,
    );
    expect(reread!.pendingTranslations.keys, containsAll(['valid', 'failed']));
  });

  test(
    'failed translation is persisted and retried after draft rehydration',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'translation_recovery_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final wav = File('${directory.path}/slice.wav')
        ..writeAsBytesSync(List<int>.filled(200, 1));
      final shadowPath = '${directory.path}/shadow.json';
      final exportPath = '${directory.path}/notes.md';
      var translationAvailable = false;

      MockClient client() => MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          return http.Response(
            jsonEncode({'text': 'A lecture sentence.'}),
            200,
          );
        }
        if (request.url.path.endsWith('/chat/completions')) {
          if (!translationAvailable)
            return http.Response('temporary failure', 401);
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '翻译结果：一条讲座句子。'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('unexpected', 404);
      });

      final firstClient = client();
      final limiter = _limiter();
      final firstService = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://groq.example',
        defaultModel: 'test',
        rateLimitService: limiter,
        httpClient: firstClient,
      );
      final firstOrchestrator = AIOrchestratorService(
        sttService: firstService,
        translationService: firstService,
        sessionId: 'translation-recovery',
        rateLimitService: limiter,
        httpClient: firstClient,
      );
      final context = RecordingSessionContext(
        sessionId: 'translation-recovery',
        mode: AppMode.lecture,
        unit: PathwaysUnit.none,
        exportPath: exportPath,
        shadowDraftPath: shadowPath,
        orchestrator: firstOrchestrator,
      );
      context.bindOrchestrator(firstOrchestrator);
      addTearDown(context.dispose);
      context.addNote(
        InsightNote(summary: '', transcript: '...', timestamp: DateTime.now()),
      );
      final noteId = context.notes.single.id;

      await firstOrchestrator.processAudioSegment(noteId, wav.path);
      // Even a partial batch must survive termination before flush starts.
      expect(context.pendingTranslations[noteId], 'A lecture sentence.');
      await expectLater(
        firstOrchestrator.drain(timeout: const Duration(seconds: 2)),
        throwsA(isA<TranslationDeferredException>()),
      );
      expect(firstOrchestrator.pendingTranslations, hasLength(1));
      expect(context.pendingTranslations[noteId], 'A lecture sentence.');
      await context.saveShadowDraft();
      firstOrchestrator.dispose();

      final restored = await ShadowDraftService.instance.readDraft(shadowPath);
      expect(restored, isNotNull);
      expect(restored!.pendingTranslations[noteId], 'A lecture sentence.');
      expect(restored.notes, hasLength(1));

      translationAvailable = true;
      ApiScheduler().cancelSession(restored.sessionId);
      final secondClient = client();
      final secondLimiter = _limiter();
      final secondService = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://groq.example',
        defaultModel: 'test',
        rateLimitService: secondLimiter,
        httpClient: secondClient,
      );
      final secondOrchestrator = AIOrchestratorService(
        sttService: secondService,
        translationService: secondService,
        sessionId: restored.sessionId,
        rateLimitService: secondLimiter,
        httpClient: secondClient,
      );
      restored.bindOrchestrator(secondOrchestrator);
      addTearDown(restored.dispose);
      final processor = SessionBackgroundProcessor.instance;
      final previousCloud = processor.cloudSyncService;
      processor.cloudSyncService = _FakeCloudSync();
      addTearDown(() => processor.cloudSyncService = previousCloud);
      SessionReadyEvent? ready;
      String? deferred;
      await processor.submit(
        HandoverPayload(
          context: restored,
          enableFinalRecap: false,
          onDone: (event) => ready = event,
          onStatus: (_) {},
          onDeferred: (message) => deferred = message,
          onError: (message) => fail('unexpected processing error: $message'),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(ready?.isFinal, isTrue);
      expect(deferred, isNull);
      expect(restored.pendingTranslations, isEmpty);
      expect(restored.notes, hasLength(1));
      expect(restored.notes.single.translatedContent, '一条讲座句子。');
      expect(secondOrchestrator.pendingTranslations, isEmpty);
      expect(await ShadowDraftService.instance.hasDraft(shadowPath), isFalse);
    },
  );
}
