import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/adapters/audio_recorder_adapter.dart';
import 'package:jeff_notes/text_sanitizer.dart';
import 'package:record/record.dart';

void main() {
  group('Stage 6 text and multi-page parsing', () {
    test('preserves legitimate repeated words and structured annotations', () {
      expect(
        TextSanitizer.clean(
          'It was very very important (see Appendix A) [Figure 1].',
        ),
        contains('very very'),
      );
      expect(
        TextSanitizer.clean('It was had had in the source [Figure 1].'),
        contains('had had'),
      );
      expect(TextSanitizer.clean('[Music] Hello'), 'Hello');
    });

    test('cleans translation wrappers without altering technical terms', () {
      expect(
        TextSanitizer.cleanTranslation(
          '```text\nTranslation: “通过 VPN 连接到 RDP。”\n```',
        ),
        '通过 VPN 连接到 RDP。',
      );
      expect(
        TextSanitizer.cleanTranslation('翻译：第一句。\nTranslation: 第二句。'),
        '第一句。\n第二句。',
      );
      expect(TextSanitizer.clean('Wait!!! Really??'), 'Wait! Really?');
      expect(TextSanitizer.clean(r'A $1 value.'), r'A $1 value.');
    });
  });

  group('Stage 9 audio recorder adapter', () {
    test('fake adapter models permission, start, stop and disposal', () async {
      final adapter = FakeAudioRecorderAdapter(stopPath: '/tmp/audio.wav');
      expect(await adapter.hasPermission(), isTrue);
      await adapter.start(
        const RecordConfig(encoder: AudioEncoder.wav),
        path: '/tmp/audio.wav',
      );
      expect(adapter.isRecording, isTrue);
      expect(await adapter.stop(), '/tmp/audio.wav');
      await adapter.dispose();
      expect(adapter.isDisposed, isTrue);
    });

    test('STT slice choices support fast captions and longer chunks', () {
      final provider = File('lib/recording_provider.dart').readAsStringSync();
      final settings = File('lib/screens/notes_screen.dart').readAsStringSync();

      expect(provider, contains('int _sliceDuration = 5;'));
      expect(provider, contains('duration.clamp(5, 10)'));
      expect(provider, contains("'slice_duration') ?? 5"));
      expect(settings, contains('items: [5, 6, 8, 10]'));
    });
  });
}
