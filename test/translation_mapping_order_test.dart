import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/local_translation_service.dart';

ApiRateLimitService _limiter() => ApiRateLimitService.forTesting(
  prefsLoader: () async => throw StateError('no preferences in unit test'),
  clock: () => DateTime.utc(2026, 9, 5),
);

class _EchoTranslator implements LocalTextTranslator {
  final List<String> inputs = [];

  @override
  Future<String> translateEnglishToChinese(String text) async {
    inputs.add(text);
    return '译文<$text>';
  }
}

OpenAIService _service(http.Client client) => OpenAIService(
  apiKey: 'test',
  baseUrl: 'https://translation.example',
  defaultModel: 'test',
  rateLimitService: _limiter(),
  httpClient: client,
);

void main() {
  test('backlogged translations retain each note boundary and content', () async {
    final client = MockClient((_) async => http.Response('unexpected', 500));
    final local = _EchoTranslator();
    final orchestrator = AIOrchestratorService(
      sttService: _service(client),
      translationService: _service(client),
      localTranslator: local,
      sessionId: 'mapping-backlog',
      rateLimitService: _limiter(),
      httpClient: client,
    );
    addTearDown(orchestrator.dispose);
    final results = <String, String>{};
    final subscription = orchestrator.accurateChineseStream.listen(
      (result) => results[result.noteId] = result.content,
    );
    addTearDown(subscription.cancel);

    final texts = <String>[
      'One short sentence.',
      'Two sentences. Still one note.',
      'Server IP is 192.168.1.109. Keep it whole.',
      'A fragment without punctuation',
      'Question one? Question two? Question three?',
      'Decimal values 3.14 and 2.718 stay together.',
      'A.',
      'This note has a much longer sentence than the others, but remains one unit.',
      'Final note. With two clauses.',
      'Tenth and last.',
    ];
    orchestrator.restorePendingTranslations([
      for (var index = 0; index < texts.length; index++)
        PendingTranslation('note-$index', texts[index]),
    ]);

    await orchestrator.retryPendingTranslations();
    await orchestrator.drain(timeout: const Duration(seconds: 2));

    expect(local.inputs, texts);
    expect(results, {
      for (var index = 0; index < texts.length; index++)
        'note-$index': '译文<${texts[index]}>',
    });
    expect(orchestrator.pendingTranslations, isEmpty);
  });

  test(
    'translation uses the history snapshot from its own STT request',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'history_snapshot_',
      );
      addTearDown(() => directory.delete(recursive: true));
      final wav = File('${directory.path}/slice.wav')
        ..writeAsBytesSync(List<int>.filled(200, 1));
      final sttReady = Completer<void>();
      Map<String, dynamic>? translationRequest;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          await sttReady.future;
          return http.Response(jsonEncode({'text': 'Current sentence.'}), 200);
        }
        if (request.url.path.endsWith('/chat/completions')) {
          translationRequest = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '当前句子。'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.Response('unexpected', 404);
      });
      final service = _service(client);
      final orchestrator = AIOrchestratorService(
        sttService: service,
        translationService: service,
        sessionId: 'history-snapshot',
        rateLimitService: _limiter(),
        httpClient: client,
      );
      addTearDown(orchestrator.dispose);
      final history = <Map<String, String>>[
        {'english': 'Original context.', 'chinese': '原始上下文。'},
      ];

      final processing = orchestrator.processAudioSegment(
        'note-1',
        wav.path,
        translationHistory: history,
      );
      history[0]['english'] = 'Mutated context.';
      history.add({'english': 'Later context.', 'chinese': '之后的上下文。'});
      sttReady.complete();
      await processing;
      await orchestrator.drain(timeout: const Duration(seconds: 2));

      final messages = translationRequest!['messages'] as List<dynamic>;
      final serialized = jsonEncode(messages);
      expect(serialized, contains('Original context.'));
      expect(serialized, isNot(contains('Mutated context.')));
      expect(serialized, isNot(contains('Later context.')));
    },
  );
}
