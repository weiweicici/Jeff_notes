import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/insight_note.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/speech_gate_service.dart';

Future<File> _writeCustomWav(
  Directory directory,
  String name, {
  required int amplitude,
}) async {
  const sampleRate = 16000;
  const sampleCount = sampleRate; // 1 second
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
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little); // 16-bit
  ascii(36, 'data');
  data.setUint32(40, sampleCount * 2, Endian.little);

  for (var i = 0; i < sampleCount; i++) {
    final sample = amplitude > 0
        ? (amplitude * math.sin(2 * math.pi * 440 * i / sampleRate)).round()
        : 0;
    data.setInt16(44 + i * 2, sample, Endian.little);
  }

  final file = File('${directory.path}/$name');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

ApiRateLimitService _testRateLimiter() => ApiRateLimitService.forTesting(
  prefsLoader: () async => throw StateError('no prefs in test'),
  clock: () => DateTime.utc(2026, 9, 1),
);

AIOrchestratorService _makeOrchestrator(http.Client client, String sessionId) {
  final limiter = _testRateLimiter();
  final openAi = OpenAIService(
    apiKey: 'test-key',
    baseUrl: 'https://groq.example',
    defaultModel: 'whisper-large-v3',
    rateLimitService: limiter,
    httpClient: client,
  );
  return AIOrchestratorService(
    sttService: openAi,
    translationService: openAi,
    sessionId: sessionId,
    rateLimitService: limiter,
    httpClient: client,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('speech_gate_test_');
  });

  tearDown(() async {
    try {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Layer A — Pre-STT Speech/Energy Gate', () {
    test('1. silent WAV skipped before STT without making API calls', () async {
      final wav = await _writeCustomWav(
        tempDirectory,
        'silent.wav',
        amplitude: 0,
      );

      var httpCallsCount = 0;
      final client = MockClient((request) async {
        httpCallsCount++;
        return http.Response(jsonEncode({'text': 'should not be called'}), 200);
      });

      final orchestrator = _makeOrchestrator(client, 'session-silence');
      addTearDown(orchestrator.dispose);

      final fastEnglishFuture = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('note-silent', wav.path);

      // Verify zero HTTP requests made
      expect(
        httpCallsCount,
        0,
        reason: 'Silent WAV must not trigger STT request',
      );

      // Verify Fast English emits [Silence]
      final result = await fastEnglishFuture;
      expect(result.noteId, 'note-silent');
      expect(result.content, '[Silence]');
    });

    test('2. low-noise non-zero WAV fails open to STT', () async {
      // Non-zero PCM is never treated as proven digital silence.
      final wav = await _writeCustomWav(
        tempDirectory,
        'ambient.wav',
        amplitude: 30,
      );

      var httpCallsCount = 0;
      final client = MockClient((request) async {
        httpCallsCount++;
        return http.Response(jsonEncode({'text': 'noise'}), 200);
      });

      final orchestrator = _makeOrchestrator(client, 'session-ambient');
      addTearDown(orchestrator.dispose);

      final fastEnglishFuture = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('note-ambient', wav.path);

      expect(httpCallsCount, 1, reason: 'Non-zero WAV must fail open to STT');
      final result = await fastEnglishFuture;
      expect(result.content, 'noise');
    });

    test('3. real speech-like WAV proceeds to STT', () async {
      // amplitude 7000: peak 7000, rmsDb ~ -16.4 dB
      final wav = await _writeCustomWav(
        tempDirectory,
        'speech.wav',
        amplitude: 7000,
      );

      var httpCallsCount = 0;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          httpCallsCount++;
          return http.Response(
            jsonEncode({'text': "Welcome to today's networking lecture."}),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final orchestrator = _makeOrchestrator(client, 'session-speech');
      addTearDown(orchestrator.dispose);

      final fastEnglishFuture = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('note-speech', wav.path);

      expect(httpCallsCount, 1, reason: 'Audible speech must proceed to STT');
      final result = await fastEnglishFuture;
      expect(result.content, "Welcome to today's networking lecture.");
    });
  });

  group('Layer B — STT Hallucination Guard', () {
    test('4. "Thank you" on low-energy non-zero slice is preserved', () async {
      final wav = await _writeCustomWav(
        tempDirectory,
        'faint_noise.wav',
        amplitude: 200,
      );

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          // Whisper hallucination on faint ambient noise
          return http.Response(jsonEncode({'text': 'Thank you.'}), 200);
        }
        return http.Response('not found', 404);
      });

      final orchestrator = _makeOrchestrator(client, 'session-hallucination');
      addTearDown(orchestrator.dispose);

      final fastEnglishFuture = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('note-faint', wav.path);

      final result = await fastEnglishFuture;
      // Low energy alone is not reliable evidence of hallucination.
      expect(result.content, 'Thank you.');
    });

    test('5. "Thank you" on normal-energy audible slice is preserved', () async {
      // amplitude 7000: strong speech signal (peak 7000 >= 600, rmsDb ~ -16.4 dB >= -36.0 dB)
      final wav = await _writeCustomWav(
        tempDirectory,
        'teacher_thank_you.wav',
        amplitude: 7000,
      );

      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          return http.Response(jsonEncode({'text': 'Thank you.'}), 200);
        }
        return http.Response('not found', 404);
      });

      final orchestrator = _makeOrchestrator(client, 'session-real-speech');
      addTearDown(orchestrator.dispose);

      final fastEnglishFuture = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('note-real', wav.path);

      final result = await fastEnglishFuture;
      // Real speech with sufficient energy MUST NOT be suppressed
      expect(result.content, 'Thank you.');
    });

    test('6. Short candidate phrases on low energy are preserved', () async {
      final wav = await _writeCustomWav(
        tempDirectory,
        'faint_noise2.wav',
        amplitude: 220,
      );

      for (final phrase in [
        'Bye.',
        'Thanks for watching!',
        'Goodbye',
        'You.',
      ]) {
        final client = MockClient((request) async {
          return http.Response(jsonEncode({'text': phrase}), 200);
        });

        final orchestrator = _makeOrchestrator(client, 'session-guard-$phrase');
        addTearDown(orchestrator.dispose);

        final fastEnglishFuture = orchestrator.fastEnglishStream.first;
        await orchestrator.processAudioSegment('note-$phrase', wav.path);

        final result = await fastEnglishFuture;
        expect(
          result.content,
          phrase,
          reason: 'Phrase "$phrase" must fail open',
        );
      }
    });
  });

  group('Session Continuity & Recovery Invariance', () {
    test('7. recording session remains active after silent slices', () async {
      final silentWav = await _writeCustomWav(
        tempDirectory,
        'seq_silent.wav',
        amplitude: 0,
      );
      final speechWav = await _writeCustomWav(
        tempDirectory,
        'seq_speech.wav',
        amplitude: 7000,
      );

      var speechRequested = false;
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/audio/transcriptions')) {
          speechRequested = true;
          return http.Response(
            jsonEncode({'text': 'Active lecture resumed.'}),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final orchestrator = _makeOrchestrator(client, 'session-continuity');
      addTearDown(orchestrator.dispose);

      // Slice 1: Silence
      await orchestrator.processAudioSegment('slice-1', silentWav.path);
      expect(speechRequested, isFalse);

      // Slice 2: Real speech resumes automatically
      final speechResult = orchestrator.fastEnglishStream.first;
      await orchestrator.processAudioSegment('slice-2', speechWav.path);

      expect(speechRequested, isTrue);
      expect((await speechResult).content, 'Active lecture resumed.');
    });

    test(
      '8. skipped slice does not trigger recovery failure or retry loop',
      () async {
        final silentWav = await _writeCustomWav(
          tempDirectory,
          'rec_silent.wav',
          amplitude: 0,
        );
        final context = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.none,
          baseDirectory: tempDirectory.path,
          customSessionId: 'rec-test-123',
        );

        final client = MockClient((request) async {
          return http.Response(jsonEncode({'text': 'unexpected'}), 500);
        });
        final orchestrator = _makeOrchestrator(client, 'rec-test-123');
        context.bindOrchestrator(orchestrator);
        addTearDown(orchestrator.dispose);

        // Register audio slice as pending in context
        context.registerPendingAudio(silentWav.path);
        final note = InsightNote(
          id: 'note-rec-1',
          summary: '',
          transcript: '...',
          timestamp: DateTime.now(),
          isProcessing: true,
        );
        context.bindPendingAudioToNote(silentWav.path, note.id);
        context.notes.add(note);

        // Process silent slice
        final fastEvent = orchestrator.fastEnglishStream.first;
        await orchestrator.processAudioSegment(note.id, silentWav.path);
        await fastEvent;
        await pumpEventQueue();

        // Verify note received [Silence]
        expect(note.transcript, '[Silence]');

        // Complete pending audio as RecordingProvider does
        context.completeTranscriptForAudio(silentWav.path, note.transcript);
        context.completePendingAudio(silentWav.path);

        // Verify slice was removed from pendingAudioNotes without lingering in queue
        expect(context.pendingAudioNotes.containsKey(silentWav.path), isFalse);
        expect(
          context.pendingAudioSequences.containsKey(silentWav.path),
          isFalse,
        );
        context.dispose();
      },
    );
  });

  group('Conservative WAV boundaries', () {
    test('digital zero is the only proven silence', () async {
      final wav = await _writeCustomWav(
        tempDirectory,
        'zero.wav',
        amplitude: 0,
      );
      final metrics = await SpeechGateService.analyzeWav(wav.path);
      expect(metrics.hasAudibleSpeech, isFalse);
      expect(metrics.peak, 0);
    });

    test(
      'non-zero quiet signal fails open, including an unsampled-phase pulse',
      () async {
        final wav = await _writeCustomWav(
          tempDirectory,
          'pulse.wav',
          amplitude: 0,
        );
        final bytes = await wav.readAsBytes();
        final data = ByteData.sublistView(bytes);
        // Index 1 used to be skipped by the every-fourth-sample implementation.
        data.setInt16(44 + 2, 300, Endian.little);
        final metrics = SpeechGateService.analyzeBytes(bytes);
        expect(metrics.hasAudibleSpeech, isTrue);
        expect(metrics.peak, 300);
        expect(metrics.isLowEnergy, isFalse);
      },
    );

    test(
      'missing, short, and non-PCM input are unknown rather than silence',
      () async {
        final missing = await SpeechGateService.analyzeWav(
          '${tempDirectory.path}/missing.wav',
        );
        expect(missing.hasAudibleSpeech, isTrue);

        final short = SpeechGateService.analyzeBytes(Uint8List(45));
        expect(short.hasAudibleSpeech, isTrue);

        final wav = await _writeCustomWav(
          tempDirectory,
          'bad-format.wav',
          amplitude: 0,
        );
        final bytes = await wav.readAsBytes();
        ByteData.sublistView(
          bytes,
        ).setUint16(20, 3, Endian.little); // IEEE float
        final badFormat = SpeechGateService.analyzeBytes(bytes);
        expect(badFormat.hasAudibleSpeech, isTrue);
      },
    );
  });
}
