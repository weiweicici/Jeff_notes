import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_english_chunk.dart';
import 'package:jeff_notes/nait_learning/services/nait_audio_extract_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_shadowing_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NaitShadowingExportService', () {
    late Directory tempDir;
    late File mockNormalizedWav;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('shadowing_export_test_');
      mockNormalizedWav = File('${tempDir.path}/normalized.wav');
      // Create 30 seconds of PCM silence as mock master normalized WAV (16kHz 16-bit mono = 32,000 bytes/sec)
      await NaitAudioExtractService.createSilenceWav(
        duration: const Duration(seconds: 30),
        outputFile: mockNormalizedWav,
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('recalculates relative timestamps accounting for silence gaps', () async {
      const exportService = NaitShadowingExportService(
        silenceGap: Duration(milliseconds: 800),
      );

      final chunks = [
        NaitEnglishChunk(
          id: 'chunk_1',
          phrase: 'first teacher expression',
          context: 'You can just leave it at the default.',
          chineseMeaning: '保持默认',
          sourceType: 'teacher_original',
          priority: 5,
          audioStart: const Duration(seconds: 2),
          audioEnd: const Duration(seconds: 6), // 4000ms duration
        ),
        NaitEnglishChunk(
          id: 'chunk_2',
          phrase: 'second teacher expression',
          context: 'Make sure you take a snapshot.',
          chineseMeaning: '确保拍摄快照',
          sourceType: 'teacher_original',
          priority: 4,
          audioStart: const Duration(seconds: 10),
          audioEnd: const Duration(seconds: 16), // 6000ms duration
        ),
      ];

      final result = await exportService.exportShadowingMp3(
        selectedChunks: chunks,
        normalizedWavFile: mockNormalizedWav,
        sessionDir: tempDir,
      );

      expect(await result.mp3File.exists(), isTrue);
      expect(result.segments.length, equals(2));

      // Segment 1: start at 0ms, end at 4000ms
      final seg1 = result.segments[0];
      expect(seg1.id, equals('chunk_1'));
      expect(seg1.originalStartMs, equals(2000));
      expect(seg1.originalEndMs, equals(6000));
      expect(seg1.shadowingStartMs, equals(0));
      expect(seg1.shadowingEndMs, equals(4000));

      // Segment 2: start at 4000ms + 800ms silence = 4800ms, end at 4800 + 6000 = 10800ms
      final seg2 = result.segments[1];
      expect(seg2.id, equals('chunk_2'));
      expect(seg2.originalStartMs, equals(10000));
      expect(seg2.originalEndMs, equals(16000));
      expect(seg2.shadowingStartMs, equals(4800));
      expect(seg2.shadowingEndMs, equals(10800));

      expect(result.totalDurationMs, equals(10800));
    });
  });
}
