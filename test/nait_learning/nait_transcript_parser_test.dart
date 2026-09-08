import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:jeff_notes/nait_learning/services/nait_audio_import_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_transcript_parser.dart';

void main() {
  group('NaitTranscriptParser', () {
    test('Parses Meetily JSON segments with fractional timestamps', () {
      const json = '{"version":"1.0","segments":[{"audio_start_time":0.21,"text":"Hello class"},{"audio_start_time":2.38,"text":"Install the tool."}],"total_segments":2}';
      final entries = NaitTranscriptParser.parseMeetilyJson(json);
      expect(entries.length, 2);
      expect(entries[0].timestamp, const Duration(milliseconds: 210));
      expect(entries[1].timestamp, const Duration(milliseconds: 2380));
      expect(entries[1].speaker, isNull);
    });

    test('Imports and reparses Meetily JSON preserving persisted extension', () async {
      final root = await Directory.systemTemp.createTemp('nait_meetily_');
      addTearDown(() => root.delete(recursive: true));
      final source = File('${root.path}/source.json')..writeAsStringSync(
        '{"version":"1.0","segments":[{"audio_start_time":1.25,"audio_end_time":2.5,"duration":1.25,"display_time":"00:00:01","confidence":0.9,"id":"seg_0","sequence_id":0,"text":"Click Next."}],"total_segments":1}');
      final result = await NaitAudioImportService.importTranscript(
        sourceTranscript: source, sessionDir: root,
      );
      expect(result.file.path, endsWith('transcript.json'));
      expect(result.entries.single.timestamp, const Duration(milliseconds: 1250));
      expect(result.entries.single.text, 'Click Next.');
    });
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
