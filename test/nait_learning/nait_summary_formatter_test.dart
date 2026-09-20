import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_analysis.dart';
import 'package:jeff_notes/nait_learning/models/nait_english_chunk.dart';
import 'package:jeff_notes/nait_learning/models/nait_teacher_mode_task.dart';
import 'package:jeff_notes/nait_learning/services/nait_summary_formatter.dart';

void main() {
  group('NaitSummaryFormatter', () {
    final testAnalysis = NaitClassAnalysis(
      mustDo: [
        'Assignment 1 due Friday 11:59 PM via Moodle',
        'Install Windows Server 2022 on VMNet4',
      ],
      lab: [
        'Step 1: Set VM network adapter to NAT',
        'Step 2: Run Windows Update',
      ],
      important: [
        'Do NOT sysprep the primary domain controller VM',
      ],
      nextClass: [
        'Bring completed DC setup to class on Thursday',
      ],
      technicalPoints: [
        'DNS reverse lookup zone requirement for Kerberos ticket resolution',
      ],
      classroomEnglish: [
        NaitEnglishChunk(
          id: 'chunk_1',
          phrase: 'leave it at the default',
          chineseMeaning: '保持默认设置，不要改动',
          context: 'When installing IIS, you can just leave it at the default.',
          priority: 5,
          sourceType: 'teacher_original',
          sourceTimestamp: const Duration(minutes: 23, seconds: 10),
        ),
      ],
      askTeacher: [
        const NaitPracticeItem(
          text: 'Are we supposed to keep the default subnet mask for this lab?',
          sourceType: 'practice_sentence',
        ),
      ],
      classmateEnglish: [
        const NaitPracticeItem(
          text: 'Did you get the second network adapter showing up in your VM?',
          sourceType: 'practice_sentence',
        ),
      ],
      teacherMode: const NaitTeacherModeTask(
        prompt: 'Explain the difference between Workgroup and Active Directory Domain.',
        suggestedOpening: 'So the fundamental difference comes down to centralized authentication...',
        targetChunks: ['centralized management', 'single point of failure'],
      ),
    );

    test('format generates all essential sections in Markdown', () {
      final markdown = NaitSummaryFormatter.format(
        analysis: testAnalysis,
        courseCode: 'ANIT101',
        weekNumber: 1,
        classDate: DateTime(2026, 9, 4),
      );

      expect(markdown, contains('# ANIT101 — Week 1 (September 4, 2026)'));
      expect(markdown, contains('## Must Do'));
      expect(markdown, contains('- [ ] Assignment 1 due Friday 11:59 PM via Moodle'));
      expect(markdown, contains('## Lab & Practical Procedures'));
      expect(markdown, contains('1. Step 1: Set VM network adapter to NAT'));
      expect(markdown, contains('## Important Warnings & Pitfalls'));
      expect(markdown, contains('> **Warning**: Do NOT sysprep the primary domain controller VM'));
      expect(markdown, contains('## Technical Highlights'));
      expect(markdown, contains('- DNS reverse lookup zone requirement'));
      expect(markdown, contains('## Next Class Preparation'));
      expect(markdown, contains('- Bring completed DC setup'));
      expect(markdown, contains('## Classroom English'));
      expect(markdown, contains('### leave it at the default'));
      expect(markdown, contains('**Chinese Meaning**: 保持默认设置，不要改动'));
      expect(markdown, contains('**Priority**: ★★★★★'));
      expect(markdown, contains('## Spoken Practice'));
      expect(markdown, contains('## Teacher Mode (60s Teach-back)'));
    });

    test('writeSummaryFile writes file atomically to disk', () async {
      final tempDir = await Directory.systemTemp.createTemp('summary_test_');
      try {
        final summaryFile = File('${tempDir.path}/summary.md');
        await NaitSummaryFormatter.writeSummaryFile(
          analysis: testAnalysis,
          courseCode: 'ANIT101',
          weekNumber: 1,
          classDate: DateTime(2026, 9, 4),
          outputFile: summaryFile,
        );

        expect(await summaryFile.exists(), isTrue);
        final content = await summaryFile.readAsString();
        expect(content, contains('# ANIT101 — Week 1'));
        expect(content.length, greaterThan(100));
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
