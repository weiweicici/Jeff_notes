import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/screens/note_detail_screen.dart';
import 'package:jeff_notes/services/tts_service.dart';
import 'package:jeff_notes/widgets/tts_player_bar.dart';

void main() {
  test('generated documents use the fixed three-repeat dictation policy', () {
    expect(TtsService.generatedDocumentDictationLoopEnabledByDefault, isTrue);
    expect(TtsService.generatedDocumentDictationRepeatCount, 3);
    expect(
      TtsService.generatedDocumentDictationPause,
      const Duration(seconds: 3),
    );
  });

  test('listening shorthand repeats only answer-focus sentences twice', () {
    expect(TtsService.listeningOverviewRepeatCount, 1);
    expect(TtsService.listeningAnswerFocusRepeatCount, 2);
    expect(
      TtsService.splitChineseSentences('第一部分介绍主题。第二部分说明例子！中国（China）是填空词。'),
      hasLength(3),
    );
    final lineAware = TtsService.normalizeTextForSpeech(
      '第一个主要内容\n第二个主要内容',
      chineseLineBreaksEndSentences: true,
    );
    expect(TtsService.splitChineseSentences(lineAware), hasLength(2));

    const narration = '''讲座共有两个主要内容。第一个内容说明定义。
第二部分，答题重点与危险位置。
填空词是中国，China。转折后结论发生改变。''';
    expect(TtsService.listeningChineseRepeatCountForSentence(narration, 0), 1);
    expect(TtsService.listeningChineseRepeatCountForSentence(narration, 1), 1);
    expect(TtsService.listeningChineseRepeatCountForSentence(narration, 2), 1);
    expect(TtsService.listeningChineseRepeatCountForSentence(narration, 3), 2);
    expect(TtsService.listeningChineseRepeatCountForSentence(narration, 4), 2);
    expect(TtsService.listeningChineseRepeatCountForSentence('普通中文总结。', 0), 1);
  });

  group('generated essay English extraction for automatic TTS', () {
    test('extracts Part 1 and excludes Part 2 Chinese translation', () {
      const source = '''Part 1: The English Essay with ==highlighters==.

This is the first sentence. This is the second sentence.

---

Part 2: The sentence-by-sentence Chinese translation.

这是第一句。''';

      expect(
        extractGeneratedEssayEnglish(source),
        'This is the first sentence. This is the second sentence.',
      );
    });

    test('supports Markdown heading variants', () {
      const source = '''## English Essay

First paragraph.

Second paragraph.

## Chinese Translation

中文翻译。''';

      expect(
        extractGeneratedEssayEnglish(source),
        'First paragraph.\n\nSecond paragraph.',
      );
    });

    test('uses text before separator when Part labels are omitted', () {
      const source = '''First English sentence.

Second English sentence.

---

第一句中文。''';

      expect(
        extractGeneratedEssayEnglish(source),
        'First English sentence.\n\nSecond English sentence.',
      );
    });
  });

  group('essay TTS player default tab', () {
    test('dictation selects English even when Chinese content exists', () {
      expect(
        initialTtsTabIndex(
          enableEnglishDictation: true,
          hasChinese: true,
          hasRecordedAudio: false,
        ),
        1,
      );
    });

    test('ordinary bilingual notes continue to default to Chinese', () {
      expect(
        initialTtsTabIndex(
          enableEnglishDictation: false,
          hasChinese: true,
          hasRecordedAudio: false,
        ),
        0,
      );
    });
  });

  group('listening shorthand TTS extraction', () {
    test('plays the two exam narration blocks instead of full transcripts', () {
      const source = '''【全篇逻辑播报·可播放】
这篇讲座共有两个主要内容。第一个内容讨论中国（China）。
━━━━━━━━━━━━
【答题重点与危险位置·可播放】
第一个可能的填空词是中国（China）。
━━━━━━━━━━━━
【中文全文】
这里是很长的中文全文。
━━━━━━━━━━━━
【英文全文】
This is the full transcript.''';

      final narration = extractListeningShorthandNarration(source);
      expect(narration, contains('共有两个主要内容'));
      expect(narration, contains('第二部分，答题重点与危险位置'));
      expect(narration, contains('中国（China）'));
      expect(narration, isNot(contains('很长的中文全文')));
      expect(narration, isNot(contains('full transcript')));
    });

    test('turns bilingual parentheses into natural TTS pauses', () {
      expect(TtsService.normalizeTextForSpeech('中国（China）'), '中国，China，');
      expect(
        TtsService.normalizeTextForSpeech('消费者行为(consumer behavior)'),
        '消费者行为，consumer behavior，',
      );
    });
  });

  group('documents with English dictation controls', () {
    test('includes both essay types and grammar writing practice', () {
      expect(
        supportsEnglishDictationDocument('/docs/Jeff_Essay_topic.md'),
        isTrue,
      );
      expect(
        supportsEnglishDictationDocument('/docs/Jeff_Grammar_sample.md'),
        isTrue,
      );
    });

    test('does not enable dictation controls for listening notes', () {
      expect(
        supportsEnglishDictationDocument('/docs/Jeff_Lecture_note.md'),
        isFalse,
      );
    });
  });

  group('listening notes with Chinese dictation controls', () {
    test('recognizes shorthand filename and narration marker', () {
      expect(
        supportsListeningChineseDictationDocument(
          '/docs/Jeff_速记_20260807.md',
          '速记内容',
        ),
        isTrue,
      );
      expect(
        supportsListeningChineseDictationDocument(
          '/docs/Jeff_Notes_20260807.md',
          '【全篇逻辑播报·可播放】\n速记内容',
        ),
        isTrue,
      );
      expect(
        supportsListeningChineseDictationDocument(
          '/docs/ordinary.md',
          '普通中文笔记',
        ),
        isFalse,
      );
    });
  });
}
