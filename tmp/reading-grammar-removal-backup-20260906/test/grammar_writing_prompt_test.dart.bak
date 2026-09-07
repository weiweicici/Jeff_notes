import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/prompt_provider.dart';
import 'package:jeff_notes/services/grammar_service.dart';

const _pastTense = GrammarUnit(
  id: 'past',
  title: 'Simple Past',
  outcomes: '',
  chart: '',
  chineseGuide: '',
  keyRules: 'Use the past form for a finished action.',
  commonMistakes: '',
  vocabulary: '',
);

const _relativeClause = GrammarUnit(
  id: 'relative',
  title: 'Adjective Clauses',
  outcomes: '',
  chart: '',
  chineseGuide: '',
  keyRules: 'Use who, which, or that to add information.',
  commonMistakes: '',
  vocabulary: '',
);

const _tensePart = GrammarPart(
  id: 'part_tense',
  title: 'Tenses',
  units: [_pastTense],
);

const _clausePart = GrammarPart(
  id: 'part_clause',
  title: 'Clauses',
  units: [_relativeClause],
);

const _allParts = [_tensePart, _clausePart];

void main() {
  group('Combined grammar writing prompt', () {
    test('requires a clean three-paragraph essay under 200 words', () {
      final prompt = PromptProvider.getCombinedWritingPrompt(
        availableParts: _allParts,
        selectedParts: const [],
        selectedUnits: const [_pastTense, _relativeClause],
      );

      expect(prompt, contains('英文正文不超过 200 个英文单词'));
      expect(prompt, contains('正文必须恰好三段'));
      expect(prompt, contains('Introduction、Body 1、Conclusion'));
      expect(prompt, contains('不要在正文中显示 Introduction、Body 1、Conclusion'));
      expect(prompt, contains('不要输出中文翻译、语法标注'));
      expect(prompt, contains('A2–B1'));
      expect(prompt, contains('语法可以复杂，但词汇必须简单'));
      expect(prompt, contains('把可以简化的难词换成常用词'));
      expect(prompt, isNot(contains('## 中文翻译')));
      expect(prompt, isNot(contains('## 语法标注')));
    });

    test('allows every selected grammar to appear anywhere in the essay', () {
      final prompt = PromptProvider.getCombinedWritingPrompt(
        availableParts: _allParts,
        selectedParts: const [_tensePart],
        selectedUnits: const [_relativeClause],
      );

      expect(prompt, contains('指定语法可以分布在全文任何段落'));
      expect(prompt, contains('已选章节只提供额外的可选范围'));
      expect(prompt, contains('每个已选具体语法至少正确使用一次'));
      expect(prompt, contains('一句话可以同时使用多项语法'));
      expect(prompt, contains('语法覆盖按“目标语法是否自然出现”计数'));
      expect(prompt, contains('也可能只是若干关键词或简短要求'));
      expect(prompt, contains('主题方向和内容偏好'));
      expect(prompt, contains('不要求把每个词机械地逐字写入正文'));
      expect(prompt, contains('只有输入明确出现“必须、至少'));
      expect(prompt, contains('内部构思模板'));
      expect(prompt, contains('背景—主要事件—结果/影响'));
      expect(prompt, contains('绝不能为了触发某项语法而添加无关'));
      expect(prompt, isNot(contains('Banff')));
      expect(prompt, isNot(contains('garage sale')));
      expect(prompt, contains(_tensePart.title));
      expect(prompt, contains(_pastTense.title));
      expect(prompt, contains(_relativeClause.title));
      expect(prompt, contains(_relativeClause.keyRules));
    });

    test('treats more than six exact grammar choices as a usable pool', () {
      const extra1 = GrammarUnit(
        id: 'extra1',
        title: 'Extra 1',
        outcomes: '',
        chart: '',
        chineseGuide: '',
        keyRules: 'Rule 1',
        commonMistakes: '',
        vocabulary: '',
      );
      const extra2 = GrammarUnit(
        id: 'extra2',
        title: 'Extra 2',
        outcomes: '',
        chart: '',
        chineseGuide: '',
        keyRules: 'Rule 2',
        commonMistakes: '',
        vocabulary: '',
      );
      const extra3 = GrammarUnit(
        id: 'extra3',
        title: 'Extra 3',
        outcomes: '',
        chart: '',
        chineseGuide: '',
        keyRules: 'Rule 3',
        commonMistakes: '',
        vocabulary: '',
      );
      const extra4 = GrammarUnit(
        id: 'extra4',
        title: 'Extra 4',
        outcomes: '',
        chart: '',
        chineseGuide: '',
        keyRules: 'Rule 4',
        commonMistakes: '',
        vocabulary: '',
      );
      const extra5 = GrammarUnit(
        id: 'extra5',
        title: 'Extra 5',
        outcomes: '',
        chart: '',
        chineseGuide: '',
        keyRules: 'Rule 5',
        commonMistakes: '',
        vocabulary: '',
      );

      final prompt = PromptProvider.getCombinedWritingPrompt(
        availableParts: _allParts,
        selectedParts: const [],
        selectedUnits: const [
          _pastTense,
          _relativeClause,
          extra1,
          extra2,
          extra3,
          extra4,
          extra5,
        ],
      );

      expect(prompt, contains('用户选了 7 个具体语法'));
      expect(prompt, contains('从中选择最适合题目的 4–6 项'));
      expect(prompt, isNot(contains('每个已选具体语法至少正确使用一次')));
      expect(prompt, isNot(contains('Rule 1')));
      expect(prompt, contains('Extra 1'));
    });

    test(
      'can require every selected grammar when the teacher specifies it',
      () {
        const extra1 = GrammarUnit(
          id: 'required1',
          title: 'Required 1',
          outcomes: '',
          chart: '',
          chineseGuide: '',
          keyRules: 'Rule 1',
          commonMistakes: '',
          vocabulary: '',
        );
        const extra2 = GrammarUnit(
          id: 'required2',
          title: 'Required 2',
          outcomes: '',
          chart: '',
          chineseGuide: '',
          keyRules: 'Rule 2',
          commonMistakes: '',
          vocabulary: '',
        );
        const extra3 = GrammarUnit(
          id: 'required3',
          title: 'Required 3',
          outcomes: '',
          chart: '',
          chineseGuide: '',
          keyRules: 'Rule 3',
          commonMistakes: '',
          vocabulary: '',
        );
        const extra4 = GrammarUnit(
          id: 'required4',
          title: 'Required 4',
          outcomes: '',
          chart: '',
          chineseGuide: '',
          keyRules: 'Rule 4',
          commonMistakes: '',
          vocabulary: '',
        );
        const extra5 = GrammarUnit(
          id: 'required5',
          title: 'Required 5',
          outcomes: '',
          chart: '',
          chineseGuide: '',
          keyRules: 'Rule 5',
          commonMistakes: '',
          vocabulary: '',
        );

        final prompt = PromptProvider.getCombinedWritingPrompt(
          availableParts: _allParts,
          selectedParts: const [],
          selectedUnits: const [
            _pastTense,
            _relativeClause,
            extra1,
            extra2,
            extra3,
            extra4,
            extra5,
          ],
          requireAllSelectedGrammar: true,
        );

        expect(prompt, contains('老师要求所有 7 个已选具体语法都至少正确使用一次'));
        expect(prompt, isNot(contains('不要强行覆盖全部')));
      },
    );

    test('combines typed topic, preset type, chapter, and exact grammar', () {
      const topic = 'Describe an important activity in your community.';
      final message = GrammarService.buildCombinedWritingUserMessage(
        selectedParts: const [_tensePart],
        selectedUnits: const [_relativeClause],
        topic: topic,
        contentType: 'an activity or daily routine',
      );

      expect(message, contains(topic));
      expect(message, contains('可能是完整原题、关键词或简短要求'));
      expect(message, contains('an activity or daily routine'));
      expect(message, contains(_tensePart.title));
      expect(message, contains(_relativeClause.title));
      expect(message, contains('内容类型只能补充题目'));
    });

    test('preset type works without typed topic or selected grammar', () {
      final message = GrammarService.buildCombinedWritingUserMessage(
        selectedParts: const [],
        selectedUnits: const [],
        topic: '',
        contentType: 'a place',
      );

      expect(message, contains('a place'));
      expect(message, contains('自动选择 4–6 种'));
    });

    test(
      'all empty selections fall back to an automatic topic and grammar',
      () {
        final message = GrammarService.buildCombinedWritingUserMessage(
          selectedParts: const [],
          selectedUnits: const [],
          topic: '',
        );
        final prompt = PromptProvider.getCombinedWritingPrompt(
          availableParts: _allParts,
          selectedParts: const [],
          selectedUnits: const [],
        );

        expect(message, contains('没有指定题目或内容类型'));
        expect(message, contains('自动选择 4–6 种'));
        expect(prompt, contains('用户没有指定语法'));
        expect(prompt, contains('自动选择 4–6 种'));
      },
    );
  });
}
