import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/nait_learning/services/nait_audio_extract_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_audio_playback_service.dart';
import 'package:jeff_notes/nait_learning/models/nait_transcript_entry.dart';
import 'package:jeff_notes/services/wav_stitch_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nait_audio_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Helper to create a dummy PCM WAV file with test duration
  Future<File> createTestPcmWav(String fileName, Duration duration) async {
    final file = File('${tempDir.path}/$fileName');
    final pcmBytes = duration.inMilliseconds * NaitAudioExtractService.bytesPerSecond ~/ 1000;
    final alignedBytes = pcmBytes - (pcmBytes % NaitAudioExtractService.bytesPerSample);

    final header = NaitAudioExtractService.buildWavHeader(alignedBytes);
    final raf = await file.open(mode: FileMode.write);
    await raf.writeFrom(header);

    // Write deterministic sine/test byte pattern
    final buffer = Uint8List(alignedBytes);
    for (int i = 0; i < alignedBytes; i++) {
      buffer[i] = (i % 256);
    }
    await raf.writeFrom(buffer);
    await raf.close();
    return file;
  }

  test('1. buildWavHeader produces valid 44-byte PCM 16kHz 16-bit mono header', () {
    const pcmLength = 32000; // 1 second of audio
    final header = NaitAudioExtractService.buildWavHeader(pcmLength);

    expect(header.length, 44);

    final bdata = ByteData.view(header.buffer);
    // ChunkID = RIFF
    expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
    // ChunkSize = 36 + pcmLength
    expect(bdata.getUint32(4, Endian.little), 36 + pcmLength);
    // Format = WAVE
    expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
    // NumChannels = 1 (mono)
    expect(bdata.getUint16(22, Endian.little), 1);
    // SampleRate = 16000
    expect(bdata.getUint32(24, Endian.little), 16000);
    // ByteRate = 32000
    expect(bdata.getUint32(28, Endian.little), 32000);
    // BitsPerSample = 16
    expect(bdata.getUint16(34, Endian.little), 16);
    // Subchunk2ID = data
    expect(String.fromCharCodes(header.sublist(36, 40)), 'data');
    // Subchunk2Size = pcmLength
    expect(bdata.getUint32(40, Endian.little), pcmLength);
  });

  test('2. createSilenceWav creates exact silence duration with zeroed PCM data', () async {
    final silenceFile = File('${tempDir.path}/silence.wav');
    await NaitAudioExtractService.createSilenceWav(
      duration: const Duration(milliseconds: 800),
      outputFile: silenceFile,
    );

    expect(await silenceFile.exists(), isTrue);

    // 800 ms at 32000 bytes/s = 25600 bytes + 44 bytes header = 25644 bytes
    final length = await silenceFile.length();
    expect(length, 25644);

    final bytes = await silenceFile.readAsBytes();
    // Check PCM payload is all zeroes
    for (int i = 44; i < bytes.length; i++) {
      expect(bytes[i], 0, reason: 'PCM silence payload must be zero');
    }
  });

  test('3. extractClip extracts exact sub-range without altering source file', () async {
    // Create a 10-second source WAV file
    final sourceFile = await createTestPcmWav('source.wav', const Duration(seconds: 10));
    final originalLength = await sourceFile.length();

    final clipFile = File('${tempDir.path}/clip1.wav');
    // Extract 2 seconds: from second 3 to second 5
    await NaitAudioExtractService.extractClip(
      normalizedWavFile: sourceFile,
      start: const Duration(seconds: 3),
      end: const Duration(seconds: 5),
      outputClipFile: clipFile,
    );

    expect(await clipFile.exists(), isTrue);
    // 2 seconds at 32000 B/s = 64000 bytes PCM + 44 byte header = 64044 bytes
    expect(await clipFile.length(), 64044);

    // Verify original source file was NOT modified
    expect(await sourceFile.length(), originalLength);
  });

  test('4. Week pack combines multiple clips with silence gap using WavStitchService', () async {
    final clip1 = await createTestPcmWav('c1.wav', const Duration(seconds: 2));
    final clip2 = await createTestPcmWav('c2.wav', const Duration(seconds: 3));

    final silenceFile = File('${tempDir.path}/gap.wav');
    await NaitAudioExtractService.createSilenceWav(
      duration: const Duration(milliseconds: 800),
      outputFile: silenceFile,
    );

    final packFile = File('${tempDir.path}/weekly_pack.wav');
    final success = await WavStitchService.stitch(
      inputPaths: [clip1.path, silenceFile.path, clip2.path],
      outputPath: packFile.path,
    );

    expect(success, isTrue);
    expect(await packFile.exists(), isTrue);

    // Total PCM duration: 2s (64000) + 0.8s (25600) + 3s (96000) = 185600 bytes + 44 = 185644
    expect(await packFile.length(), 185644);
  });

  test('5. Conservative bounds retain a phrase tail without entering next segment', () async {
    const entries = [
      NaitTranscriptEntry(
        timestamp: Duration(seconds: 4),
        endTimestamp: Duration(milliseconds: 6200),
        text: 'Complete phrase including final teacher words.',
      ),
      NaitTranscriptEntry(
        timestamp: Duration(milliseconds: 6300),
        endTimestamp: Duration(seconds: 7),
        text: 'Unrelated next utterance.',
      ),
    ];
    final bounds = NaitAudioExtractService.resolveConservativeClipBounds(
      audioStart: const Duration(seconds: 3),
      audioEnd: const Duration(seconds: 5),
      transcriptEntries: entries,
    );
    expect(bounds.start, const Duration(milliseconds: 2600));
    expect(bounds.end, const Duration(milliseconds: 6200));

    final source = await createTestPcmWav('tail_source.wav', const Duration(seconds: 10));
    final clip = File('${tempDir.path}/tail_clip.wav');
    await NaitAudioExtractService.extractClip(
      normalizedWavFile: source,
      start: bounds.start,
      end: bounds.end,
      outputClipFile: clip,
    );
    // 3.6 seconds at 32,000 bytes/s plus the 44-byte WAV header.
    expect(await clip.length(), 115244);

    final pack = File('${tempDir.path}/tail_pack.wav');
    expect(await WavStitchService.stitch(inputPaths: [clip.path], outputPath: pack.path), isTrue);
    expect(await pack.length(), await clip.length());
  });

  test('6. Playback path rebases across an iOS Documents container change', () async {
    final currentDocuments = Directory('${tempDir.path}/current/Documents')
      ..createSync(recursive: true);
    final clip = File('${currentDocuments.path}/nait/course/week_01/class_a/clips/clip_001.wav')
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    const stalePath = '/var/mobile/Containers/Data/Application/OLD/Documents/'
        'nait/course/week_01/class_a/clips/clip_001.wav';

    final resolved = await NaitAudioPlaybackService.resolvePersistedWavPath(
      stalePath,
      currentDocuments,
    );
    expect(resolved, clip.path);
  });
}
