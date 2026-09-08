import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_analysis.dart';
import 'package:jeff_notes/nait_learning/models/nait_english_chunk.dart';
import 'package:jeff_notes/nait_learning/services/nait_consolidation_service.dart';

void main() {
  group('NaitConsolidationService Tests', () {
    const service = NaitConsolidationService();

    test('1. Overlap duplicate ACTION removed while distinct ACTION preserved', () {
      final chunk1 = NaitClassAnalysis(
        mustDo: [
          'Assignment 1 due Friday 11:59 PM via Moodle',
          'Configure VMNet4 static IP 192.168.10.10',
        ],
        important: [
          'Always take snapshot before promoting DC',
        ],
      );

      final chunk2 = NaitClassAnalysis(
        mustDo: [
          // Near-duplicate from 90s overlap window
          'Assignment 1 is due this Friday 11:59 PM on Moodle',
          // New distinct action in chunk 2
          'Submit network topology diagram by Tuesday',
        ],
        important: [
          // Exact duplicate from overlap
          'Always take snapshot before promoting DC',
          // Distinct warning
          'Do NOT delete default Administrator account',
        ],
      );

      final consolidated = service.consolidate(
        chunkAnalyses: [chunk1, chunk2],
        courseId: 'c1',
        sessionId: 's1',
      );

      // Duplicate assignment should be deduplicated (expect 3 items total)
      expect(consolidated.mustDo.length, equals(3));
      expect(consolidated.mustDo.any((s) => s.contains('Assignment 1')), isTrue);
      expect(consolidated.mustDo.any((s) => s.contains('VMNet4')), isTrue);
      expect(consolidated.mustDo.any((s) => s.contains('topology diagram')), isTrue);

      // Important warnings: 1 duplicate removed, 1 distinct preserved
      expect(consolidated.important.length, equals(2));
      expect(consolidated.important.any((s) => s.contains('snapshot')), isTrue);
      expect(consolidated.important.any((s) => s.contains('Administrator account')), isTrue);
    });

    test('2. Lab steps are preserved in chronological order and duplicates removed', () {
      final chunk1 = NaitClassAnalysis(
        lab: [
          'Step 1: Set network adapter to NAT',
          'Step 2: Run Windows Update until clean',
        ],
      );

      final chunk2 = NaitClassAnalysis(
        lab: [
          // Duplicate from overlap
          'Step 2: Run Windows Update until clean',
          'Step 3: Switch adapter to VMNet4 and set IP',
          'Step 4: Install Active Directory Domain Services role',
        ],
      );

      final consolidated = service.consolidate(
        chunkAnalyses: [chunk1, chunk2],
        courseId: 'c1',
        sessionId: 's1',
      );

      expect(consolidated.lab.length, equals(4));
      expect(consolidated.lab[0], contains('NAT'));
      expect(consolidated.lab[1], contains('Windows Update'));
      expect(consolidated.lab[2], contains('VMNet4'));
      expect(consolidated.lab[3], contains('Active Directory Domain Services'));
    });

    test('3. Repeated classroom phrase at distant timestamps increases frequency and priority', () {
      final chunk1 = NaitClassAnalysis(
        classroomEnglish: [
          NaitEnglishChunk(
            id: 'c1',
            phrase: 'leave it at the default',
            chineseMeaning: '保持默认设置',
            context: 'When installing IIS, you can just leave it at the default.',
            priority: 2,
            sourceType: 'teacher_original',
            sourceTimestamp: const Duration(minutes: 12, seconds: 30),
            audioStart: const Duration(minutes: 12, seconds: 25),
            audioEnd: const Duration(minutes: 12, seconds: 40),
          ),
          NaitEnglishChunk(
            id: 'c2',
            phrase: 'up and running',
            chineseMeaning: '正常运转',
            context: 'Make sure your domain controller is up and running.',
            priority: 3,
            sourceType: 'teacher_original',
            sourceTimestamp: const Duration(minutes: 15),
          ),
        ],
      );

      final chunk2 = NaitClassAnalysis(
        classroomEnglish: [
          // Same phrase repeated 50 minutes later in class
          NaitEnglishChunk(
            id: 'c3',
            phrase: 'leave it at the default',
            chineseMeaning: '保持默认',
            context: 'For the database port configuration, leave it at the default.',
            priority: 2,
            sourceType: 'teacher_original',
            sourceTimestamp: const Duration(minutes: 62, seconds: 15),
            audioStart: const Duration(minutes: 62, seconds: 10),
            audioEnd: const Duration(minutes: 62, seconds: 25),
          ),
        ],
      );

      final consolidated = service.consolidate(
        chunkAnalyses: [chunk1, chunk2],
        courseId: 'c1',
        sessionId: 's1',
      );

      expect(consolidated.classroomEnglish.length, equals(2));
      final repeated = consolidated.classroomEnglish.firstWhere(
        (c) => c.phrase.toLowerCase() == 'leave it at the default',
      );

      // Appearance count incremented
      expect(repeated.appearanceCount, equals(2));
      // Priority boosted
      expect(repeated.priority, greaterThan(2));
      // Teacher original preserved
      expect(repeated.sourceType, equals('teacher_original'));
      expect(repeated.audioStart, isNotNull);
      expect(repeated.audioEnd, isNotNull);
    });

    test('4. Practice sentences are deduplicated and never become teacher_original', () {
      final chunk1 = NaitClassAnalysis(
        askTeacher: [
          NaitPracticeItem(
            text: 'Should we take a snapshot before promoting the DC?',
            sourceType: 'practice_sentence',
          ),
        ],
        classmateEnglish: [
          NaitPracticeItem(
            text: 'Did your VM connect to VMNet4 properly?',
            sourceType: 'practice_sentence',
          ),
        ],
      );

      final chunk2 = NaitClassAnalysis(
        askTeacher: [
          NaitPracticeItem(
            text: 'Should we take a snapshot before promoting the DC?',
            sourceType: 'practice_sentence',
          ),
          NaitPracticeItem(
            text: 'What is the deadline for lab assignment 1?',
            sourceType: 'practice_sentence',
          ),
        ],
      );

      final consolidated = service.consolidate(
        chunkAnalyses: [chunk1, chunk2],
        courseId: 'c1',
        sessionId: 's1',
      );

      expect(consolidated.askTeacher.length, equals(2));
      for (final item in consolidated.askTeacher) {
        expect(item.sourceType, equals('practice_sentence'));
        expect(item.sourceType, isNot('teacher_original'));
      }

      expect(consolidated.classmateEnglish.length, equals(1));
      expect(consolidated.classmateEnglish.first.sourceType, equals('practice_sentence'));
    });
  });
}
