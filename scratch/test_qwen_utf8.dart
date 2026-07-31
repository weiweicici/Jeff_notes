import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

Future<void> main() async {
  final apiKey = Platform.environment['SILICONFLOW_API_KEY'] ?? "";
  final baseUrl = "https://api.siliconflow.cn/v1";
  final model = "Qwen/Qwen2.5-7B-Instruct";

  final inputs = [
    "So, today we are going to talk about supervised learning algorithms.",
    "First, we will discuss linear regression and how it maps inputs to outputs.",
  ];

  print("=== TESTING UTF-8 DECODING ===");
  for (final text in inputs) {
    print("\nEnglish: \"$text\"");
    final url = Uri.parse("$baseUrl/chat/completions");
    try {
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $apiKey',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content': 'Translate the English input into natural Chinese. Output ONLY the translated text.'
            },
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.1,
        }),
      );

      print("Response Headers Content-Type: ${response.headers['content-type']}");
      
      // Using standard response.body (might be decoded as Latin-1)
      print("Raw response.body:           \"${response.body}\"");

      // Using robust utf8.decode(response.bodyBytes)
      final decodedUtf8 = utf8.decode(response.bodyBytes);
      final data = jsonDecode(decodedUtf8);
      final content = data['choices'][0]['message']['content'] as String;
      print("Decoded via UTF-8:           \"$content\"");
      
    } catch (e) {
      print("Request Error: $e");
    }
  }
}
