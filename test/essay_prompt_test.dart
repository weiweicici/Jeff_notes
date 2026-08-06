import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/screens/essay_config_screen.dart';

void main() {
  group('Essay topic interpretation', () {
    test('user meaning takes priority over structure and preferred aspects', () {
      final rules = RecordingProvider.buildEssayTopicPriorityRules();

      expect(rules, contains('USER TOPIC HAS CONTENT PRIORITY'));
      expect(rules, contains('primary source of meaning'));
      expect(rules, contains('silently reconstruct'));
      expect(rules, contains('without distorting that topic'));
    });

    test('incomplete topic examples are reconstructed naturally', () {
      final rules = RecordingProvider.buildEssayTopicPriorityRules();

      expect(rules, contains('subsidy school lunches'));
      expect(
        rules,
        contains('Should students be provided with subsidized school lunches?'),
      );
      expect(rules, contains('required wear a helmets'));
      expect(
        rules,
        contains('Should bicycle riders be required to wear helmets?'),
      );
    });
  });

  group('Essay type routing', () {
    test('comparison mode recognizes common forms without choosing a winner', () {
      final rules = RecordingProvider.buildComparisonTopicRoutingRules();

      expect(rules, contains('NORMALIZE INPUT AS A COMPARISON ESSAY'));
      expect(rules, contains('compare, contrast, distinguish'));
      expect(rules, contains('A vs. B'));
      expect(rules, contains('If two subjects are named'));
      expect(rules, contains('not as an instruction to choose a winner'));
      expect(rules, contains('Never turn the result into a recommendation'));
    });

    test('argumentative mode recognizes common forms and requires a position', () {
      final rules = RecordingProvider.buildArgumentativeTopicRoutingRules();

      expect(rules, contains('NORMALIZE INPUT AS AN ARGUMENTATIVE ESSAY'));
      expect(rules, contains('should, should not, must, require'));
      expect(rules, contains('Do you agree or disagree?'));
      expect(rules, contains('advantages outweigh disadvantages'));
      expect(rules, contains('take a clear position'));
      expect(rules, contains('opposing view followed by refutation'));
    });
  });

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
        contains(
          'are similar in terms of the three chosen practical aspects',
        ),
      );
      expect(prompt, contains('Never force an awkward connection'));
      expect(prompt, contains('USER TOPIC HAS CONTENT PRIORITY'));
      expect(prompt, contains('NORMALIZE INPUT AS A COMPARISON ESSAY'));
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
        contains(
          'exactly three suitable aspects are chosen and used in the same order throughout',
        ),
      );
      expect(prompt, contains('does not choose a winner'));
      expect(
        prompt,
        contains(
          'are different in terms of the three chosen practical aspects',
        ),
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
    expect(rules, contains('remaining third chosen aspect'));
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

  group('Preset topic search', () {
    test('searches all preset topics in English and Chinese', () {
      expect(presetTopicCount, greaterThan(40));
      expect(
        searchPresetTopics('helmet').first.preset.chineseLabel,
        '戴头盔 vs 不戴头盔',
      );
      expect(
        searchPresetTopics('头盔').first.preset.topic,
        contains('bicycle helmets'),
      );
    });

    test('ranks incomplete assignment wording by matching keywords', () {
      expect(
        searchPresetTopics('subsidy school lunches').first.preset.topic,
        'Free school lunches vs. Paid school lunches',
      );
      expect(
        searchPresetTopics('required wear a helmets').first.preset.topic,
        'Wearing bicycle helmets vs. Not wearing bicycle helmets',
      );
    });

    test('empty queries stay available for unrestricted custom input', () {
      expect(searchPresetTopics(''), isEmpty);
      expect(searchPresetTopics('a'), isEmpty);
    });
  });
}
