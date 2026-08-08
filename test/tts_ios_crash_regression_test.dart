import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iOS just_audio crash regression', () {
    late String source;
    late String audioHandlerSource;
    late String mainSource;

    setUpAll(() async {
      source = await File('lib/services/tts_service.dart').readAsString();
      audioHandlerSource = await File(
        'lib/services/audio_handler.dart',
      ).readAsString();
      mainSource = await File('lib/main.dart').readAsString();
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

    test('TTS preparation claims iOS Now Playing as loading playback', () {
      expect(source, contains('publishPreparingPlayback('));
      expect(
        audioHandlerSource,
        contains('processingState: AudioProcessingState.loading'),
      );
      expect(audioHandlerSource, contains('playing: true'));
    });

    test('unsafe route pauses dictation without releasing Now Playing', () {
      final routeGuardBody = RegExp(
        r'Future<void> _enforceSafeOutputRoute[\s\S]*?\n  void _startHeadphoneMonitor',
      ).firstMatch(source)?.group(0);

      expect(routeGuardBody, isNotNull);
      expect(routeGuardBody, contains('_pauseDictationForUnsafeRoute'));
      expect(routeGuardBody, isNot(contains('stopAll()')));
      expect(audioHandlerSource, contains('pausing safely and retaining'));
    });

    test('system previous control navigates to the previous sentence', () {
      expect(
        source,
        matches(
          RegExp(
            r'globalAudioHandler\.onSkipPrevious\s*=\s*requestPreviousEnglishDictationSentence;',
          ),
        ),
      );
      expect(
        source,
        isNot(
          contains(
            'globalAudioHandler.onSkipPrevious = _requestExtraEnglishDictationReplay;',
          ),
        ),
      );
    });

    test('Now Playing adds separate five-second seek controls', () {
      expect(mainSource, contains('fastForwardInterval: Duration(seconds: 5)'));
      expect(mainSource, contains('rewindInterval: Duration(seconds: 5)'));
      expect(audioHandlerSource, contains('MediaControl.rewind'));
      expect(audioHandlerSource, contains('MediaControl.fastForward'));
      expect(
        audioHandlerSource,
        contains('_seekRelativeToPlayer(-AudioService.config.rewindInterval)'),
      );
    });
  });
}
