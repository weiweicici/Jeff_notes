import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/screens/essay_config_screen.dart';

void main() {
  group('Comparison-contrast prompt routing', () {
    test('similarities mode keeps all body paragraphs similarity-only', () {
      final prompt = RecordingProvider.buildComparisonEssayPrompt(
        'Similarities',
      );

      expect(prompt, contains('SIMILARITIES ONLY'));
      expect(
        prompt,
        contains('The entire essay must compare similarities only'),
      );
      expect(prompt, contains('Body 1 and Body 2 must each include one'));
      expect(prompt, contains('Do NOT mix similarities and differences'));
      expect(
        prompt,
        contains('are similar in terms of cost, time, and happiness'),
      );
    });

    test('differences mode keeps all body paragraphs difference-only', () {
      final prompt = RecordingProvider.buildComparisonEssayPrompt(
        'Differences',
      );

      expect(prompt, contains('DIFFERENCES ONLY'));
      expect(
        prompt,
        contains('The entire essay must compare differences only'),
      );
      expect(
        prompt,
        contains('Cost, Time, and Happiness are used in that order'),
      );
      expect(prompt, contains('does not choose a winner'));
      expect(
        prompt,
        contains('are different in terms of cost, time, and happiness'),
      );
      expect(
        prompt,
        contains('select two widely familiar subjects from the same category'),
      );
    });

    test('missing focus fails closed to differences prompt', () {
      final prompt = RecordingProvider.buildComparisonEssayPrompt(null);

      expect(prompt, contains('DIFFERENCES ONLY'));
      expect(prompt, isNot(contains('SIMILARITIES ONLY')));
    });
  });

  test('argumentative Body 3 is the longer concession-refutation section', () {
    final rules = RecordingProvider.buildArgumentativeBody3Rules();

    expect(rules, contains('5-7 Sentences'));
    expect(rules, contains('most important body paragraph'));
    expect(rules, contains('Present one clear opposing view'));
    expect(rules, contains('Acknowledge a limited part'));
    expect(rules, contains('state the main refutation clearly'));
    expect(rules, contains('Sentence 7 (Optional)'));
  });

  group('Practiced essay presets', () {
    test('comparison practice category contains all remembered topics', () {
      final topics = presetTopicsByCategory[EssayCategory.practicedComparison]!;
      final labels = topics.map((topic) => topic.chineseLabel).toSet();

      expect(topics, hasLength(6));
      expect(
        labels,
        containsAll({
          '两位电影明星',
          '两位歌星',
          '两位喜剧演员',
          '温哥华和香港',
          'New Year和农历新年',
          'AI自选同类主题',
        }),
      );
    });

    test('remembered argumentative topics already exist in presets', () {
      final topics = presetTopicsByCategory.values
          .expand((categoryTopics) => categoryTopics)
          .map((topic) => topic.topic)
          .toList();

      expect(topics, contains('Wearing face masks vs. Not wearing face masks'));
      expect(
        topics,
        contains('Wearing bicycle helmets vs. Not wearing bicycle helmets'),
      );
      expect(topics, contains('Free school lunches vs. Paid school lunches'));
      expect(topics, contains('Wearing school uniforms vs. Casual dress code'));
      expect(
        topics,
        contains(
          'Banning smartphones in school vs. Allowing smartphones in school',
        ),
      );
    });
  });
}
