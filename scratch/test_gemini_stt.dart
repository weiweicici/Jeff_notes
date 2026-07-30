import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

Uint8List generateTestWav(int durationSeconds) {
  final sampleRate = 16000;
  final numSamples = sampleRate * durationSeconds;
  final pcmBytes = ByteData(numSamples * 2);
  
  // 440 Hz sine wave for test audio
  for (int i = 0; i < numSamples; i++) {
    final sample = (sin(2 * pi * 440 * i / sampleRate) * 10000).toInt();
    pcmBytes.setInt16(i * 2, sample, Endian.little);
  }

  final header = ByteData(44);
  final dataSize = pcmBytes.lengthInBytes;

  header.setUint8(0, 0x52); header.setUint8(1, 0x49); header.setUint8(2, 0x46); header.setUint8(3, 0x46); // "RIFF"
  header.setUint32(4, 36 + dataSize, Endian.little);
  header.setUint8(8, 0x57); header.setUint8(9, 0x41); header.setUint8(10, 0x56); header.setUint8(11, 0x45); // "WAVE"
  header.setUint8(12, 0x66); header.setUint8(13, 0x6D); header.setUint8(14, 0x74); header.setUint8(15, 0x20); // "fmt "
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // Mono
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  header.setUint8(36, 0x64); header.setUint8(37, 0x61); header.setUint8(38, 0x74); header.setUint8(39, 0x61); // "data"
  header.setUint32(40, dataSize, Endian.little);

  final wav = Uint8List(44 + dataSize);
  wav.setRange(0, 44, header.buffer.asUint8List());
  wav.setRange(44, 44 + dataSize, pcmBytes.buffer.asUint8List());
  return wav;
}

Future<void> main() async {
  print("=== TESTING GEMINI 2.5 FLASH AUDIO STT API ===");
  final apiKey = "AIzaSyBU1TeaDmBB46HbVvrndasc4MmZ5QcKPOA";
  final wavBytes = generateTestWav(3);
  final base64Audio = base64Encode(wavBytes);

  print("Generated test WAV: ${wavBytes.length} bytes (Base64 len: ${base64Audio.length})");

  final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$apiKey");

  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'system_instruction': {
          'parts': [
            {
              'text':
                  'You are an expert English speech-to-text transcriber. Transcribe the given audio slice into raw English text. Output ONLY the clean transcribed English text with no markdown, no quotes, no explanations. If the audio contains only tone or silence, output [Silence].'
            }
          ]
        },
        'contents': [
          {
            'parts': [
              {
                'inline_data': {
                  'mime_type': 'audio/wav',
                  'data': base64Audio,
                }
              },
              {'text': 'Transcribe this English audio recording slice.'}
            ]
          }
        ],
        'generationConfig': {'temperature': 0.1},
      }),
    ).timeout(const Duration(seconds: 15));

    print("HTTP Response Code: ${response.statusCode}");
    print("Response Body:\n${response.body}");

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
      print("\n✅ SUCCESS! Gemini 2.5 Flash returned: \"$text\"");
    } else {
      print("\n❌ FAILED with status ${response.statusCode}");
    }
  } catch (e) {
    print("\n❌ EXCEPTION: $e");
  }
}
