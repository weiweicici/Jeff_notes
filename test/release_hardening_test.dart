import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/adapters/audio_recorder_adapter.dart';
import 'package:jeff_notes/services/reading_content_parser.dart';
import 'package:jeff_notes/text_sanitizer.dart';
import 'package:record/record.dart';

void main() {
  group('Stage 6 text and multi-page parsing', () {
    test('preserves legitimate repeated words and structured annotations', () {
      expect(
        TextSanitizer.clean(
          'It was very very important (see Appendix A) [Figure 1].',
        ),
        contains('very very'),
      );
      expect(
        TextSanitizer.clean('It was had had in the source [Figure 1].'),
        contains('had had'),
      );
      expect(TextSanitizer.clean('[Music] Hello'), 'Hello');
    });

    test('retains every imported page before an explicit exercise heading', () {
      const markdown = '''
# Article
Page one.

---

Page two.

---

Page three.

## 📝 练习
Question 1
''';
      final article = ReadingContentParser.extractArticle(markdown);
      expect(article, contains('Page one.'));
      expect(article, contains('Page two.'));
      expect(article, contains('Page three.'));
      expect(article, isNot(contains('Question 1')));
    });

    test('does not truncate title-less multi-page content', () {
      const markdown = 'First page\n\n---\n\nSecond page';
      expect(
        ReadingContentParser.extractArticle(markdown),
        contains('Second page'),
      );
    });
  });

  group('Stage 9 audio recorder adapter', () {
    test('fake adapter models permission, start, stop and disposal', () async {
      final adapter = FakeAudioRecorderAdapter(stopPath: '/tmp/audio.wav');
      expect(await adapter.hasPermission(), isTrue);
      await adapter.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: '/tmp/audio.wav',
      );
      expect(adapter.isRecording, isTrue);
      expect(await adapter.stop(), '/tmp/audio.wav');
      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });
  });
}
