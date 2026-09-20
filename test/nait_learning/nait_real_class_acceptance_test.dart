import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/services/nait_audio_import_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_processing_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NAIT Real-Class Acceptance Test (Phase 1 End-to-End)', () {
    final fixtureRoot = Directory('real_class_test');
    final audioSource = File('${fixtureRoot.path}/audio.mp4');
    final transcriptSource = File('${fixtureRoot.path}/transcripts.json');
    final cachedChunksDir = Directory('real_class_test/acceptance/nait/real_class/week_01/class_20260904/chunks');

    final testStorageDir = Directory('real_class_test/acceptance/phase1_acceptance_run');

    setUp(() async {
      if (await testStorageDir.exists()) {
        await testStorageDir.delete(recursive: true);
      }
      await testStorageDir.create(recursive: true);
    });

    tearDown(() async {
      if (await testStorageDir.exists()) {
        await testStorageDir.delete(recursive: true);
      }
    });

    test('Processes real class session to exactly summary.md and shadowing.mp3 with cleanup', () async {
      expect(await audioSource.exists(), isTrue, reason: 'External real audio fixture must exist');
      expect(await transcriptSource.exists(), isTrue, reason: 'External real transcript fixture must exist');
      final originalAudioSizeBefore = await audioSource.length();
      final originalTranscriptSizeBefore = await transcriptSource.length();

      final storage = NaitStorageService()..setBaseDir(testStorageDir);
      final sessionDir = await storage.getSessionDir('SYSA1010', 1, '20260904');

      // 1. Copy external source files to session dir (internal working copies)
      final internalAudio = await NaitAudioImportService.preserveOriginalAudio(
        sourceAudio: audioSource,
        sessionDir: sessionDir,
      );
      final importResult = await NaitAudioImportService.importTranscript(
        sourceTranscript: transcriptSource,
        sessionDir: sessionDir,
      );

      // Verify copies exist
      expect(await internalAudio.exists(), isTrue);
      expect(await importResult.file.exists(), isTrue);

      // 2. Pre-populate chunks if available to test fast deterministic processing
      final sessionChunksDir = Directory('${sessionDir.path}/chunks');
      if (await cachedChunksDir.exists()) {
        await sessionChunksDir.create(recursive: true);
        var chunkIndex = 0;
        await for (final entity in cachedChunksDir.list()) {
          if (entity is File && entity.path.endsWith('.json')) {
            if (entity.path.endsWith('chunk_manifest.json')) {
              await entity.copy('${sessionChunksDir.path}/${entity.uri.pathSegments.last}');
            } else {
              final content = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
              if (content.containsKey('classroomEnglish')) {
                final list = content['classroomEnglish'] as List<dynamic>;
                for (var i = 0; i < list.length; i++) {
                  final item = list[i] as Map<String, dynamic>;
                  final offset = ((chunkIndex * 5 + i) * 3000) % 25000;
                  item['audioStart'] = offset + 100;
                  item['audioEnd'] = offset + 2600;
                  item['sourceType'] = 'teacher_original';
                }
              }
              await File('${sessionChunksDir.path}/${entity.uri.pathSegments.last}')
                  .writeAsString(jsonEncode(content));
              chunkIndex++;
            }
          }
        }
      }

      // 3. Create synthetic normalized audio for test speed if full ffmpeg extraction is heavy,
      // or test audio slicing with real WAV. Let's create a valid WAV header + PCM for session slicing.
      final normalizedWav = File('${sessionDir.path}/normalized.wav');
      // 16kHz mono 16-bit PCM (32000 bytes per second) - 30 seconds for fast acceptance test
      const sampleRate = 16000;
      const numChannels = 1;
      const bitsPerSample = 16;
      const durationSeconds = 30;
      const dataSize = sampleRate * numChannels * (bitsPerSample ~/ 8) * durationSeconds;
      final wavHeader = BytesBuilder();
      wavHeader.add(utf8.encode('RIFF'));
      wavHeader.add([dataSize + 36, 0, 0, 0]);
      wavHeader.add(utf8.encode('WAVEfmt '));
      wavHeader.add([16, 0, 0, 0, 1, 0, numChannels, 0]);
      wavHeader.add([sampleRate & 0xFF, (sampleRate >> 8) & 0xFF, 0, 0]);
      final byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
      wavHeader.add([byteRate & 0xFF, (byteRate >> 8) & 0xFF, (byteRate >> 16) & 0xFF, 0]);
      wavHeader.add([numChannels * (bitsPerSample ~/ 8), 0, bitsPerSample, 0]);
      wavHeader.add(utf8.encode('data'));
      wavHeader.add([dataSize & 0xFF, (dataSize >> 8) & 0xFF, (dataSize >> 16) & 0xFF, (dataSize >> 24) & 0xFF]);
      wavHeader.add(List<int>.filled(dataSize, 0));
      await normalizedWav.writeAsBytes(wavHeader.takeBytes());

      final session = NaitClassSession(
        id: '20260904',
        courseId: 'SYSA1010',
        weekNumber: 1,
        classDate: DateTime(2026, 9, 4),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        originalAudioPath: internalAudio.path,
        transcriptPath: importResult.file.path,
        normalizedAudioPath: normalizedWav.path,
      );

      final processingService = NaitProcessingService(storageService: storage);
      final processedSession = await processingService.processClassSession(
        session: session,
        cleanIntermediate: true,
      );

      // 4. Verify deliverables
      expect(processedSession.summaryPath, isNotNull);
      final summaryFile = File(processedSession.summaryPath!);
      expect(await summaryFile.exists(), isTrue, reason: 'summary.md must exist');
      final summaryContent = await summaryFile.readAsString();
      expect(summaryContent.contains('# SYSA1010 — Week 1'), isTrue);

      expect(processedSession.shadowingAudioPath, isNotNull);
      final shadowingFile = File(processedSession.shadowingAudioPath!);
      expect(await shadowingFile.exists(), isTrue, reason: 'shadowing.mp3 must exist');
      expect(await shadowingFile.length(), greaterThan(0));

      expect(processedSession.shadowingSegments, isNotEmpty);
      for (final seg in processedSession.shadowingSegments) {
        expect(seg.shadowingStartMs, lessThan(seg.shadowingEndMs));
        expect(seg.phrase.isNotEmpty, isTrue);
      }

      // 5. Verify intermediate cleanup
      expect(await normalizedWav.exists(), isFalse, reason: 'normalized.wav must be cleaned up');
      expect(await Directory('${sessionDir.path}/clips').exists(), isFalse, reason: 'clips/ dir must be cleaned up');
      expect(await Directory('${sessionDir.path}/chunks').exists(), isFalse, reason: 'chunks/ dir must be cleaned up');
      expect(await internalAudio.exists(), isFalse, reason: 'Internal original_audio copy must be cleaned up');
      expect(await importResult.file.exists(), isFalse, reason: 'Internal transcript copy must be cleaned up');

      // 6. Non-negotiable safety: external source files must be 100% untouched
      expect(await audioSource.exists(), isTrue, reason: 'User external audio must never be deleted');
      expect(await audioSource.length(), equals(originalAudioSizeBefore));
      expect(await transcriptSource.exists(), isTrue, reason: 'User external transcript must never be deleted');
      expect(await transcriptSource.length(), equals(originalTranscriptSizeBefore));
    });
  });
}
