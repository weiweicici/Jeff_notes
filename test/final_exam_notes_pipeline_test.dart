import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
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
      expect(lecture, contains('【30秒理解·可播放】'));
      expect(lecture, contains('【Purpose（目的）】'));
      expect(lecture, contains('【二听】'));
      expect(lecture, contains('【符号】'));
      expect(lecture, contains('Output no blank lines anywhere'));
      expect(lecture, contains('English-first'));
      expect(lecture, contains('━━━━━━━━━━━━'));
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
  });
}
