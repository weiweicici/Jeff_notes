import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../prompt_provider.dart';
import '../models.dart';

class GrammarService {
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _model = 'openai/gpt-oss-120b';

  static Future<String?> _callGroq(String systemPrompt, String userMessage) async {
    final prefs = await SharedPreferences.getInstance();
    final apiKey = prefs.getString('api_key_groq');
    if (apiKey == null || apiKey.isEmpty) return '请先在设置中配置 Groq API Key';

    try {
      final response = await http.post(
        Uri.parse(_groqUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': _model,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userMessage},
          ],
          'temperature': 0.5,
          'max_tokens': 2048,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        return 'AI 服务错误: ${response.statusCode}';
      }
    } catch (e) {
      return '请求失败: $e';
    }
  }

  /// 生成练习题
  static Future<String> generateExercise(GrammarUnit unit) async {
    final prompt = PromptProvider.getGrammarExercisePrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
    );
    return await _callGroq(prompt, '请为 "${unit.title}" 生成 5 道练习题') ?? '生成失败';
  }

  /// 提问语法点
  static Future<String> askQuestion(GrammarUnit unit, String question) async {
    final prompt = PromptProvider.getGrammarQuestionPrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
    );
    return await _callGroq(prompt, question) ?? '请求失败';
  }

  /// 批改句子
  static Future<String> correctSentence(String sentence) async {
    final prompt = PromptProvider.getGrammarCorrectionPrompt();
    return await _callGroq(prompt, sentence) ?? '请求失败';
  }

  /// 生成写作范文
  static Future<String> generateWritingSample(GrammarUnit unit, String theme, {String partId = ''}) async {
    final prompt = PromptProvider.getGrammarWritingPrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
      partId: partId,
    );
    final userMsg = '请写一篇关于 "$theme" 的范文，要求使用 "${unit.title}" 的核心语法结构。';
    return await _callGroq(prompt, userMsg) ?? '生成失败';
  }
}
