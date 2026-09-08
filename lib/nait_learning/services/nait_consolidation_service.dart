import 'dart:math';
import '../models/nait_class_analysis.dart';
import '../models/nait_english_chunk.dart';
import '../models/nait_teacher_mode_task.dart';

/// Pure Dart deterministic consolidation service for merging multi-chunk extractions.
class NaitConsolidationService {
  const NaitConsolidationService();

  /// Consolidates multiple per-chunk [NaitClassAnalysis] objects into one unified [NaitClassAnalysis].
  NaitClassAnalysis consolidate({
    required List<NaitClassAnalysis> chunkAnalyses,
    String courseId = '',
    String sessionId = '',
    int weekNumber = 1,
  }) {
    if (chunkAnalyses.isEmpty) {
      return const NaitClassAnalysis();
    }
    if (chunkAnalyses.length == 1) {
      return chunkAnalyses.first;
    }

    final mustDo = _deduplicateStrings(chunkAnalyses.expand((a) => a.mustDo).toList());
    final lab = _consolidateLabSteps(chunkAnalyses.expand((a) => a.lab).toList());
    final important = _deduplicateStrings(chunkAnalyses.expand((a) => a.important).toList());
    final nextClass = _deduplicateStrings(chunkAnalyses.expand((a) => a.nextClass).toList());
    final technicalPoints = _deduplicateStrings(chunkAnalyses.expand((a) => a.technicalPoints).toList());

    final classroomEnglish = _consolidateClassroomEnglish(
      chunkAnalyses.expand((a) => a.classroomEnglish).toList(),
      courseId: courseId,
      sessionId: sessionId,
      weekNumber: weekNumber,
    );

    final askTeacher = _deduplicatePracticeItems(
      chunkAnalyses.expand((a) => a.askTeacher).toList(),
      maxItems: 6,
    );

    final classmateEnglish = _deduplicatePracticeItems(
      chunkAnalyses.expand((a) => a.classmateEnglish).toList(),
      maxItems: 6,
    );

    final teacherMode = _synthesizeTeacherMode(
      chunkAnalyses: chunkAnalyses,
      technicalPoints: technicalPoints,
      classroomEnglish: classroomEnglish,
    );

    return NaitClassAnalysis(
      mustDo: mustDo,
      lab: lab,
      important: important,
      nextClass: nextClass,
      technicalPoints: technicalPoints,
      classroomEnglish: classroomEnglish,
      askTeacher: askTeacher,
      classmateEnglish: classmateEnglish,
      teacherMode: teacherMode,
    );
  }

  /// Deduplicates string items across chunks while strictly preserving distinct operational details.
  List<String> _deduplicateStrings(List<String> items) {
    final List<String> result = [];

    for (final rawItem in items) {
      final item = rawItem.trim();
      if (item.isEmpty) continue;

      var duplicateFound = false;
      for (int i = 0; i < result.length; i++) {
        final existing = result[i];
        if (_areStringsNearDuplicates(existing, item)) {
          duplicateFound = true;
          // Keep the more detailed / longer string
          if (item.length > existing.length + 5) {
            result[i] = item;
          }
          break;
        }
      }

      if (!duplicateFound) {
        result.add(item);
      }
    }

    return result;
  }

  /// Consolidates procedural lab steps preserving chronological sequence.
  List<String> _consolidateLabSteps(List<String> rawSteps) {
    final List<String> result = [];

    for (final raw in rawSteps) {
      final step = raw.trim();
      if (step.isEmpty) continue;

      var isDup = false;
      for (int i = 0; i < result.length; i++) {
        if (_areStringsNearDuplicates(result[i], step)) {
          isDup = true;
          if (step.length > result[i].length) {
            result[i] = step;
          }
          break;
        }
      }
      if (!isDup) {
        result.add(step);
      }
    }

    return result;
  }

  /// Consolidates classroom English phrases:
  /// - Exact phrases at distant timestamps increment appearance count & boost priority.
  /// - Overlap duplicates (<90s apart) are merged cleanly without artificial count inflation.
  List<NaitEnglishChunk> _consolidateClassroomEnglish(
    List<NaitEnglishChunk> chunks, {
    required String courseId,
    required String sessionId,
    required int weekNumber,
  }) {
    final Map<String, NaitEnglishChunk> consolidated = {};
    int nextId = 1;

    for (final chunk in chunks) {
      final normPhrase = chunk.phrase.trim().toLowerCase();
      if (normPhrase.isEmpty) continue;

      if (!consolidated.containsKey(normPhrase)) {
        consolidated[normPhrase] = NaitEnglishChunk(
          id: '${sessionId}_chunk_${nextId++}',
          phrase: chunk.phrase.trim(),
          chineseMeaning: chunk.chineseMeaning.trim(),
          context: chunk.context.trim(),
          courseId: courseId,
          classSessionId: sessionId,
          weekNumber: weekNumber,
          sourceTimestamp: chunk.sourceTimestamp,
          audioStart: chunk.audioStart,
          audioEnd: chunk.audioEnd,
          priority: chunk.priority,
          sourceType: 'teacher_original',
          appearanceCount: 1,
        );
      } else {
        final existing = consolidated[normPhrase]!;
        final t1 = existing.sourceTimestamp ?? existing.audioStart ?? Duration.zero;
        final t2 = chunk.sourceTimestamp ?? chunk.audioStart ?? Duration.zero;
        final timeDiff = (t1 - t2).abs();

        // If time difference > 90 seconds, this is a genuine re-occurrence across class
        if (timeDiff > const Duration(seconds: 90)) {
          existing.appearanceCount += 1;
          existing.priority = min(5, existing.priority + 1);
          // Retain the longer / richer context sentence
          if (chunk.context.length > existing.context.length) {
            existing.context = chunk.context.trim();
          }
          if (chunk.chineseMeaning.isNotEmpty && existing.chineseMeaning.isEmpty) {
            existing.chineseMeaning = chunk.chineseMeaning.trim();
          }
        } else {
          // Overlap boundary artifact: keep the cleaner audio clip boundary if available
          if (existing.audioStart == null && chunk.audioStart != null) {
            existing.audioStart = chunk.audioStart;
            existing.audioEnd = chunk.audioEnd;
            existing.sourceTimestamp = chunk.sourceTimestamp ?? existing.sourceTimestamp;
          }
        }
      }
    }

    final result = consolidated.values.toList();
    // Sort by priority descending, then timestamp ascending
    result.sort((a, b) {
      final pCmp = b.priority.compareTo(a.priority);
      if (pCmp != 0) return pCmp;
      final tA = a.sourceTimestamp ?? Duration.zero;
      final tB = b.sourceTimestamp ?? Duration.zero;
      return tA.compareTo(tB);
    });

    return result;
  }

  /// Deduplicates practice sentences, guaranteeing sourceType = 'practice_sentence'.
  List<NaitPracticeItem> _deduplicatePracticeItems(
    List<NaitPracticeItem> items, {
    int maxItems = 6,
  }) {
    final List<NaitPracticeItem> result = [];
    final Set<String> seen = {};

    for (final item in items) {
      final text = item.text.trim();
      if (text.isEmpty) continue;
      final norm = text.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '');
      if (seen.contains(norm)) continue;

      seen.add(norm);
      result.add(NaitPracticeItem(
        text: text,
        sourceType: 'practice_sentence', // Invariant: always practice_sentence
      ));

      if (result.length >= maxItems) break;
    }

    return result;
  }

  /// Synthesizes a class-level Teacher Mode task from chunk extractions.
  NaitTeacherModeTask? _synthesizeTeacherMode({
    required List<NaitClassAnalysis> chunkAnalyses,
    required List<String> technicalPoints,
    required List<NaitEnglishChunk> classroomEnglish,
  }) {
    // 1. Look for an existing teacherMode produced by a chunk
    for (final a in chunkAnalyses) {
      if (a.teacherMode != null && a.teacherMode!.prompt.trim().isNotEmpty) {
        return a.teacherMode;
      }
    }

    // 2. Synthesize from prominent technicalPoints and top phrases
    if (technicalPoints.isNotEmpty) {
      final primaryTopic = technicalPoints.first;
      final topChunks = classroomEnglish.take(3).map((c) => c.phrase).toList();
      return NaitTeacherModeTask(
        prompt: 'Explain the core concept of today: $primaryTopic to a peer.',
        suggestedOpening: 'In today\'s session, the key procedure revolves around $primaryTopic...',
        targetChunks: topChunks,
      );
    }

    return null;
  }

  /// Helper to detect near-duplicate sentences (Overlap coefficient or Jaccard word similarity).
  static bool _areStringsNearDuplicates(String a, String b) {
    if (a == b) return true;

    final normA = a.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    final normB = b.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), ' ').trim();

    if (normA == normB) return true;
    if (normA.contains(normB) || normB.contains(normA)) return true;

    final wordsA = normA.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();
    final wordsB = normB.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toSet();

    if (wordsA.isEmpty || wordsB.isEmpty) return false;

    final intersection = wordsA.intersection(wordsB).length;
    final minLen = min(wordsA.length, wordsB.length);
    final union = wordsA.union(wordsB).length;

    if (minLen == 0 || union == 0) return false;

    final overlap = intersection / minLen;
    final jaccard = intersection / union;

    return overlap >= 0.70 || jaccard >= 0.55;
  }
}
