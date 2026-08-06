import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/tts_service.dart';

void main() {
  test('native TTS repeats only while loop mode and channel remain active', () {
    expect(
      TtsService.shouldRepeatNativePlayback(
        loopEnabled: true,
        playbackBlocked: false,
        channelIsStillActive: true,
      ),
      isTrue,
    );
    expect(
      TtsService.shouldRepeatNativePlayback(
        loopEnabled: false,
        playbackBlocked: false,
        channelIsStillActive: true,
      ),
      isFalse,
    );
    expect(
      TtsService.shouldRepeatNativePlayback(
        loopEnabled: true,
        playbackBlocked: true,
        channelIsStillActive: true,
      ),
      isFalse,
    );
    expect(
      TtsService.shouldRepeatNativePlayback(
        loopEnabled: true,
        playbackBlocked: false,
        channelIsStillActive: false,
      ),
      isFalse,
    );
  });

  test('dictation splits simple prose and estimates repeat and pause time', () {
    const text = 'First sentence. Second sentence! Third sentence?';
    expect(TtsService.splitEnglishSentences(text), [
      'First sentence.',
      'Second sentence!',
      'Third sentence?',
    ]);
    expect(
      TtsService.estimateEnglishDictationDuration(
        text,
        repeatCount: 3,
        pauseBetweenSentences: const Duration(seconds: 3),
        speed: 0.6,
      ),
      const Duration(seconds: 18),
    );
  });
}
