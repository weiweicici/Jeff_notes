import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/screens/note_detail_screen.dart';
import 'package:jeff_notes/widgets/tts_player_bar.dart';

void main() {
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
}
