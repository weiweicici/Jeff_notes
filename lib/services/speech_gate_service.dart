import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Metrics describing the energy and speech likelihood of an audio slice.
class AudioSignalMetrics {
  final double rmsDb;
  final int peak;
  final bool hasAudibleSpeech;
  final bool isLowEnergy;
  final bool isDigitalSilence;

  const AudioSignalMetrics({
    required this.rmsDb,
    required this.peak,
    required this.hasAudibleSpeech,
    required this.isLowEnergy,
    this.isDigitalSilence = false,
  });

  const AudioSignalMetrics.silent()
    : rmsDb = -100.0,
      peak = 0,
      hasAudibleSpeech = false,
      isLowEnergy = true,
      isDigitalSilence = true;

  /// An unclassified or non-silent signal.  Conservative callers must send it
  /// to STT rather than treating it as digital silence.
  const AudioSignalMetrics.unknown()
    : rmsDb = -100.0,
      peak = 0,
      hasAudibleSpeech = true,
      isLowEnergy = false,
      isDigitalSilence = false;

  @override
  String toString() =>
      'AudioSignalMetrics(rmsDb: ${rmsDb.toStringAsFixed(1)} dB, peak: $peak, audible: $hasAudibleSpeech, lowEnergy: $isLowEnergy)';
}

/// [Meetily-Style Speech Gate]
/// Pre-STT energy gate (Layer A) + STT hallucination guard (Layer B).
///
/// Prevents sending silent/near-silent audio slices to cloud STT providers,
/// cutting wasted API costs and suppressing common Whisper hallucinations
/// ("Thank you", "Bye", etc.) on faint background noise.
class SpeechGateService {
  // Layer A: Pre-STT speech/energy gate thresholds
  static const double defaultRmsThresholdDb = -48.0;
  static const int defaultPeakThreshold = 80;

  // Layer B: STT Hallucination Guard thresholds
  // Faint room noise that slips past Layer A rarely exceeds these thresholds.
  static const double defaultHallucinationMaxRmsDb = -36.0;
  static const int defaultHallucinationMaxPeak = 600;

  /// Phrases commonly hallucinated by Whisper on near-silence / ambient noise.
  static final Set<String> _hallucinationPhrases = {
    'thank you',
    'thank you.',
    'thanks',
    'thanks.',
    'thanks for watching',
    'thanks for watching.',
    'thank you for watching',
    'thank you for watching.',
    'bye',
    'bye.',
    'bye bye',
    'bye-bye',
    'goodbye',
    'goodbye.',
    'you',
    'you.',
    'subtitles by',
    'subtitle by',
  };

  /// Analyzes a 16-bit PCM WAV file and extracts energy metrics.
  static Future<AudioSignalMetrics> analyzeWav(
    String filePath, {
    double rmsThresholdDb = defaultRmsThresholdDb,
    int peakThreshold = defaultPeakThreshold,
    double hallucinationMaxRmsDb = defaultHallucinationMaxRmsDb,
    int hallucinationMaxPeak = defaultHallucinationMaxPeak,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return const AudioSignalMetrics.unknown();
      final bytes = await file.readAsBytes();
      return analyzeBytes(
        bytes,
        rmsThresholdDb: rmsThresholdDb,
        peakThreshold: peakThreshold,
        hallucinationMaxRmsDb: hallucinationMaxRmsDb,
        hallucinationMaxPeak: hallucinationMaxPeak,
      );
    } catch (_) {
      return const AudioSignalMetrics.unknown();
    }
  }

  /// Analyzes raw WAV bytes in memory.
  static AudioSignalMetrics analyzeBytes(
    Uint8List bytes, {
    double rmsThresholdDb = defaultRmsThresholdDb,
    int peakThreshold = defaultPeakThreshold,
    double hallucinationMaxRmsDb = defaultHallucinationMaxRmsDb,
    int hallucinationMaxPeak = defaultHallucinationMaxPeak,
  }) {
    // Do not interpret arbitrary bytes at offset 44 as PCM.  A valid fmt and
    // bounded data chunk are required before silence can be established.
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      return const AudioSignalMetrics.unknown();
    }

    final data = ByteData.sublistView(bytes);
    final riffLength = data.getUint32(4, Endian.little);
    final riffEnd = riffLength + 8;
    if (riffEnd < 12 || riffEnd > bytes.length) {
      return const AudioSignalMetrics.unknown();
    }

    var offset = 12;
    var validPcm = false;
    var dataStart = 0;
    var dataLength = 0;
    while (offset + 8 <= riffEnd) {
      final chunkLength = data.getUint32(offset + 4, Endian.little);
      final chunkStart = offset + 8;
      final chunkEnd = chunkStart + chunkLength;
      if (chunkEnd < chunkStart || chunkEnd > riffEnd) {
        return const AudioSignalMetrics.unknown();
      }
      final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      if (chunkId == 'fmt ' && chunkLength >= 16) {
        final format = data.getUint16(chunkStart, Endian.little);
        final channels = data.getUint16(chunkStart + 2, Endian.little);
        final blockAlign = data.getUint16(chunkStart + 12, Endian.little);
        final bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
        validPcm =
            format == 1 &&
            channels > 0 &&
            bitsPerSample == 16 &&
            blockAlign == channels * 2;
      }
      if (chunkId == 'data') {
        dataStart = chunkStart;
        dataLength = chunkLength;
        break;
      }
      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }

    if (!validPcm ||
        dataLength < 2 ||
        dataLength.isOdd ||
        dataStart + dataLength > bytes.length) {
      return const AudioSignalMetrics.unknown();
    }

    var sumSquares = 0.0;
    var peak = 0;
    var samples = 0;
    final end = dataStart + dataLength;

    // Scan every sample.  Striding can miss a short burst entirely depending
    // on its phase, turning real non-zero PCM into apparent digital silence.
    for (var offset = dataStart; offset < end; offset += 2) {
      final value = data.getInt16(offset, Endian.little).abs();
      peak = math.max(peak, value);
      final normalized = value / 32768.0;
      sumSquares += normalized * normalized;
      samples++;
    }

    final rms = math.sqrt(sumSquares / samples);
    if (peak == 0 || rms <= 0) return const AudioSignalMetrics.silent();

    final rmsDb = 20 * math.log(rms) / math.ln10;
    // Energy thresholds remain API-compatible telemetry knobs, but are not
    // deletion evidence: every valid non-zero signal fails open to STT.
    final hasAudibleSpeech = true;
    final isLowEnergy = false;

    return AudioSignalMetrics(
      rmsDb: rmsDb,
      peak: peak,
      hasAudibleSpeech: hasAudibleSpeech,
      isLowEnergy: isLowEnergy,
    );
  }

  /// Layer B: Detects whether a transcription output is a hallucination
  /// produced on a slice with low energy evidence.
  ///
  /// Does NOT globally blacklist phrases because legitimate speakers may say them.
  /// Only suppresses when evidence shows low energy / near-silence.
  static bool isSuspiciousHallucination(
    String transcript,
    AudioSignalMetrics metrics,
  ) {
    // A low RMS/peak pair is not independent evidence of hallucination.
    // Only the analyzer's proven digital-zero result may suppress text.
    if (!metrics.isDigitalSilence) return false;

    final normalized = transcript
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized.isEmpty) return false;

    return _hallucinationPhrases.contains(normalized);
  }
}
