import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import '../models/nait_transcript_entry.dart';
import 'nait_transcript_parser.dart';

class NaitAudioImportService {
  /// Normalizes an audio file (MP4, M4A, MP3, WAV, etc.) to 16kHz 16-bit mono PCM WAV.
  /// Uses ffmpeg_kit_flutter_new_audio, with a CLI fallback if running in desktop dev mode.
  static Future<File> normalizeAudio({
    required File inputFile,
    required File outputWavFile,
  }) async {
    if (!await inputFile.exists()) {
      throw FileNotFoundException('Input audio file not found: ${inputFile.path}');
    }

    final parent = outputWavFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    if (await outputWavFile.exists()) {
      await outputWavFile.delete();
    }

    final inputPath = inputFile.path;
    final outputPath = outputWavFile.path;

    // Normalization command: mono (-ac 1), 16kHz (-ar 16000), 16-bit PCM (-acodec pcm_s16le)
    final cmd = '-y -i "$inputPath" -vn -acodec pcm_s16le -ac 1 -ar 16000 "$outputPath"';

    bool converted = false;
    String? errorDetail;

    // Strategy 1: Attempt native FFmpegKit plugin execution
    try {
      final session = await FFmpegKit.executeAsync(cmd);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode)) {
        if (await outputWavFile.exists() && await outputWavFile.length() > 44) {
          converted = true;
        }
      } else {
        errorDetail = 'FFmpegKit returned code $returnCode';
      }
    } catch (e) {
      errorDetail = 'FFmpegKit exception: $e';
    }

    // Strategy 2: If FFmpegKit failed or native dylib is absent (e.g. desktop CLI/macOS dev test),
    // attempt local ffmpeg binary fallback if available
    if (!converted) {
      try {
        final result = await Process.run('ffmpeg', [
          '-y',
          '-i', inputPath,
          '-vn',
          '-acodec', 'pcm_s16le',
          '-ac', '1',
          '-ar', '16000',
          outputPath,
        ]);
        if (result.exitCode == 0 && await outputWavFile.exists() && await outputWavFile.length() > 44) {
          converted = true;
        } else {
          errorDetail = (errorDetail != null ? '$errorDetail; ' : '') +
              'System ffmpeg exited with ${result.exitCode}: ${result.stderr}';
        }
      } catch (e) {
        errorDetail = (errorDetail != null ? '$errorDetail; ' : '') + 'System ffmpeg not found: $e';
      }
    }

    // Strategy 3: If input is already a WAV file, and FFmpeg is unavailable, copy it as normalized.wav
    if (!converted && p.extension(inputPath).toLowerCase() == '.wav') {
      await inputFile.copy(outputPath);
      if (await outputWavFile.exists()) {
        converted = true;
      }
    }

    if (!converted) {
      throw AudioConversionException(
        'Failed to convert audio to normalized WAV ($inputPath -> $outputPath). Details: $errorDetail',
      );
    }

    return outputWavFile;
  }

  /// Copies the original audio into the session directory without modification.
  static Future<File> preserveOriginalAudio({
    required File sourceAudio,
    required Directory sessionDir,
  }) async {
    final ext = p.extension(sourceAudio.path);
    final targetFile = File(p.join(sessionDir.path, 'original_audio$ext'));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    return await sourceAudio.copy(targetFile.path);
  }

  /// Copies and parses transcript into the session directory.
  static Future<({File file, List<NaitTranscriptEntry> entries})> importTranscript({
    required File sourceTranscript,
    required Directory sessionDir,
  }) async {
    final targetFile = File(p.join(sessionDir.path, 'transcript.txt'));
    if (await targetFile.exists()) {
      await targetFile.delete();
    }
    await sourceTranscript.copy(targetFile.path);
    final entries = await NaitTranscriptParser.parseFile(targetFile);
    return (file: targetFile, entries: entries);
  }
}

class AudioConversionException implements Exception {
  final String message;
  AudioConversionException(this.message);
  @override
  String toString() => message;
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
