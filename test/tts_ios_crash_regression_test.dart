import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS just_audio crash regression', () {
    late String source;

    setUpAll(() async {
      source = await File('lib/services/tts_service.dart').readAsString();
    });

    test('dictation does not reload AVPlayerItem for every sentence', () {
      expect(source, isNot(contains('.setClip(')));
    });

    test('TtsService does not dispose the AudioService-owned player', () {
      final disposeBody = RegExp(
        r'void dispose\(\)\s*\{([\s\S]*?)super\.dispose\(\);',
      ).firstMatch(source)?.group(1);

      expect(disposeBody, isNotNull);
      expect(disposeBody, isNot(contains('_audioPlayer.dispose')));
    });
  });
}
