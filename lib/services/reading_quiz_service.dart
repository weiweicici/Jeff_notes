import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../data/pathways_content.dart';
import '../models.dart';
import '../prompt_provider.dart';

class ReadingQuizService {
  static Future<String> _callGroq(String systemPrompt, {String userMessage = '请生成'}) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key_groq') ?? '';
    if (apiKey.isEmpty) return '[AI 服务未配置，请在设置中填写 API Key]';

    try {
      final response = await http
          .post(
            Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'llama-3.3-70b-versatile',
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

  static Future<String> generateQuiz(String text) =>
      _callGroq(PromptProvider.getReadingQuizPrompt(), userMessage: text);

  static Future<String> getSummary(String text) =>
      _callGroq(PromptProvider.getReadingSummaryPrompt(), userMessage: text);

  static Future<String> getTranslation(String text) =>
      _callGroq(PromptProvider.getReadingTranslationPrompt(), userMessage: text);

  static Future<String> getParaphrase(String text) =>
      _callGroq(PromptProvider.getReadingParaphrasePrompt(), userMessage: text);

  static Future<String> getVocabulary(String text) =>
      _callGroq(PromptProvider.getReadingVocabularyPrompt(), userMessage: text);

  static Future<String> getPathwaysContent(PathwaysUnit unit) =>
      _callGroq(PromptProvider.getPathwaysUnitPrompt(unit));

  /// 优先返回内置本地数据，无本地数据时返回 null
  static String? getPathwaysLocalContent(PathwaysUnit unit) =>
      PathwaysContent.units[unit];
}
