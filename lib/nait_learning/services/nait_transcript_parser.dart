import 'dart:io';
import 'dart:convert';
import '../models/nait_transcript_entry.dart';

class NaitTranscriptParser {
  // Regex to match timestamp at the beginning of a line:
  // [MM:SS] or [HH:MM:SS] or [H:MM:SS] or [M:SS]
  static final RegExp _timestampRegex = RegExp(
    r'^\[?(\d{1,2}:)?(\d{1,2}):(\d{2}(?:\.\d+)?)\]?\s*(.*)$',
  );

  static final RegExp _speakerRegex = RegExp(r'^([^:]+):\s*(.*)$');

  /// Parses raw transcript text into structured [NaitTranscriptEntry] items.
  static List<NaitTranscriptEntry> parse(String text) {
    final List<NaitTranscriptEntry> entries = [];
    final lines = text.split('\n');
    Duration lastTimestamp = Duration.zero;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final match = _timestampRegex.firstMatch(line);
      if (match != null) {
        final hoursPart = match.group(1);
        final minutesPart = match.group(2);
        final secondsPart = match.group(3);
        var content = match.group(4) ?? '';

        try {
          int h = 0;
          if (hoursPart != null && hoursPart.isNotEmpty) {
            h = int.parse(hoursPart.replaceAll(':', ''));
          }
          final m = int.parse(minutesPart ?? '0');
          final sDouble = double.parse(secondsPart ?? '0');
          final s = sDouble.floor();
          final ms = ((sDouble - s) * 1000).round();

          lastTimestamp = Duration(hours: h, minutes: m, seconds: s, milliseconds: ms);

          String? speaker;
          final speakerMatch = _speakerRegex.firstMatch(content);
          if (speakerMatch != null) {
            speaker = speakerMatch.group(1)?.trim();
            content = speakerMatch.group(2)?.trim() ?? '';
          }

          entries.add(NaitTranscriptEntry(
            timestamp: lastTimestamp,
            text: content.trim(),
            speaker: speaker,
          ));
        } catch (_) {
          // Gracefully append as continuation or fallback
          entries.add(NaitTranscriptEntry(
            timestamp: lastTimestamp,
            text: line,
          ));
        }
      } else {
        // Line without timestamp, check if we can append to the last entry
        if (entries.isNotEmpty) {
          final last = entries.removeLast();
          entries.add(NaitTranscriptEntry(
            timestamp: last.timestamp,
            text: '${last.text} $line'.trim(),
            speaker: last.speaker,
          ));
        } else {
          entries.add(NaitTranscriptEntry(
            timestamp: Duration.zero,
            text: line,
          ));
        }
      }
    }

    return entries;
  }

  /// Parses a file directly.
  static Future<List<NaitTranscriptEntry>> parseFile(File file) async {
    if (!await file.exists()) return [];
    final content = await file.readAsString();
    if (file.path.toLowerCase().endsWith('.json')) {
      return parseMeetilyJson(content);
    }
    return parse(content);
  }

  /// Parses Meetily's timestamped export format.
  static List<NaitTranscriptEntry> parseMeetilyJson(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map || decoded['segments'] is! List) {
      throw const FormatException('Unsupported Meetily transcript JSON');
    }
    return (decoded['segments'] as List).map((rawSegment) {
      if (rawSegment is! Map) {
        throw const FormatException('Invalid Meetily transcript segment');
      }
      final segment = rawSegment;
      final start = segment['audio_start_time'];
      final text = segment['text'];
      if (start is! num || !start.isFinite || start < 0 || text is! String) {
        throw const FormatException('Invalid Meetily transcript segment');
      }
      return NaitTranscriptEntry(
        timestamp: Duration(milliseconds: (start * 1000).round()),
        text: text.trim(),
      );
    }).where((entry) => entry.text.isNotEmpty).toList();
  }

  /// Rebuilds clean, formatted transcript text suitable for LLM input.
  static String formatForLlm(List<NaitTranscriptEntry> entries) {
    final buffer = StringBuffer();
    for (final e in entries) {
      if (e.text.trim().isEmpty) continue;
      buffer.writeln(e.toString());
    }
    return buffer.toString();
  }
}
