import 'dart:io';
import 'dart:typed_data';

/// Joins mono 16 kHz, 16-bit PCM WAV slices into one playable WAV file.
class WavStitchService {
  const WavStitchService._();

  static Future<bool> stitch({
    required List<String> inputPaths,
    required String outputPath,
  }) async {
    final pcm = <int>[];
    for (final path in inputPaths) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      final offset = dataOffset(bytes);
      if (bytes.length > offset) pcm.addAll(bytes.sublist(offset));
    }
    if (pcm.isEmpty) return false;

    final output = File(outputPath);
    final temp = File('$outputPath.tmp');
    await temp.writeAsBytes(<int>[
      ...wavHeader(pcm.length),
      ...pcm,
    ], flush: true);
    if (await output.exists()) await output.delete();
    await temp.rename(outputPath);
    return await output.exists() && await output.length() > 44;
  }

  static int dataOffset(Uint8List bytes) {
    if (bytes.length < 12 ||
        bytes[0] != 0x52 ||
        bytes[1] != 0x49 ||
        bytes[2] != 0x46 ||
        bytes[3] != 0x46 ||
        bytes[8] != 0x57 ||
        bytes[9] != 0x41 ||
        bytes[10] != 0x56 ||
        bytes[11] != 0x45) {
      return bytes.length >= 44 ? 44 : bytes.length;
    }

    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final isData =
          bytes[offset] == 0x64 &&
          bytes[offset + 1] == 0x61 &&
          bytes[offset + 2] == 0x74 &&
          bytes[offset + 3] == 0x61;
      if (isData) return offset + 8;
      final chunkSize =
          bytes[offset + 4] |
          (bytes[offset + 5] << 8) |
          (bytes[offset + 6] << 16) |
          (bytes[offset + 7] << 24);
      offset += 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }
    return bytes.length >= 44 ? 44 : bytes.length;
  }

  static Uint8List wavHeader(int pcmLength) {
    final header = ByteData(44)
      ..setUint32(4, 36 + pcmLength, Endian.little)
      ..setUint32(16, 16, Endian.little)
      ..setUint16(20, 1, Endian.little)
      ..setUint16(22, 1, Endian.little)
      ..setUint32(24, 16000, Endian.little)
      ..setUint32(28, 32000, Endian.little)
      ..setUint16(32, 2, Endian.little)
      ..setUint16(34, 16, Endian.little)
      ..setUint32(40, pcmLength, Endian.little);
    const ascii = <int>[
      0x52, 0x49, 0x46, 0x46, // RIFF
      0, 0, 0, 0,
      0x57, 0x41, 0x56, 0x45, // WAVE
      0x66, 0x6d, 0x74, 0x20, // fmt
    ];
    for (var i = 0; i < ascii.length; i++) {
      if (ascii[i] != 0) header.setUint8(i, ascii[i]);
    }
    header
      ..setUint8(36, 0x64)
      ..setUint8(37, 0x61)
      ..setUint8(38, 0x74)
      ..setUint8(39, 0x61);
    return header.buffer.asUint8List();
  }
}
