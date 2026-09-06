import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/local_translation_service.dart';

class _LocalTranslator implements LocalTextTranslator {
  _LocalTranslator({this.error});

  final Object? error;
  final List<String> inputs = [];

  @override
  Future<String> translateEnglishToChinese(String text) async {
    inputs.add(text);
    if (error != null) throw error!;
    return '本机译文';
  }
}

ApiRateLimitService _limiter() => ApiRateLimitService.forTesting(
  prefsLoader: () async => throw StateError('no prefs'),
  clock: () => DateTime.utc(2026, 9, 1),
);

void main() {
  test('only Lecture and Free Talk select on-device translation', () {
    expect(shouldUseOnDeviceTranslation(AppMode.lecture), isTrue);
    expect(shouldUseOnDeviceTranslation(AppMode.freeTalk), isTrue);
    expect(shouldUseOnDeviceTranslation(AppMode.discussion), isFalse);
    expect(shouldUseOnDeviceTranslation(AppMode.exam), isFalse);
  });

  test('local translation bypasses every cloud translation endpoint', () async {
    var cloudRequests = 0;
    final client = MockClient((request) async {
      cloudRequests++;
      return http.Response('cloud translation must not be called', 429);
    });
    final remote = OpenAIService(
      apiKey: 'test',
      baseUrl: 'https://cloud.example',
      defaultModel: 'test',
      rateLimitService: _limiter(),
      httpClient: client,
    );
    final local = _LocalTranslator();
    final orchestrator = AIOrchestratorService(
      sttService: remote,
      translationService: remote,
      translationFallbackService: remote,
      localTranslator: local,
      sessionId: 'local-success',
      geminiApiKey: 'must-not-be-used',
      rateLimitService: _limiter(),
      httpClient: client,
    );
    addTearDown(orchestrator.dispose);
    final results = <PipelineResult>[];
    final subscription = orchestrator.accurateChineseStream.listen(results.add);
    addTearDown(subscription.cancel);

    orchestrator.restorePendingTranslations(const [
      PendingTranslation('note-1', 'English classroom sentence.'),
    ]);
    await orchestrator.retryPendingTranslations();
    await Future<void>.delayed(Duration.zero);

    expect(local.inputs, ['English classroom sentence.']);
    expect(cloudRequests, 0);
    expect(results.single.noteId, 'note-1');
    expect(results.single.content, '本机译文');
    expect(orchestrator.pendingTranslations, isEmpty);
  });

  test(
    'local failure remains recoverable and never falls back to AI',
    () async {
      var cloudRequests = 0;
      final client = MockClient((request) async {
        cloudRequests++;
        return http.Response('cloud translation must not be called', 200);
      });
      final remote = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://cloud.example',
        defaultModel: 'test',
        rateLimitService: _limiter(),
        httpClient: client,
      );
      final orchestrator = AIOrchestratorService(
        sttService: remote,
        translationService: remote,
        translationFallbackService: remote,
        localTranslator: _LocalTranslator(error: StateError('model missing')),
        sessionId: 'local-failure',
        geminiApiKey: 'must-not-be-used',
        rateLimitService: _limiter(),
        httpClient: client,
      );
      addTearDown(orchestrator.dispose);
      orchestrator.restorePendingTranslations(const [
        PendingTranslation('note-1', 'Keep this durable.'),
      ]);

      await orchestrator.retryPendingTranslations();

      expect(cloudRequests, 0);
      expect(orchestrator.pendingTranslations.single.noteId, 'note-1');
      await expectLater(
        orchestrator.drain(timeout: const Duration(milliseconds: 200)),
        throwsA(isA<TranslationDeferredException>()),
      );
    },
  );
}
