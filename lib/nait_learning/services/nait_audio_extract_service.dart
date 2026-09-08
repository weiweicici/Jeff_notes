import 'dart:io';
import 'dart:typed_data';
import '../models/nait_transcript_entry.dart';

class NaitAudioExtractService {
  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;
  static const int bytesPerSample = (bitsPerSample ~/ 8) * channels; // 2 bytes
  static const int bytesPerSecond = sampleRate * bytesPerSample;      // 32000 bytes/s
  static const Duration clipPreRoll = Duration(milliseconds: 400);
  static const Duration clipPostRoll = Duration(milliseconds: 1600);
  static const Duration nextEntryGuard = Duration(milliseconds: 100);

  /// Adds room around AI timestamps without cutting past a known Meetily
  /// segment end or drifting into a following unrelated segment.
  static ({Duration start, Duration end}) resolveConservativeClipBounds({
    required Duration audioStart,
    required Duration audioEnd,
    required List<NaitTranscriptEntry> transcriptEntries,
  }) {
    if (audioEnd <= audioStart) {
      throw ArgumentError('Audio end must be after audio start');
    }
    final sorted = List<NaitTranscriptEntry>.from(transcriptEntries)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final start = audioStart > clipPreRoll ? audioStart - clipPreRoll : Duration.zero;
    var end = audioEnd + clipPostRoll;
    var requiredEnd = audioEnd;

    for (final entry in sorted) {
      final entryEnd = entry.endTimestamp;
      if (entryEnd != null && entry.timestamp <= audioEnd && entryEnd >= audioEnd) {
        if (entryEnd > requiredEnd) requiredEnd = entryEnd;
        if (entryEnd > end) end = entryEnd;
      }
    }
    for (final entry in sorted) {
      if (entry.timestamp <= requiredEnd) continue;
      final cap = entry.timestamp > nextEntryGuard
          ? entry.timestamp - nextEntryGuard
          : entry.timestamp;
      if (end > cap) end = cap >= requiredEnd ? cap : requiredEnd;
      break;
    }
    return (start: start, end: end > start ? end : audioEnd);
  }

  /// Builds a standard 44-byte WAV header for PCM 16kHz 16-bit mono audio.
  static Uint8List buildWavHeader(int dataLength) {
    final header = Uint8List(44);
    final bdata = ByteData.view(header.buffer);

    // RIFF header
    header.setRange(0, 4, 'RIFF'.codeUnits);
    bdata.setUint32(4, 36 + dataLength, Endian.little);
    header.setRange(8, 12, 'WAVE'.codeUnits);

    // fmt subchunk
    header.setRange(12, 16, 'fmt '.codeUnits);
    bdata.setUint32(16, 16, Endian.little);             // Subchunk1Size = 16
    bdata.setUint16(20, 1, Endian.little);              // AudioFormat = 1 (PCM)
    bdata.setUint16(22, channels, Endian.little);       // NumChannels
    bdata.setUint32(24, sampleRate, Endian.little);     // SampleRate
    bdata.setUint32(28, bytesPerSecond, Endian.little); // ByteRate
    bdata.setUint16(32, bytesPerSample, Endian.little); // BlockAlign
    bdata.setUint16(34, bitsPerSample, Endian.little);  // BitsPerSample

    // data subchunk
    header.setRange(36, 40, 'data'.codeUnits);
    bdata.setUint32(40, dataLength, Endian.little);

    return header;
  }

  /// Finds the offset of the 'data' chunk in a WAV file, or returns 44 as default.
  static Future<int> findDataChunkOffset(RandomAccessFile raf) async {
    await raf.setPosition(0);
    final headerBytes = await raf.read(64);
    if (headerBytes.length < 44) return 44;

    // Search for "data" ASCII marker
    for (int i = 12; i <= headerBytes.length - 8; i++) {
      if (headerBytes[i] == 0x64 &&      // 'd'
          headerBytes[i + 1] == 0x61 &&  // 'a'
          headerBytes[i + 2] == 0x74 &&  // 't'
          headerBytes[i + 3] == 0x61) {  // 'a'
        return i + 8; // offset where actual PCM audio bytes begin
      }
    }
    return 44;
  }

  /// Extracts a clip from [normalizedWavFile] between [start] and [end]
  /// and saves it to [outputClipFile] using streaming RandomAccessFile.
  /// Memory footprint is strictly bounded to the buffer size (64 KB).
  static Future<File> extractClip({
    required File normalizedWavFile,
    required Duration start,
    required Duration end,
    required File outputClipFile,
  }) async {
    if (!await normalizedWavFile.exists()) {
      throw FileNotFoundException('Source WAV file not found: ${normalizedWavFile.path}');
    }

    final duration = end - start;
    if (duration <= Duration.zero) {
      throw ArgumentError('End timestamp ($end) must be after start timestamp ($start)');
    }

    final parent = outputClipFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final rafIn = await normalizedWavFile.open(mode: FileMode.read);
    final rafOut = await outputClipFile.open(mode: FileMode.write);

    try {
      final dataOffset = await findDataChunkOffset(rafIn);
      final sourceAudioBytes = await normalizedWavFile.length() - dataOffset;

      final startMs = start.inMilliseconds;
      final endMs = end.inMilliseconds;

      // Calculate sample-aligned byte positions
      int startByteOffset = (startMs * bytesPerSecond ~/ 1000);
      startByteOffset -= (startByteOffset % bytesPerSample); // align to 2 bytes

      int endByteOffset = (endMs * bytesPerSecond ~/ 1000);
      endByteOffset -= (endByteOffset % bytesPerSample);

      if (startByteOffset >= sourceAudioBytes) {
        throw ArgumentError('Clip start is beyond source WAV duration');
      }
      if (endByteOffset > sourceAudioBytes) {
        endByteOffset = sourceAudioBytes - (sourceAudioBytes % bytesPerSample);
      }

      final totalAudioBytes = endByteOffset - startByteOffset;
      if (totalAudioBytes <= 0) {
        throw ArgumentError('Clip duration resulted in 0 bytes');
      }

      // Write WAV header
      final header = buildWavHeader(totalAudioBytes);
      await rafOut.writeFrom(header);

      // Seek to clip start position in source file
      final seekTarget = dataOffset + startByteOffset;
      await rafIn.setPosition(seekTarget);

      // Stream copy in 64KB chunks
      const chunkSize = 64 * 1024;
      int bytesRemaining = totalAudioBytes;

      while (bytesRemaining > 0) {
        final toRead = bytesRemaining > chunkSize ? chunkSize : bytesRemaining;
        final buffer = await rafIn.read(toRead);
        if (buffer.isEmpty) break; // EOF reached early
        await rafOut.writeFrom(buffer);
        bytesRemaining -= buffer.length;
      }

      return outputClipFile;
    } finally {
      await rafIn.close();
      await rafOut.close();
    }
  }

  /// Creates a silence WAV file of given duration.
  static Future<File> createSilenceWav({
    required Duration duration,
    required File outputFile,
  }) async {
    final parent = outputFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final dataLength = (duration.inMilliseconds * bytesPerSecond ~/ 1000);
    final alignedDataLength = dataLength - (dataLength % bytesPerSample);

    final header = buildWavHeader(alignedDataLength);
    final raf = await outputFile.open(mode: FileMode.write);
    try {
      await raf.writeFrom(header);
      const chunkSize = 32 * 1024;
      final zeroBuffer = Uint8List(chunkSize); // all zeroes represents PCM silence
      int remaining = alignedDataLength;
      while (remaining > 0) {
        final toWrite = remaining > chunkSize ? chunkSize : remaining;
        await raf.writeFrom(zeroBuffer, 0, toWrite);
        remaining -= toWrite;
      }
      return outputFile;
    } finally {
      await raf.close();
    }
  }
}

class FileNotFoundException implements Exception {
  final String message;
  FileNotFoundException(this.message);
  @override
  String toString() => message;
}
