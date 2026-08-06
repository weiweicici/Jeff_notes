import 'dart:convert';

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

  test('parses Edge sentence boundary metadata ticks and text', () {
    final frame =
        'Content-Type:application/json\r\nPath:audio.metadata\r\n\r\n'
        '${jsonEncode({
          'Metadata': [
            {
              'Type': 'SentenceBoundary',
              'Data': {
                'Offset': 12000000,
                'Duration': 8000000,
                'text': {'Text': 'This is a sentence.'},
              },
            },
            {
              'Type': 'WordBoundary',
              'Data': {
                'Offset': 12000000,
                'Duration': 1000000,
                'text': {'Text': 'This'},
              },
            },
          ],
        })}';

    final boundaries = TtsService.parseEdgeSentenceMetadata(frame);
    expect(boundaries, hasLength(1));
    expect(boundaries.single.text, 'This is a sentence.');
    expect(boundaries.single.offset, const Duration(milliseconds: 1200));
    expect(boundaries.single.duration, const Duration(milliseconds: 800));
  });

  test(
    'dictation starts another full round only while loop remains enabled',
    () {
      expect(
        TtsService.shouldContinueEnglishDictation(
          loopEnabled: true,
          runId: 7,
          currentRunId: 7,
        ),
        isTrue,
      );
      expect(
        TtsService.shouldContinueEnglishDictation(
          loopEnabled: false,
          runId: 7,
          currentRunId: 7,
        ),
        isFalse,
      );
      expect(
        TtsService.shouldContinueEnglishDictation(
          loopEnabled: true,
          runId: 7,
          currentRunId: 8,
        ),
        isFalse,
      );
    },
  );

  test(
    'dictation pause gate waits for resume without advancing work',
    () async {
      final gate = DictationPauseGate();
      expect(gate.isPaused, isFalse);

      gate.pause();
      expect(gate.isPaused, isTrue);
      var continued = false;
      final wait = gate.waitWhilePaused().then((_) => continued = true);
      await Future<void>.delayed(Duration.zero);
      expect(continued, isFalse);

      gate.resume();
      await wait;
      expect(gate.isPaused, isFalse);
      expect(continued, isTrue);
    },
  );

  test('cancelling a paused dictation releases its pending wait', () async {
    final gate = DictationPauseGate()..pause();
    final wait = gate.waitWhilePaused();
    gate.cancel();
    await wait;
    expect(gate.isPaused, isFalse);
  });

  test('rapid headset pause then play is treated as an extra replay', () {
    final pauseAt = DateTime.utc(2026, 8, 6, 12);
    expect(
      TtsService.isRapidDictationMediaReplay(
        pauseAt,
        pauseAt.add(const Duration(milliseconds: 450)),
      ),
      isTrue,
    );
  });

  test('a normal delayed resume remains an ordinary resume', () {
    final pauseAt = DateTime.utc(2026, 8, 6, 12);
    expect(
      TtsService.isRapidDictationMediaReplay(
        pauseAt,
        pauseAt.add(const Duration(seconds: 2)),
      ),
      isFalse,
    );
  });

  test('dictation sentence navigation clamps previous and ends the round', () {
    expect(
      TtsService.resolveEnglishDictationSentenceNavigation(
        currentIndex: 2,
        sentenceCount: 5,
        direction: -1,
      ),
      1,
    );
    expect(
      TtsService.resolveEnglishDictationSentenceNavigation(
        currentIndex: 0,
        sentenceCount: 5,
        direction: -1,
      ),
      0,
    );
    expect(
      TtsService.resolveEnglishDictationSentenceNavigation(
        currentIndex: 4,
        sentenceCount: 5,
        direction: 1,
      ),
      5,
    );
  });
}
