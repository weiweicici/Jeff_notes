import 'dart:io';
import 'package:path/path.dart' as p;
import '../../services/wav_stitch_service.dart';
import '../models/nait_audio_clip.dart';
import '../models/nait_english_chunk.dart';
import '../models/nait_week.dart';
import 'nait_audio_extract_service.dart';
import 'nait_storage_service.dart';

class ConsolidatedEnglishResult {
  final List<NaitEnglishChunk> chunks;
  final List<NaitAudioClip> selectedClips;
  final String? listeningPackPath;

  ConsolidatedEnglishResult({
    required this.chunks,
    required this.selectedClips,
    this.listeningPackPath,
  });
}

class NaitWeekConsolidationService {
  final NaitStorageService _storageService;

  NaitWeekConsolidationService({NaitStorageService? storageService})
      : _storageService = storageService ?? NaitStorageService();

  static String normalizePhraseKey(String phrase) {
    return phrase
        .toLowerCase()
        .replaceAll(RegExp(r"[^\w\s']"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Consolidates English chunks across all sessions in a week,
  /// detects repeats, boosts priority, selects top clips, and builds
  /// the Weekly Listening Pack with silence gaps.
  Future<ConsolidatedEnglishResult> consolidateWeek({
    required String courseId,
    required int weekNumber,
  }) async {
    final sessions = await _storageService.loadSessionsForWeek(courseId, weekNumber);
    final Map<String, NaitEnglishChunk> chunkMap = {};
    final Map<String, NaitAudioClip> clipMap = {};

    for (final session in sessions) {
      for (final clip in session.clips) {
        clipMap[clip.id] = clip;
      }

      if (session.analysis == null) continue;
      for (final chunk in session.analysis!.classroomEnglish) {
        final key = normalizePhraseKey(chunk.phrase);
        if (key.isEmpty) continue;

        if (chunkMap.containsKey(key)) {
          final existing = chunkMap[key]!;
          existing.appearanceCount += 1;
          existing.priority = (existing.priority + 1).clamp(1, 5);
          if (chunk.lastSeenAt.isAfter(existing.lastSeenAt)) {
            existing.lastSeenAt = chunk.lastSeenAt;
          }
          // Preserve clip if existing has none but current does
          if (existing.audioClipId == null && chunk.audioClipId != null) {
            existing.audioClipId = chunk.audioClipId;
          }
        } else {
          chunkMap[key] = NaitEnglishChunk(
            id: chunk.id,
            phrase: chunk.phrase,
            chineseMeaning: chunk.chineseMeaning,
            context: chunk.context,
            courseId: courseId,
            classSessionId: session.id,
            weekNumber: weekNumber,
            sourceTimestamp: chunk.sourceTimestamp,
            audioStart: chunk.audioStart,
            audioEnd: chunk.audioEnd,
            audioClipId: chunk.audioClipId,
            priority: chunk.priority,
            firstSeenAt: chunk.firstSeenAt,
            lastSeenAt: chunk.lastSeenAt,
            appearanceCount: 1,
            learned: chunk.learned,
            sourceType: chunk.sourceType,
          );
        }
      }
    }

    final consolidatedChunks = chunkMap.values.toList();
    // Sort by priority descending, appearance count descending
    consolidatedChunks.sort((a, b) {
      final pCmp = b.priority.compareTo(a.priority);
      if (pCmp != 0) return pCmp;
      return b.appearanceCount.compareTo(a.appearanceCount);
    });

    // Select clips for the listening pack
    final List<NaitAudioClip> packClips = [];
    final List<String> clipPathsWithSilence = [];

    final weekDir = await _storageService.getWeekDir(courseId, weekNumber);
    final silenceFile = File(p.join(weekDir.path, 'silence_gap.wav'));

    // Ensure a 0.8s silence WAV is created
    await NaitAudioExtractService.createSilenceWav(
      duration: const Duration(milliseconds: 800),
      outputFile: silenceFile,
    );

    for (final chunk in consolidatedChunks) {
      if (chunk.audioClipId != null && clipMap.containsKey(chunk.audioClipId)) {
        final clip = clipMap[chunk.audioClipId]!;
        if (await File(clip.filePath).exists()) {
          packClips.add(clip);
          clipPathsWithSilence.add(clip.filePath);
          clipPathsWithSilence.add(silenceFile.path);
        }
      }
    }

    String? packAudioPath;
    if (packClips.isNotEmpty) {
      // Remove trailing silence
      if (clipPathsWithSilence.isNotEmpty &&
          clipPathsWithSilence.last == silenceFile.path) {
        clipPathsWithSilence.removeLast();
      }

      final packFile = File(p.join(weekDir.path, 'listening_pack.wav'));
      final success = await WavStitchService.stitch(
        inputPaths: clipPathsWithSilence,
        outputPath: packFile.path,
      );

      if (success) {
        packAudioPath = packFile.path;
        final week = await _storageService.loadWeek(courseId, weekNumber) ??
            NaitWeek(courseId: courseId, weekNumber: weekNumber);
        week.packAudioPath = packAudioPath;
        week.updatedAt = DateTime.now();
        await _storageService.saveWeek(week);
      }
    }

    return ConsolidatedEnglishResult(
      chunks: consolidatedChunks,
      selectedClips: packClips,
      listeningPackPath: packAudioPath,
    );
  }
}
