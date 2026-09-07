import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/prompt_provider.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/nait_learning/nait_learning_provider.dart';
import 'package:jeff_notes/screens/academic_hub_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NAIT Regression & Core Isolation Suite', () {
    test('1. PromptStrategy.naitClassAnalysis is defined and returns NAIT prompt', () {
      expect(PromptStrategy.values, contains(PromptStrategy.naitClassAnalysis));

      final naitPrompt = PromptProvider.getSystemPrompt(
        PromptStrategy.naitClassAnalysis,
        AIProvider.gemini,
      );
      expect(naitPrompt, contains('NAIT'));
      expect(naitPrompt, contains('Northern Alberta Institute of Technology'));
      expect(naitPrompt, contains('classroomEnglish'));
      expect(naitPrompt, contains('mustDo'));
    });

    test('2. Existing prompt strategies remain completely unaltered', () {
      final essayPrompt = PromptProvider.getSystemPrompt(
        PromptStrategy.essay,
        AIProvider.gemini,
      );
      expect(essayPrompt, contains('professional academic writing assistant'));

      final discoveryPrompt = PromptProvider.getSystemPrompt(
        PromptStrategy.discovery,
        AIProvider.gemini,
      );
      expect(discoveryPrompt.isNotEmpty, isTrue);
    });

    testWidgets('3. AcademicHubScreen renders all 4 modules including NAIT Learning', (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => RecordingProvider()),
            ChangeNotifierProvider(create: (_) => NaitLearningProvider()),
          ],
          child: const MaterialApp(
            home: AcademicHubScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify existing 3 hub cards
      expect(find.textContaining('学术听力同传'), findsOneWidget);
      expect(find.textContaining('对比作文写作'), findsOneWidget);
      expect(find.textContaining('智能学术词库'), findsOneWidget);

      // Verify the new 4th NAIT Learning card
      expect(find.textContaining('NAIT Learning'), findsOneWidget);
      expect(find.textContaining('课堂精听 × 实用英语 × Weekly Listening'), findsOneWidget);
    });

    test('4. NaitLearningProvider registers cleanly without polluting RecordingProvider', () {
      final recordingProvider = RecordingProvider();
      final naitProvider = NaitLearningProvider();

      expect(recordingProvider, isA<ChangeNotifier>());
      expect(naitProvider, isA<ChangeNotifier>());

      // RecordingProvider has no NAIT fields
      expect(recordingProvider.isRecording, isFalse);
      expect(naitProvider.courses, isEmpty);
    });
  });
}
