import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/services/nait_transcript_parser.dart';

void main() {
  group('NaitTranscriptParser', () {
    test('1. Parses MM:SS timestamp format [23:10]', () {
      const text = '[23:10] Leave it at the default.';
      final entries = NaitTranscriptParser.parse(text);

      expect(entries.length, 1);
      expect(entries.first.timestamp, const Duration(minutes: 23, seconds: 10));
      expect(entries.first.text, 'Leave it at the default.');
    });

    test('2. Parses HH:MM:SS timestamp format [01:23:10]', () {
      const text = '[01:23:10] Then click Next to finish the setup.';
      final entries = NaitTranscriptParser.parse(text);

      expect(entries.length, 1);
      expect(entries.first.timestamp, const Duration(hours: 1, minutes: 23, seconds: 10));
      expect(entries.first.text, 'Then click Next to finish the setup.');
    });

    test('3. Handles speaker prefix like [12:34] Instructor: hello', () {
      const text = '[12:34] Instructor: Make sure you take a snapshot.';
      final entries = NaitTranscriptParser.parse(text);

      expect(entries.length, 1);
      expect(entries.first.timestamp, const Duration(minutes: 12, seconds: 34));
      expect(entries.first.speaker, 'Instructor');
      expect(entries.first.text, 'Make sure you take a snapshot.');
    });

    test('4. Gracefully handles malformed transcript lines without crashing', () {
      const text = '''
[invalid timestamp] Some broken line
Random text without any brackets at all
[99:99:99] Extremely large numbers
[10:05] Valid line after broken lines
''';
      final entries = NaitTranscriptParser.parse(text);
      expect(entries.isNotEmpty, isTrue);
      // Valid line still parsed
      expect(entries.any((e) => e.text.contains('Valid line after broken lines')), isTrue);
    });

    test('5. Formats transcript for LLM input cleanly', () {
      const text = '''
[00:05] Good morning everyone.
[00:10] Today we are setting up Active Directory.
''';
      final entries = NaitTranscriptParser.parse(text);
      final formatted = NaitTranscriptParser.formatForLlm(entries);

      expect(formatted, contains('[00:05] Good morning everyone.'));
      expect(formatted, contains('[00:10] Today we are setting up Active Directory.'));
    });
  });
}
