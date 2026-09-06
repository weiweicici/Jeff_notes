import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';

void main() {
  test('parses Retry-After seconds and standard HTTP date', () {
    final now = DateTime.utc(2015, 10, 21, 7, 27, 50);
    expect(
      ApiRateLimitService.parseRetryAfter('2', now: now),
      const Duration(seconds: 2),
    );
    expect(
      ApiRateLimitService.parseRetryAfter(
        'Wed, 21 Oct 2015 07:28:00 GMT',
        now: now,
      ),
      const Duration(seconds: 10),
    );
    expect(
      ApiRateLimitService.parseGeminiRetryDelay({
        'error': {
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.RetryInfo',
              'retryDelay': '3.5s',
            },
          ],
        },
      }),
      const Duration(milliseconds: 3500),
    );
    expect(ApiRateLimitService.parseRetryAfter('NaN'), isNull);
    expect(ApiRateLimitService.parseRetryAfter('-1'), isNull);
    expect(ApiRateLimitService.parseRetryAfter('Infinity'), isNull);
    expect(
      ApiRateLimitService.parseGeminiRetryDelay({
        'error': {
          'details': [
            {
              '@type': 'type.googleapis.com/google.rpc.RetryInfo',
              'retryDelay': '999999999999999999999999s',
            },
          ],
        },
      }),
      isNull,
    );
  });

  test(
    'persists provider/model cooldown and blocks without another request',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var now = DateTime.utc(2026, 8, 30);
      final service = ApiRateLimitService.forTesting(
        prefsLoader: () async => prefs,
        clock: () => now,
      );
      final retryAt = await service.register429(
        provider: 'groq',
        model: 'whisper-large-v3',
        serverDelay: const Duration(seconds: 120),
      );
      expect(retryAt, now.add(const Duration(seconds: 120)));
      await expectLater(
        () => service.ensureAvailable('groq', 'whisper-large-v3'),
        throwsA(isA<ApiRateLimitException>()),
      );

      final restored = ApiRateLimitService.forTesting(
        prefsLoader: () async => prefs,
        clock: () => now,
      );
      await expectLater(
        () => restored.ensureAvailable('groq', 'whisper-large-v3'),
        throwsA(isA<ApiRateLimitException>()),
      );
      now = retryAt;
      await restored.ensureAvailable('groq', 'whisper-large-v3');
    },
  );

  for (final endpoint in <({String name, String baseUrl, String provider})>[
    (name: 'Groq', baseUrl: 'https://api.groq.com/openai/v1', provider: 'groq'),
    (
      name: 'OpenRouter',
      baseUrl: 'https://openrouter.ai/api/v1',
      provider: 'openrouter',
    ),
  ]) {
    test(
      '${endpoint.name} translation 429 registers Retry-After cooldown',
      () async {
        const now = 1788048000000; // 2026-08-30T00:00:00Z
        final limiter = ApiRateLimitService.forTesting(
          prefsLoader: () async =>
              throw StateError('no preferences in unit test'),
          clock: () => DateTime.fromMillisecondsSinceEpoch(now, isUtc: true),
        );
        var requests = 0;
        final service = OpenAIService(
          apiKey: 'test-key',
          baseUrl: endpoint.baseUrl,
          defaultModel: 'translation-model',
          rateLimitService: limiter,
          httpClient: MockClient((request) async {
            requests++;
            return http.Response(
              jsonEncode({'error': 'rate limited'}),
              429,
              headers: {'retry-after': '120'},
            );
          }),
        );
        addTearDown(service.dispose);

        await expectLater(
          service.translate('A lecture sentence.'),
          throwsA(
            isA<ApiRateLimitException>()
                .having(
                  (error) => error.provider,
                  'provider',
                  endpoint.provider,
                )
                .having((error) => error.model, 'model', 'translation-model')
                .having(
                  (error) => error.retryAt,
                  'retryAt',
                  DateTime.fromMillisecondsSinceEpoch(
                    now + const Duration(seconds: 120).inMilliseconds,
                    isUtc: true,
                  ),
                ),
          ),
        );
        await expectLater(
          service.translate('A later sentence.'),
          throwsA(
            isA<ApiRateLimitException>().having(
              (error) => error.source,
              'source',
              'cooldown',
            ),
          ),
        );
        expect(requests, 1);
      },
    );
  }

  test(
    'translation rejects a response that becomes empty after cleanup',
    () async {
      final service = OpenAIService(
        apiKey: 'test-key',
        baseUrl: 'https://api.groq.com/openai/v1',
        defaultModel: 'translation-model',
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': '''```text
Translation: 
```''',
                  },
                },
              ],
            }),
            200,
          ),
        ),
      );
      addTearDown(service.dispose);

      await expectLater(
        service.translate('A lecture sentence.'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Translation response was empty after sanitization',
          ),
        ),
      );
    },
  );
}
