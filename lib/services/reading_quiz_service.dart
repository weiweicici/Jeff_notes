import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'credential_store.dart';
import '../prompt_provider.dart';

class ReadingQuizService {
  static const String _geminiModel = 'gemini-2.5-flash';

  static Future<String> _callAI(
    String systemPrompt, {
    String userMessage = '请生成',
  }) async {
    // Try Gemini first
    final geminiKey =
        await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
        );
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'system_instruction': {
                  'parts': [
                    {'text': systemPrompt},
                  ],
                },
                'contents': [
                  {
                    'parts': [
                      {'text': userMessage},
                    ],
                  },
                ],
                'generationConfig': {'temperature': 0.5},
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts[0]['text'] as String?;
              if (text != null && text.trim().isNotEmpty) return text.trim();
            }
          }
        }
        debugPrint(
          '[ReadingQuiz] Gemini failed (${response.statusCode}), falling back to Groq...',
        );
      } catch (e) {
        debugPrint(
          '[ReadingQuiz] Gemini exception: $e, falling back to Groq...',
        );
      }
    }

    // Fallback: Groq
    final groqKey =
        await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';
    if (groqKey.isEmpty) return '[AI 服务未配置，请在设置中填写 API Key]';

    try {
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $groqKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'openai/gpt-oss-120b',
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userMessage},
              ],
              'temperature': 0.5,
            }),
          )
          .timeout(const Duration(seconds: 90));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      }
      return '[请求失败: HTTP ${response.statusCode}]';
    } on TimeoutException {
      return '[请求超时，请重试]';
    } catch (e) {
      return '[错误: $e]';
    }
  }

  static Future<String> getTranslation(String text) =>
      _callAI(PromptProvider.getReadingTranslationPrompt(), userMessage: text);

  static Future<String> getParaphrase(String text) =>
      _callAI(PromptProvider.getReadingParaphrasePrompt(), userMessage: text);
}
