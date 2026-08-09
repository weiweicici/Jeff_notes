import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/data/grammar_content.dart';
import 'package:jeff_notes/screens/grammar_writing_screen.dart';
import 'package:jeff_notes/services/grammar_repository.dart';
import 'package:jeff_notes/services/grammar_writing_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    GrammarWritingDraftService.instance.resetForTesting();
    GrammarRepository.setCachedPartsForTesting(GrammarContent.parts);
  });

  tearDown(() {
    GrammarRepository.setCachedPartsForTesting(null);
  });

  test('archive filename uses the topic and always stays within iOS limit', () {
    final filename = buildGrammarArchiveFilename(
      topic: List.filled(100, '买单车 shopping garage sale').join(' '),
      dateStamp: '20260807_2232',
    );

    expect(filename, startsWith('Jeff_Grammar_买单车_shopping_garage_sale'));
    expect(utf8.encode(filename).length, lessThanOrEqualTo(255));
    expect(filename, endsWith('_20260807_2232.md'));
  });

  testWidgets('writing screen opens in combined practice mode', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GrammarWritingScreen()));
    await tester.pumpAndSettle();

    final modeToggle = tester.widget<SegmentedButton<bool>>(
      find.byType(SegmentedButton<bool>),
    );
    expect(modeToggle.selected, {true});
    expect(find.byKey(const ValueKey('combinedWritingTopic')), findsOneWidget);
    expect(find.text('快捷主题（可选）'), findsOneWidget);
    expect(find.text('活动/日常'), findsOneWidget);
    expect(find.text('经历'), findsOneWidget);
    expect(find.text('物品/事物'), findsOneWidget);
    expect(find.text('计划/目标'), findsOneWidget);
    expect(find.text('问题/建议'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('选择语法（可选）'), findsOneWidget);
    expect(find.text('选择章节（Part）'), findsNothing);
  });

  testWidgets('watch topic is copied into combined writing input', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GrammarWritingScreen(initialTopic: 'shopping garage sale'),
      ),
    );
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('combinedWritingTopic')),
    );
    expect(field.controller?.text, 'shopping garage sale');
  });

  testWidgets(
    'phone combined grammar choices persist for a later watch launch',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GrammarWritingScreen()));
      await tester.pumpAndSettle();

      final partCheckbox = find.byKey(
        const ValueKey('combinedPartCheckbox_part_1'),
      );
      await tester.ensureVisible(partCheckbox);
      await tester.tap(partCheckbox);
      await tester.pumpAndSettle();
      final activityTheme = find.text('活动/日常');
      await tester.ensureVisible(activityTheme);
      await tester.tap(activityTheme);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        const MaterialApp(
          home: GrammarWritingScreen(initialTopic: 'teacher topic'),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<Checkbox>(partCheckbox).value, isTrue);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '活动/日常'))
            .selected,
        isTrue,
      );
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('combinedWritingTopic')),
      );
      expect(field.controller?.text, 'teacher topic');
    },
  );

  testWidgets('quick preset can generate without a typed topic', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: GrammarWritingScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('活动/日常'));
    await tester.pump();
    final generateButton = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, '🚀 生成范文'),
    );
    expect(generateButton.onPressed, isNotNull);
  });

  testWidgets(
    'combined generation allows every empty or selected combination',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GrammarWritingScreen()));
      await tester.pumpAndSettle();

      final generateFinder = find.widgetWithText(ElevatedButton, '🚀 生成范文');
      expect(
        tester.widget<ElevatedButton>(generateFinder).onPressed,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey('combinedWritingTopic')),
        'Describe an important activity in your community.',
      );
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(generateFinder).onPressed,
        isNotNull,
      );

      final partCheckbox = find.byKey(
        const ValueKey('combinedPartCheckbox_part_1'),
      );
      await tester.ensureVisible(partCheckbox);
      await tester.pumpAndSettle();
      await tester.tap(partCheckbox);
      await tester.pump();
      expect(
        tester.widget<ElevatedButton>(generateFinder).onPressed,
        isNotNull,
      );
    },
  );

  testWidgets('single-part practice remains available', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GrammarWritingScreen()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('单章练习'));
    await tester.pumpAndSettle();

    expect(find.text('选择章节（Part）'), findsOneWidget);
    expect(find.text('选择具体单元（可选，不选则不限）'), findsOneWidget);
    expect(find.text('选择主题大类'), findsOneWidget);
    expect(find.text('活动/日常'), findsOneWidget);
    expect(find.text('问题/建议'), findsOneWidget);
    expect(find.byKey(const ValueKey('combinedWritingTopic')), findsNothing);
  });
}
