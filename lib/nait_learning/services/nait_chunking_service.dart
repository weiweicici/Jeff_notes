import '../models/nait_transcript_entry.dart';
import 'nait_transcript_parser.dart';

/// Represents a single time-window slice of a transcript for LLM analysis.
class NaitTranscriptChunk {
  final int index;
  final Duration startTime;
  final Duration endTime;
  final List<NaitTranscriptEntry> entries;
  final String formattedText;
  final int estimatedTokenCount;

  const NaitTranscriptChunk({
    required this.index,
    required this.startTime,
    required this.endTime,
    required this.entries,
    required this.formattedText,
    required this.estimatedTokenCount,
  });

  Duration get duration => endTime - startTime;

  Map<String, dynamic> toJson() => {
    'index': index,
    'startTimeMs': startTime.inMilliseconds,
    'endTimeMs': endTime.inMilliseconds,
    'startTime': _formatDuration(startTime),
    'endTime': _formatDuration(endTime),
    'entryCount': entries.length,
    'estimatedTokenCount': estimatedTokenCount,
  };

  static String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  String toString() =>
      'Chunk #$index [${_formatDuration(startTime)} - ${_formatDuration(endTime)}] '
      '(${entries.length} entries, ~$estimatedTokenCount tokens)';
}

/// Hybrid time-window and token-safety transcript chunking service.
class NaitChunkingService {
  /// Target duration for each chunk (default ~17 minutes, within 16-18m range).
  final Duration targetChunkDuration;

  /// Overlap duration between consecutive chunks (default 90 seconds).
  final Duration overlapDuration;

  /// Maximum estimated prompt token safety ceiling per chunk.
  final int maxPromptTokens;

  /// Minimum silence gap between entries considered a natural conversational pause.
  final Duration pauseThreshold;

  /// Time window around target boundary to search for a natural pause.
  final Duration pauseSearchWindow;

  const NaitChunkingService({
    this.targetChunkDuration = const Duration(minutes: 17),
    this.overlapDuration = const Duration(seconds: 90),
    this.maxPromptTokens = 6000,
    this.pauseThreshold = const Duration(seconds: 4),
    this.pauseSearchWindow = const Duration(seconds: 45),
  });

  /// Estimates token count from text using character heuristic (~3.8 chars/token).
  static int estimateTokenCount(String text) {
    if (text.isEmpty) return 0;
    return (text.length / 3.8).ceil();
  }

  /// Slices a list of transcript entries into overlapping, boundary-aligned chunks.
  List<NaitTranscriptChunk> createChunks(List<NaitTranscriptEntry> entries) {
    if (entries.isEmpty) return const [];

    // Ensure entries are ordered by timestamp
    final sorted = List<NaitTranscriptEntry>.from(entries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final totalDuration = sorted.last.timestamp - sorted.first.timestamp;
    final totalText = NaitTranscriptParser.formatForLlm(sorted);
    final totalTokens = estimateTokenCount(totalText);

    // If entire transcript is within target duration and token budget, return single chunk
    if (totalDuration <= targetChunkDuration && totalTokens <= maxPromptTokens) {
      return [
        NaitTranscriptChunk(
          index: 0,
          startTime: sorted.first.timestamp,
          endTime: sorted.last.timestamp,
          entries: sorted,
          formattedText: totalText,
          estimatedTokenCount: totalTokens,
        ),
      ];
    }

    final List<NaitTranscriptChunk> chunks = [];
    int startIndex = 0;
    int chunkIndex = 0;

    while (startIndex < sorted.length) {
      final chunkStart = sorted[startIndex].timestamp;
      final targetEnd = chunkStart + targetChunkDuration;

      // Find boundary end index
      int endIndex = _findBoundaryIndex(
        sorted: sorted,
        startIndex: startIndex,
        targetEnd: targetEnd,
      );

      // Enforce token safety ceiling: if entries exceed maxPromptTokens, shrink endIndex
      endIndex = _enforceTokenCeiling(
        sorted: sorted,
        startIndex: startIndex,
        endIndex: endIndex,
      );

      final chunkEntries = sorted.sublist(startIndex, endIndex);
      final formatted = NaitTranscriptParser.formatForLlm(chunkEntries);
      final tokens = estimateTokenCount(formatted);

      chunks.add(
        NaitTranscriptChunk(
          index: chunkIndex++,
          startTime: chunkEntries.first.timestamp,
          endTime: chunkEntries.last.timestamp,
          entries: chunkEntries,
          formattedText: formatted,
          estimatedTokenCount: tokens,
        ),
      );

      if (endIndex >= sorted.length) {
        break;
      }

      // Compute next start index with overlap
      final nextTargetStart = chunkEntries.last.timestamp - overlapDuration;
      int nextStartIndex = startIndex + 1; // Strict forward progress guarantee

      for (int i = startIndex + 1; i < endIndex; i++) {
        if (sorted[i].timestamp >= nextTargetStart) {
          nextStartIndex = i;
          break;
        }
      }

      // If nextStartIndex didn't advance, advance by at least 1
      if (nextStartIndex <= startIndex) {
        nextStartIndex = startIndex + 1;
      }

      startIndex = nextStartIndex;
    }

    return chunks;
  }

  /// Locates the best boundary index near [targetEnd], prioritizing natural pauses.
  int _findBoundaryIndex({
    required List<NaitTranscriptEntry> sorted,
    required int startIndex,
    required Duration targetEnd,
  }) {
    final searchStart = targetEnd - pauseSearchWindow;
    final searchEnd = targetEnd + pauseSearchWindow;

    int bestPauseIndex = -1;
    Duration bestGap = Duration.zero;

    // First, scan for natural pause in search window
    for (int i = startIndex + 1; i < sorted.length; i++) {
      final t = sorted[i].timestamp;
      if (t < searchStart) continue;
      if (t > searchEnd) break;

      final gap = t - sorted[i - 1].timestamp;
      if (gap >= pauseThreshold && gap > bestGap) {
        bestGap = gap;
        bestPauseIndex = i;
      }
    }

    if (bestPauseIndex != -1) {
      return bestPauseIndex;
    }

    // If no natural pause, pick the first entry at or after targetEnd
    for (int i = startIndex + 1; i < sorted.length; i++) {
      if (sorted[i].timestamp >= targetEnd) {
        return i;
      }
    }

    // Otherwise include all remaining entries
    return sorted.length;
  }

  /// Decrements [endIndex] if formatted text exceeds [maxPromptTokens].
  int _enforceTokenCeiling({
    required List<NaitTranscriptEntry> sorted,
    required int startIndex,
    required int endIndex,
  }) {
    var curEnd = endIndex;
    while (curEnd > startIndex + 1) {
      final slice = sorted.sublist(startIndex, curEnd);
      final text = NaitTranscriptParser.formatForLlm(slice);
      if (estimateTokenCount(text) <= maxPromptTokens) {
        return curEnd;
      }
      // Shrink by 5 entries or 1 at a time if close
      final step = (curEnd - startIndex > 20) ? 5 : 1;
      curEnd = (curEnd - step).clamp(startIndex + 1, sorted.length);
    }
    return curEnd;
  }
}
