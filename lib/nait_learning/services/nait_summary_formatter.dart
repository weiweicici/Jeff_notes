import 'dart:io';
import '../models/nait_class_analysis.dart';

class NaitSummaryFormatter {
  const NaitSummaryFormatter._();

  static String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  /// Generates clean, execution-focused GitHub Flavored Markdown from [NaitClassAnalysis].
  static String format({
    required NaitClassAnalysis analysis,
    required String courseCode,
    required int weekNumber,
    required DateTime classDate,
  }) {
    final buffer = StringBuffer();
    final dateStr = _formatDate(classDate);

    // Document Title
    buffer.writeln('# $courseCode — Week $weekNumber ($dateStr)');
    buffer.writeln();

    // 1. MUST DO
    if (analysis.mustDo.isNotEmpty) {
      buffer.writeln('## Must Do');
      for (final item in analysis.mustDo) {
        buffer.writeln('- [ ] $item');
      }
      buffer.writeln();
    }

    // 2. LAB & PRACTICAL PROCEDURES
    if (analysis.lab.isNotEmpty) {
      buffer.writeln('## Lab & Practical Procedures');
      for (int i = 0; i < analysis.lab.length; i++) {
        buffer.writeln('${i + 1}. ${analysis.lab[i]}');
      }
      buffer.writeln();
    }

    // 3. IMPORTANT WARNINGS & PITFALLS
    if (analysis.important.isNotEmpty) {
      buffer.writeln('## Important Warnings & Pitfalls');
      for (final warn in analysis.important) {
        buffer.writeln('> **Warning**: $warn');
        buffer.writeln();
      }
    }

    // 4. TECHNICAL HIGHLIGHTS
    if (analysis.technicalPoints.isNotEmpty) {
      buffer.writeln('## Technical Highlights');
      for (final pt in analysis.technicalPoints) {
        buffer.writeln('- $pt');
      }
      buffer.writeln();
    }

    // 5. NEXT CLASS PREPARATION
    if (analysis.nextClass.isNotEmpty) {
      buffer.writeln('## Next Class Preparation');
      for (final item in analysis.nextClass) {
        buffer.writeln('- $item');
      }
      buffer.writeln();
    }

    // 6. CLASSROOM ENGLISH (High-Value Expressions)
    if (analysis.classroomEnglish.isNotEmpty) {
      buffer.writeln('## Classroom English');
      buffer.writeln();
      for (final chunk in analysis.classroomEnglish) {
        buffer.writeln('### ${chunk.phrase}');
        if (chunk.chineseMeaning.isNotEmpty) {
          buffer.writeln('**Chinese Meaning**: ${chunk.chineseMeaning}  ');
        }
        if (chunk.context.isNotEmpty) {
          buffer.writeln('**Teacher Context**: *"${chunk.context}"*  ');
        }
        if (chunk.sourceTimestamp != null) {
          buffer.writeln('**Timestamp**: `${chunk.sourceTimestamp.toString().split('.').first}`  ');
        }
        buffer.writeln('**Priority**: ${'★' * chunk.priority.clamp(1, 5)}');
        buffer.writeln();
      }
    }

    // 7. SPOKEN PRACTICE (Ask Teacher & Classmates)
    if (analysis.askTeacher.isNotEmpty || analysis.classmateEnglish.isNotEmpty) {
      buffer.writeln('## Spoken Practice');
      if (analysis.askTeacher.isNotEmpty) {
        buffer.writeln('### Questions for the Teacher');
        for (final q in analysis.askTeacher) {
          buffer.writeln('- "$q"');
        }
        buffer.writeln();
      }
      if (analysis.classmateEnglish.isNotEmpty) {
        buffer.writeln('### Peer Interaction');
        for (final c in analysis.classmateEnglish) {
          buffer.writeln('- "$c"');
        }
        buffer.writeln();
      }
    }

    // 8. TEACHER MODE (60s Teach-back)
    if (analysis.teacherMode != null) {
      final tm = analysis.teacherMode!;
      buffer.writeln('## Teacher Mode (60s Teach-back)');
      buffer.writeln('**Prompt**: ${tm.prompt}  ');
      if (tm.suggestedOpening.isNotEmpty) {
        buffer.writeln('**Suggested Opening**: *"${tm.suggestedOpening}"*  ');
      }
      if (tm.targetChunks.isNotEmpty) {
        buffer.writeln('**Target Chunks**: `${tm.targetChunks.join('`, `')}`');
      }
      buffer.writeln();
    }

    return buffer.toString().trimRight();
  }

  /// Writes formatted summary to [outputFile] atomically.
  static Future<File> writeSummaryFile({
    required NaitClassAnalysis analysis,
    required String courseCode,
    required int weekNumber,
    required DateTime classDate,
    required File outputFile,
  }) async {
    final parent = outputFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final markdown = format(
      analysis: analysis,
      courseCode: courseCode,
      weekNumber: weekNumber,
      classDate: classDate,
    );

    final tmpFile = File('${outputFile.path}.tmp');
    await tmpFile.writeAsString(markdown, flush: true);
    if (await outputFile.exists()) {
      await outputFile.delete();
    }
    await tmpFile.rename(outputFile.path);

    return outputFile;
  }
}
