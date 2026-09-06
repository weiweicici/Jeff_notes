import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jeff_notes/ai_orchestrator_service.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/openai_service.dart';
import 'package:jeff_notes/prompt_provider.dart';
import 'package:jeff_notes/services/transcript_assembler.dart';
import 'package:jeff_notes/services/wav_stitch_service.dart';

void main() {
  group('Final exam first-listening pipeline', () {
    test('routes rolling and final prompts to separate contracts', () {
      final rolling = PromptProvider.getSystemPrompt(
        PromptStrategy.rollingNotes,
        AIProvider.groq,
        mode: AppMode.exam,
      );
      expect(rolling, contains('ONE evolving set'));
      expect(rolling, contains('CURRENT DRAFT'));
      expect(rolling, isNot(contains('Answer Candidate Bank')));

      final exam = PromptProvider.getSystemPrompt(
        PromptStrategy.recap,
        AIProvider.groq,
        mode: AppMode.exam,
      );
      expect(exam, contains('One-Screen Exam View'));
      expect(exam, contains('Answer Candidate Bank'));
      expect(exam, contains('may be recorded only once'));
      expect(exam, isNot(contains('Blank 1')));

      final lecture = PromptProvider.getSystemPrompt(
        PromptStrategy.recap,
        AIProvider.groq,
        mode: AppMode.lecture,
      );
      expect(lecture, contains('【全篇逻辑播报·可播放】'));
      expect(lecture, contains('【答题重点与危险位置·可播放】'));
      expect(lecture, contains('no minimum length'));
      expect(lecture, contains('Never repeat, generalize, or add outside'));
      expect(lecture, contains('under 1200 Chinese'));
      expect(lecture, contains('how many distinct examples'));
      expect(lecture, contains('likely fill-in evidence in audio order'));
      expect(lecture, contains('True/False danger point'));
      expect(lecture, contains('中国（China）'));
      expect(lecture, contains('Output no blank lines anywhere'));
      expect(lecture, contains('━━━━━━━━━━━━'));
      expect(lecture, contains('Do not omit an example'));
      expect(lecture, isNot(contains('One-Screen Quick View')));

      final directGeminiShorthand = PromptProvider.getFinalReviewPrompt(
        AppMode.lecture,
        PathwaysUnit.none,
      );
      expect(directGeminiShorthand, lecture);
    });

    test(
      'assembles asynchronous STT slices in time order and removes overlap',
      () {
        final start = DateTime(2026, 7, 31, 12);
        final notes = <InsightNote>[
          InsightNote(
            summary: '',
            transcript: 'external factors influence decisions.',
            translatedContent: '外部因素影响决定。',
            timestamp: start.add(const Duration(seconds: 12)),
          ),
          InsightNote(
            summary: '',
            transcript: 'Consumer behavior includes external factors',
            translatedContent: '消费者行为包括外部因素',
            timestamp: start.add(const Duration(seconds: 6)),
          ),
          InsightNote(
            summary: '',
            transcript: '[Silence]',
            timestamp: start.add(const Duration(seconds: 18)),
          ),
        ];

        expect(
          TranscriptAssembler.english(notes),
          'Consumer behavior includes external factors influence decisions.',
        );
        expect(
          TranscriptAssembler.timestampedEnglish(notes, sessionStart: start),
          startsWith('[00:06] Consumer behavior'),
        );
        expect(TranscriptAssembler.chinese(notes), contains('外部因素影响决定'));
      },
    );

    test('stitches PCM WAV slices into one valid non-empty WAV', () async {
      final directory = await Directory.systemTemp.createTemp(
        'final_exam_wav_test_',
      );
      addTearDown(() => directory.delete(recursive: true));

      Future<File> makeSlice(String name, List<int> pcm) async {
        final file = File('${directory.path}/$name');
        await file.writeAsBytes(<int>[
          ...WavStitchService.wavHeader(pcm.length),
          ...pcm,
        ]);
        return file;
      }

      final first = await makeSlice('one.wav', <int>[1, 2, 3, 4]);
      final second = await makeSlice('two.wav', <int>[5, 6, 7, 8]);
      final output = '${directory.path}/combined.wav';

      expect(
        await WavStitchService.stitch(
          inputPaths: <String>[first.path, second.path],
          outputPath: output,
        ),
        isTrue,
      );
      final bytes = await File(output).readAsBytes();
      expect(bytes.length, 52);
      expect(
        bytes.sublist(44),
        Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
      );
    });

    test(
      'stitches multi-megabyte WAV slices without retaining all PCM',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'final_exam_large_wav_test_',
        );
        addTearDown(() => directory.delete(recursive: true));
        final block = Uint8List.fromList(List<int>.filled(256 * 1024, 0x5a));

        Future<File> makeLargeSlice(String name, int blockCount) async {
          final file = File('${directory.path}/$name');
          final sink = await file.open(mode: FileMode.write);
          try {
            await sink.writeFrom(
              WavStitchService.wavHeader(block.length * blockCount),
            );
            for (var index = 0; index < blockCount; index++) {
              await sink.writeFrom(block);
            }
          } finally {
            await sink.close();
          }
          return file;
        }

        final first = await makeLargeSlice('one.wav', 4);
        final second = await makeLargeSlice('two.wav', 4);
        final output = File('${directory.path}/combined.wav');

        expect(
          await WavStitchService.stitch(
            inputPaths: [first.path, second.path],
            outputPath: output.path,
          ),
          isTrue,
        );
        expect(await output.length(), 44 + 2 * 4 * block.length);
      },
    );

    test(
      'Gemini summary fallback preserves the shorthand system prompt',
      () async {
        late Map<String, dynamic> requestBody;
        final client = MockClient((request) async {
          requestBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(
              jsonEncode({
                'candidates': [
                  {
                    'finishReason': 'STOP',
                    'content': {
                      'parts': [
                        {'text': '【30秒理解·可播放】\n测试内容'},
                      ],
                    },
                  },
                ],
              }),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final service = OpenAIService(
          apiKey: 'test',
          baseUrl: 'https://example.invalid',
          defaultModel: 'test',
          httpClient: client,
        );
        final orchestrator = AIOrchestratorService(
          sttService: service,
          translationService: service,
          sessionId: 'gemini_summary_test',
          geminiApiKey: 'test-key',
          httpClient: client,
        );
        addTearDown(orchestrator.dispose);

        final result = await orchestrator.generateSummaryWithGemini(
          systemPrompt: 'SYSTEM-SHORTHAND-CONTRACT',
          userMessage: 'TRANSCRIPT',
          maxOutputTokens: 1800,
        );

        expect(result, '【30秒理解·可播放】\n测试内容');
        expect(
          requestBody['system_instruction']['parts'][0]['text'],
          'SYSTEM-SHORTHAND-CONTRACT',
        );
        expect(requestBody['generationConfig']['maxOutputTokens'], 1800);
        expect(
          requestBody['generationConfig']['thinkingConfig']['thinkingBudget'],
          0,
        );
      },
    );

    test('Gemini summary fallback rejects MAX_TOKENS output', () async {
      final client = MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'candidates': [
                {
                  'finishReason': 'MAX_TOKENS',
                  'content': {
                    'parts': [
                      {'text': '【30秒理解·可播放】\n只有半份内容'},
                    ],
                  },
                },
              ],
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final service = OpenAIService(
        apiKey: 'test',
        baseUrl: 'https://example.invalid',
        defaultModel: 'test',
        httpClient: client,
      );
      final orchestrator = AIOrchestratorService(
        sttService: service,
        translationService: service,
        sessionId: 'gemini_truncation_test',
        geminiApiKey: 'test-key',
        httpClient: client,
      );
      addTearDown(orchestrator.dispose);

      final result = await orchestrator.generateSummaryWithGemini(
        systemPrompt: 'SYSTEM-SHORTHAND-CONTRACT',
        userMessage: 'TRANSCRIPT',
      );

      expect(result, isNull);
    });
  });
}
