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
    "Is it possible to optimize the objective function using gradient descent?",
    "Hello."
  ];

  print("=== TESTING QWEN TRANSLATION OUTPUTS ===");
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
              'content': 'You are a professional academic simultaneous interpreter. '
                         'Your task: translate English academic lecture notes/utterances into natural, fluent, scholarly Chinese. '
                         'Important: The input is a real-time 5-second slice. It might be an unfinished sentence. '
                         'Rules: '
                         '1. Translate ONLY what is in the input. '
                         '2. If the input ends without punctuation (like . ? !), it is an unfinished clause. Translate it in a natural "hanging/unfinished" tone to ensure it seamlessly connects to the next chunk. Do NOT append final periods. '
                         '3. Keep proper nouns in their original form. For uncertain terms, keep the English with a Chinese translation in parentheses. '
                         '4. Output ONLY the translated Chinese text. No notes, no explanations, no markup.'
            },
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.1,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final rawContent = data['choices'][0]['message']['content'] as String;
        print("Raw Output:  \"$rawContent\"");
        print("Represent:   ${jsonEncode(rawContent)}");
      } else {
        print("Error ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      print("Request Error: $e");
    }
  }
}
