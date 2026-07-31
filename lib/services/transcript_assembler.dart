import '../models/insight_note.dart';
import '../text_sanitizer.dart';

/// Deterministically assembles asynchronous short STT slices in audio order.
class TranscriptAssembler {
  const TranscriptAssembler._();

  static List<InsightNote> validNotes(Iterable<InsightNote> notes) {
    final result = notes.where((note) {
      if (note.isSummary) return false;
      final text = note.transcript.trim();
      return text.isNotEmpty &&
          text != '...' &&
          !text.startsWith('[Silence') &&
          !text.startsWith('[Error');
    }).toList();
    result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return result;
  }

  static String english(Iterable<InsightNote> notes) {
    var assembled = '';
    for (final note in validNotes(notes)) {
      final next = note.transcript.trim();
      assembled = assembled.isEmpty
          ? next
          : TextSanitizer.mergeOverlappingText(assembled, next);
    }
    return assembled.trim();
  }

  static String chinese(Iterable<InsightNote> notes) => validNotes(notes)
      .map((note) => note.translatedContent?.trim() ?? '')
      .where((text) => text.isNotEmpty && !text.startsWith('['))
      .join(' ')
      .trim();

  static String timestampedEnglish(
    Iterable<InsightNote> notes, {
    required DateTime sessionStart,
  }) {
    return validNotes(notes)
        .map((note) {
          final elapsed = note.timestamp.difference(sessionStart);
          final seconds = elapsed.isNegative ? 0 : elapsed.inSeconds;
          final minutePart = (seconds ~/ 60).toString().padLeft(2, '0');
          final secondPart = (seconds % 60).toString().padLeft(2, '0');
          return '[$minutePart:$secondPart] ${note.transcript.trim()}';
        })
        .join('\n');
  }
}
