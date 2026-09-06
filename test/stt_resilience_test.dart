import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';

Future<File> _writeWav(
  Directory directory,
  String name, {
  required bool tone,
}) async {
  const sampleRate = 16000;
  const sampleCount = sampleRate;
  final bytes = Uint8List(44 + sampleCount * 2);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, bytes.length - 8, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, sampleCount * 2, Endian.little);
  for (var i = 0; i < sampleCount; i++) {
    final sample = tone
        ? (7000 * math.sin(2 * math.pi * 440 * i / sampleRate)).round()
        : 0;
    data.setInt16(44 + i * 2, sample, Endian.little);
  }

  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

ApiRateLimitService _freshRateLimitService() => ApiRateLimitService.forTesting(
  prefsLoader: () async => throw StateError('no prefs in unit test'),
  clock: () => DateTime.utc(2026, 8, 30),
);

AIOrchestratorService _orchestrator(
  http.Client client,
  String sessionId, {
  String geminiApiKey = '',
  ApiRateLimitService? rateLimitService,
}) {
  final limiter = rateLimitService ?? _freshRateLimitService();
  final service = OpenAIService(
    apiKey: 'test',
    baseUrl: 'https://groq.example',
    defaultModel: 'test',
    rateLimitService: limiter,
    httpClient: client,
  );
  return AIOrchestratorService(
    sttService: service,
    translationService: service,
    sessionId: sessionId,
    geminiApiKey: geminiApiKey,
    rateLimitService: limiter,
    httpClient: client,
  );
}

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('jeff_stt_test_');
  });

  tearDown(() async {
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test(
    'WAV signal detector separates audible speech-level audio from silence',
    () async {
      final audible = await _writeWav(tempDirectory, 'audible.wav', tone: true);
      final silent = await _writeWav(tempDirectory, 'silent.wav', tone: false);

      expect(await wavContainsAudibleSignal(audible.path), isTrue);
      expect(await wavContainsAudibleSignal(silent.path), isFalse);
    },
  );

  test('Groq 429 is attempted once and propagates typed limit', () async {
    final wav = await _writeWav(tempDirectory, 'retry.wav', tone: true);
    var sttCalls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/audio/transcriptions')) {
        sttCalls++;
        return http.Response('rate limited', 429);
      }
      if (request.url.path.endsWith('/chat/completions')) {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '清晰的讲座内容。'},
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('unexpected', 404);
    });
    final orchestrator = _orchestrator(client, 'stt_retry_test');
    addTearDown(orchestrator.dispose);
    final emitted = <PipelineResult>[];
    final subscription = orchestrator.fastEnglishStream.listen(emitted.add);
    addTearDown(subscription.cancel);
    await expectLater(
      orchestrator.processAudioSegment('note-1', wav.path),
      throwsA(isA<ApiRateLimitException>()),
    );
    expect(sttCalls, 1);
    expect(emitted.where((e) => e.content.startsWith('[Error:')), isEmpty);
  });

  test('a second call during cooldown sends no Groq HTTP request', () async {
    final wav = await _writeWav(tempDirectory, 'cooldown.wav', tone: true);
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('rate limited', 429);
    });
    final limiter = _freshRateLimitService();
    final service = OpenAIService(
      apiKey: 'test',
      baseUrl: 'https://groq.example',
      defaultModel: 'test',
      rateLimitService: limiter,
      httpClient: client,
    );
    addTearDown(service.dispose);
    await expectLater(
      service.transcribe(wav.path),
      throwsA(isA<ApiRateLimitException>()),
    );
    await expectLater(
      service.transcribe(wav.path),
      throwsA(isA<ApiRateLimitException>()),
    );
    expect(calls, 1);
  });

  test('Groq 429 falls back to Gemini successfully', () async {
    final wav = await _writeWav(tempDirectory, 'fallback.wav', tone: true);
    var groqCalls = 0;
    var geminiCalls = 0;
    final limiter = _freshRateLimitService();
    final client = MockClient((request) async {
      if (request.url.host == 'groq.example') {
        groqCalls++;
        return http.Response('rate limited', 429);
      }
      if (request.url.host == 'generativelanguage.googleapis.com') {
        geminiCalls++;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'Recovered Gemini speech.'},
                  ],
                },
              },
            ],
          }),
          200,
        );
      }
      return http.Response('unexpected', 404);
    });
    final orchestrator = _orchestrator(
      client,
      'stt_gemini_fallback_test',
      geminiApiKey: 'gemini-test-key',
      rateLimitService: limiter,
    );
    addTearDown(orchestrator.dispose);
    final result = orchestrator.fastEnglishStream.first;
    await orchestrator.processAudioSegment('note-fallback', wav.path);
    expect((await result).content, 'Recovered Gemini speech.');
    expect(groqCalls, 1);
    expect(geminiCalls, 1);
  });

  test(
    'Groq and Gemini 429 both propagate typed limit without error note',
    () async {
      final wav = await _writeWav(
        tempDirectory,
        'both-limited.wav',
        tone: true,
      );
      final client = MockClient((request) async {
        if (request.url.host == 'groq.example') {
          return http.Response('rate limited', 429);
        }
        if (request.url.host == 'generativelanguage.googleapis.com') {
          return http.Response(
            jsonEncode({
              'error': {
                'details': [
                  {
                    '@type': 'type.googleapis.com/google.rpc.RetryInfo',
                    'retryDelay': '2s',
                  },
                ],
              },
            }),
            429,
          );
        }
        return http.Response('unexpected', 404);
      });
      final orchestrator = _orchestrator(
        client,
        'stt_both_limited_test',
        geminiApiKey: 'gemini-test-key',
      );
      addTearDown(orchestrator.dispose);
      final emitted = <PipelineResult>[];
      final subscription = orchestrator.fastEnglishStream.listen(emitted.add);
      addTearDown(subscription.cancel);
      await expectLater(
        orchestrator.processAudioSegment('note-both-limited', wav.path),
        throwsA(
          isA<ApiRateLimitException>().having(
            (e) => e.provider,
            'provider',
            'gemini',
          ),
        ),
      );
      expect(emitted.where((e) => e.content.startsWith('[Error:')), isEmpty);
    },
  );

  test(
    'audible WAV with unavailable STT is retained instead of labeled silence',
    () async {
      final wav = await _writeWav(tempDirectory, 'retain.wav', tone: true);
      final client = MockClient(
        (request) async => http.Response('unauthorized', 401),
      );
      final orchestrator = _orchestrator(client, 'stt_retain_test');
      addTearDown(orchestrator.dispose);
      final emitted = <PipelineResult>[];
      final subscription = orchestrator.fastEnglishStream.listen(emitted.add);
      addTearDown(subscription.cancel);

      await expectLater(
        orchestrator.processAudioSegment('note-2', wav.path),
        throwsA(isA<SttUnavailableException>()),
      );
      expect(emitted.where((result) => result.content == '[Silence]'), isEmpty);
    },
  );

  test('truly silent WAV can still be labeled silence', () async {
    final wav = await _writeWav(tempDirectory, 'silence.wav', tone: false);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/audio/transcriptions')) {
        return http.Response(jsonEncode({'text': ''}), 200);
      }
      return http.Response('unexpected', 404);
    });
    final orchestrator = _orchestrator(client, 'stt_silence_test');
    addTearDown(orchestrator.dispose);
    final result = orchestrator.fastEnglishStream.first;

    await orchestrator.processAudioSegment('note-3', wav.path);

    expect((await result).content, '[Silence]');
  });
}
