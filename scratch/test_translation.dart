import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  print("=== STARTING TERMINAL API TESTS ===");

  final geminiKey = "AIzaSyBU1TeaDmBB46HbVvrndasc4MmZ5QcKPOA";
  final siliconKey1 = "sk-xvqruvbtbbcqobglijorfqczmvpfvikouftvapeautkipitqh";
  final siliconKey2 = "sk-xvqruvbtbbcqobglijorfqczmvpfvikouftvapeautkipitq";

  print("\n1. Testing Google Gemini API...");
  await testGemini(geminiKey);

  print("\n2. Testing SiliconFlow with Key 1 (ending in 'h')...");
  await testSiliconFlow(siliconKey1);

  print("\n3. Testing SiliconFlow with Key 2 (ending in 'q')...");
  await testSiliconFlow(siliconKey2);
  
  print("\n=== TESTS COMPLETE ===");
}

Future<void> testGemini(String apiKey) async {
  final url = Uri.parse("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent");
  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey.trim(),
      },
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': 'Hello, translate this to Chinese: "This is a quick terminal test of the translation service."'}
            ]
          }
        ],
        'systemInstruction': {
          'parts': [
            {
              'text': 'Translate the English input into natural Chinese. Output ONLY the translated text.'
            }
          ]
        },
        'generationConfig': {
          'temperature': 0.1,
        }
      }),
    );

    print("Gemini Status Code: ${response.statusCode}");
    print("Gemini Response Body:\n${response.body}\n");
  } catch (e) {
    print("Gemini Request Error: $e");
  }
}

Future<void> testSiliconFlow(String apiKey) async {
  final url = Uri.parse("https://api.siliconflow.cn/v1/chat/completions");
  try {
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: jsonEncode({
        'model': 'Qwen/Qwen2.5-7B-Instruct',
        'messages': [
          {
            'role': 'system',
            'content': 'Translate the English input into natural Chinese. Output ONLY the translated text.'
          },
          {
            'role': 'user',
            'content': 'This is a quick terminal test of the translation service.'
          }
        ],
        'temperature': 0.1,
      }),
    );

    print("SiliconFlow Status Code: ${response.statusCode}");
    print("SiliconFlow Response Body:\n${response.body}\n");
  } catch (e) {
    print("SiliconFlow Request Error: $e");
  }
}
