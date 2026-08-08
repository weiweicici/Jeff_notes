import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/screens/essay_config_screen.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('typed topic stays unobstructed without autocomplete', (
    tester,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => RecordingProvider(),
        child: const MaterialApp(home: EssayConfigScreen()),
      ),
    );

    const typedTopic = 'A brand-new teacher-provided topic';
    final topicField = find.byKey(const ValueKey('essayTopicInput'));
    await tester.enterText(topicField, typedTopic);
    await tester.pump();

    expect(find.text('作文题目（输入优先）'), findsOneWidget);
    expect(find.text('有输入时直接使用输入内容；留空才使用下方预设'), findsOneWidget);
    expect(find.text(typedTopic), findsOneWidget);
    expect(find.byType(RawAutocomplete), findsNothing);

    final generateButton = find.widgetWithText(ElevatedButton, '生成作文');
    await tester.ensureVisible(generateButton);
    await tester.pumpAndSettle();
    expect(generateButton.hitTestable(), findsOneWidget);
  });
}
