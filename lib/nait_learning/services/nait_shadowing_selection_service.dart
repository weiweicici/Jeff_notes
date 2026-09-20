import '../models/nait_english_chunk.dart';

enum ShadowingCategory {
  instructional, // Lab, assignment, action, configuration instructions
  teacherQuestions, // Teacher questions to class
  highFrequency, // Expressions appearing multiple times or priority 4-5
  generalClassroom, // Idioms, phrasal verbs, transitions, general classroom speech
}

class NaitShadowingSelectionService {
  /// Target minimum duration (8 minutes = 480 seconds).
  final Duration minTargetDuration;

  /// Target center duration (9 minutes = 540 seconds).
  final Duration targetDuration;

  /// Target maximum duration (10 minutes = 600 seconds).
  final Duration maxTargetDuration;

  /// Silence duration inserted between clips.
  final Duration silenceGap;

  const NaitShadowingSelectionService({
    this.minTargetDuration = const Duration(minutes: 8),
    this.targetDuration = const Duration(minutes: 9),
    this.maxTargetDuration = const Duration(minutes: 10),
    this.silenceGap = const Duration(milliseconds: 800),
  });

  /// Selects a balanced set of authentic teacher-original classroom chunks
  /// fitting an 8–10 minute budget, and sorts them chronologically by [audioStart].
  List<NaitEnglishChunk> selectBalancedChunks(List<NaitEnglishChunk> rawChunks) {
    // 1. Strict validity filter: teacher_original only, valid audio timestamps
    final validChunks = rawChunks.where((c) {
      if (c.sourceType != 'teacher_original') return false;
      if (c.audioStart == null || c.audioEnd == null) return false;
      final dur = c.audioEnd! - c.audioStart!;
      // Accept clips between 1.5s and 45s
      return dur >= const Duration(milliseconds: 1500) && dur <= const Duration(seconds: 45);
    }).toList();

    if (validChunks.isEmpty) return [];

    // 2. Deduplicate near-identical phrases
    final deduplicated = _deduplicateChunks(validChunks);

    // Calculate total duration of all qualified clips including silence gaps
    final totalDurationMs = deduplicated.fold<int>(
      0,
      (sum, c) => sum + (c.audioEnd! - c.audioStart!).inMilliseconds + silenceGap.inMilliseconds,
    );

    // Fallback: If total qualified material is less than or equal to max target duration,
    // retain all qualified clips without artificial repetition, sorted chronologically.
    if (totalDurationMs <= maxTargetDuration.inMilliseconds) {
      return _sortChronologically(deduplicated);
    }

    // 3. Categorize chunks for balanced selection
    final Map<ShadowingCategory, List<NaitEnglishChunk>> buckets = {
      ShadowingCategory.instructional: [],
      ShadowingCategory.teacherQuestions: [],
      ShadowingCategory.highFrequency: [],
      ShadowingCategory.generalClassroom: [],
    };

    for (final chunk in deduplicated) {
      final category = _categorizeChunk(chunk);
      buckets[category]!.add(chunk);
    }

    // Sort each bucket by priority descending, appearance count descending
    for (final bucket in buckets.values) {
      bucket.sort((a, b) {
        final pCmp = b.priority.compareTo(a.priority);
        if (pCmp != 0) return pCmp;
        return b.appearanceCount.compareTo(a.appearanceCount);
      });
    }

    // 4. Balanced selection with duration budget
    final List<NaitEnglishChunk> selected = [];
    final Set<String> selectedIds = {};
    int accumulatedMs = 0;
    final targetMs = targetDuration.inMilliseconds;
    final maxMs = maxTargetDuration.inMilliseconds;

    // Phase A: Guaranteed quota per category (up to 3-4 top items per category if available)
    const categoryQuotas = {
      ShadowingCategory.highFrequency: 4,
      ShadowingCategory.instructional: 3,
      ShadowingCategory.teacherQuestions: 2,
      ShadowingCategory.generalClassroom: 4,
    };

    for (final entry in categoryQuotas.entries) {
      final category = entry.key;
      final quota = entry.value;
      final bucket = buckets[category]!;

      int addedFromCategory = 0;
      for (final chunk in bucket) {
        if (addedFromCategory >= quota) break;
        if (selectedIds.contains(chunk.id)) continue;

        final chunkDurMs = (chunk.audioEnd! - chunk.audioStart!).inMilliseconds + silenceGap.inMilliseconds;
        if (accumulatedMs + chunkDurMs <= maxMs) {
          selected.add(chunk);
          selectedIds.add(chunk.id);
          accumulatedMs += chunkDurMs;
          addedFromCategory++;
        }
      }
    }

    // Phase B: Fill remaining duration budget from highest priority remaining items across all categories
    final remainingPool = deduplicated.where((c) => !selectedIds.contains(c.id)).toList()
      ..sort((a, b) {
        final pCmp = b.priority.compareTo(a.priority);
        if (pCmp != 0) return pCmp;
        return b.appearanceCount.compareTo(a.appearanceCount);
      });

    for (final chunk in remainingPool) {
      if (accumulatedMs >= targetMs) break;

      final chunkDurMs = (chunk.audioEnd! - chunk.audioStart!).inMilliseconds + silenceGap.inMilliseconds;
      if (accumulatedMs + chunkDurMs <= maxMs) {
        selected.add(chunk);
        selectedIds.add(chunk.id);
        accumulatedMs += chunkDurMs;
      }
    }

    // 5. Final requirement: sort selected clips CHRONOLOGICALLY by original classroom start time
    return _sortChronologically(selected);
  }

  /// Categorizes chunk into broad pedagogical categories based on available metadata.
  ShadowingCategory _categorizeChunk(NaitEnglishChunk chunk) {
    if (chunk.appearanceCount > 1 || chunk.priority >= 4) {
      return ShadowingCategory.highFrequency;
    }

    final phrase = chunk.phrase.trim().toLowerCase();
    final context = chunk.context.trim().toLowerCase();

    // Question category: phrase or context ends with '?' or starts with interrogative phrasing
    if (phrase.endsWith('?') ||
        context.endsWith('?') ||
        phrase.startsWith('does anyone') ||
        phrase.startsWith('who has') ||
        phrase.startsWith('what do you') ||
        phrase.startsWith('how many') ||
        phrase.startsWith('why would')) {
      return ShadowingCategory.teacherQuestions;
    }

    // Instructional / Lab / Configuration category
    if (phrase.contains('step') ||
        phrase.contains('make sure') ||
        phrase.contains('set up') ||
        phrase.contains('configure') ||
        phrase.contains('install') ||
        phrase.contains('submit') ||
        phrase.contains('hand in') ||
        phrase.contains('due') ||
        phrase.contains('assignment') ||
        phrase.contains('lab') ||
        context.contains('step') ||
        context.contains('make sure') ||
        context.contains('default') ||
        context.contains('click') ||
        context.contains('restart')) {
      return ShadowingCategory.instructional;
    }

    // Default fallback is general authentic classroom English (idioms, phrasal verbs, spoken chunks)
    return ShadowingCategory.generalClassroom;
  }

  /// Deduplicates phrases with high lexical similarity.
  List<NaitEnglishChunk> _deduplicateChunks(List<NaitEnglishChunk> chunks) {
    final List<NaitEnglishChunk> result = [];
    final Set<String> seenNormPhrases = {};

    for (final chunk in chunks) {
      final norm = chunk.phrase
          .toLowerCase()
          .replaceAll(RegExp(r"[^\w\s']"), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      if (norm.isEmpty) continue;

      if (!seenNormPhrases.contains(norm)) {
        seenNormPhrases.add(norm);
        result.add(chunk);
      }
    }

    return result;
  }

  /// Sorts chunks chronologically by [audioStart].
  List<NaitEnglishChunk> _sortChronologically(List<NaitEnglishChunk> chunks) {
    final sorted = List<NaitEnglishChunk>.from(chunks);
    sorted.sort((a, b) {
      final tA = a.audioStart ?? Duration.zero;
      final tB = b.audioStart ?? Duration.zero;
      return tA.compareTo(tB);
    });
    return sorted;
  }
}
