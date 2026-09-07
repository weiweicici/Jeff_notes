import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'credential_store.dart';
import '../prompt_provider.dart';
import '../models.dart';

class GrammarService {
  static const String _groqUrl =
      'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'openai/gpt-oss-120b';
  static const String _geminiModel = 'gemini-2.5-flash';
  static const String _openRouterUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  // This is used only after Gemini and Groq fail, so it protects the user's
  // paid OpenRouter balance while still giving writing practice a reliable end.
  static const String _openRouterModel = 'google/gemini-2.5-flash-lite';

  static Future<String?> _callAI(
    String systemPrompt,
    String userMessage,
  ) async {
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
          '[GrammarService] Gemini failed (${response.statusCode}), falling back to Groq...',
        );
      } catch (e) {
        debugPrint(
          '[GrammarService] Gemini exception: $e, falling back to Groq...',
        );
      }
    }

    // Second choice: Groq
    final groqKey = await CredentialStore.instance.readKey(
      CredentialStore.keyGroq,
    );
    if (groqKey != null && groqKey.isNotEmpty) {
      try {
        final response = await http
            .post(
              Uri.parse(_groqUrl),
              headers: {
                'Authorization': 'Bearer $groqKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': _groqModel,
                'messages': [
                  {'role': 'system', 'content': systemPrompt},
                  {'role': 'user', 'content': userMessage},
                ],
                'temperature': 0.5,
                'max_tokens': 2048,
              }),
            )
            .timeout(const Duration(seconds: 60));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return data['choices'][0]['message']['content'] as String;
        } else {
          debugPrint(
            '[GrammarService] Groq failed (${response.statusCode}), falling back to OpenRouter...',
          );
        }
      } catch (e) {
        debugPrint(
          '[GrammarService] Groq exception: $e, falling back to OpenRouter...',
        );
      }
    }

    // Final paid fallback: OpenRouter.
    final openRouterKey = await CredentialStore.instance.readKey(
      CredentialStore.keyOpenRouter,
    );
    if (openRouterKey == null || openRouterKey.isEmpty) {
      return 'Gemini 和 Groq 都未成功，请在设置中配置 OpenRouter API Key 作为备用。';
    }

    try {
      final response = await http
          .post(
            Uri.parse(_openRouterUrl),
            headers: {
              'Authorization': 'Bearer $openRouterKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': _openRouterModel,
              'messages': [
                {'role': 'system', 'content': systemPrompt},
                {'role': 'user', 'content': userMessage},
              ],
              'temperature': 0.5,
              'max_tokens': 2048,
            }),
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['choices']?[0]?['message']?['content'] as String?;
        if (text != null && text.trim().isNotEmpty) return text.trim();
      }
      return 'OpenRouter 备用生成失败：${response.statusCode}';
    } catch (e) {
      return 'OpenRouter 备用请求失败：$e';
    }
  }

  /// 生成练习题
  static Future<String> generateExercise(GrammarUnit unit) async {
    final prompt = PromptProvider.getGrammarExercisePrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
    );
    return await _callAI(prompt, '请为 "${unit.title}" 生成 5 道练习题') ?? '生成失败';
  }

  /// 提问语法点
  static Future<String> askQuestion(GrammarUnit unit, String question) async {
    final prompt = PromptProvider.getGrammarQuestionPrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
    );
    return await _callAI(prompt, question) ?? '请求失败';
  }

  /// 批改句子
  static Future<String> correctSentence(String sentence) async {
    final prompt = PromptProvider.getGrammarCorrectionPrompt();
    return await _callAI(prompt, sentence) ?? '请求失败';
  }

  /// 生成写作范文
  static Future<String> generateWritingSample(
    GrammarUnit unit,
    String theme, {
    String partId = '',
    String? focusUnits,
  }) async {
    final prompt = PromptProvider.getGrammarWritingPrompt(
      unit.title,
      unit.chart,
      unit.keyRules,
      partId: partId,
    );
    final focus = focusUnits != null ? '（仅使用以下单元：$focusUnits）' : '';
    final userMsg = '请写一篇关于 "$theme" 的范文，要求使用 "${unit.title}" 的核心语法结构$focus。';
    return await _callAI(prompt, userMsg) ?? '生成失败';
  }

  /// 综合写作范文（可跨 Part 使用老师指定的具体语法）
  static Future<String> generateCombinedSample({
    required List<GrammarPart> availableParts,
    required List<GrammarPart> selectedParts,
    required List<GrammarUnit> selectedUnits,
    required String topic,
    String? contentType,
    bool requireAllSelectedGrammar = false,
  }) async {
    final prompt = PromptProvider.getCombinedWritingPrompt(
      availableParts: availableParts,
      selectedParts: selectedParts,
      selectedUnits: selectedUnits,
      requireAllSelectedGrammar: requireAllSelectedGrammar,
    );
    final userMsg = buildCombinedWritingUserMessage(
      selectedParts: selectedParts,
      selectedUnits: selectedUnits,
      topic: topic,
      contentType: contentType,
      requireAllSelectedGrammar: requireAllSelectedGrammar,
    );
    return await _callAI(prompt, userMsg) ?? '生成失败';
  }

  @visibleForTesting
  static String buildCombinedWritingUserMessage({
    required List<GrammarPart> selectedParts,
    required List<GrammarUnit> selectedUnits,
    required String topic,
    String? contentType,
    bool requireAllSelectedGrammar = false,
  }) {
    final sections = <String>[];
    final cleanTopic = topic.trim();
    final cleanType = contentType?.trim() ?? '';

    if (cleanTopic.isNotEmpty) {
      sections.add('用户输入（可能是完整原题、关键词或简短要求）：\n$cleanTopic');
    }
    if (cleanType.isNotEmpty) {
      sections.add('选择的内容类型：\n$cleanType');
    }
    if (cleanTopic.isEmpty && cleanType.isEmpty) {
      sections.add('没有指定题目或内容类型，请选择一个适合练习所学语法的简单主题。');
    }

    if (selectedParts.isNotEmpty) {
      sections.add(
        '选择的语法章节（作为选用范围）：\n- '
        '${selectedParts.map((part) => part.title).join('\n- ')}',
      );
    }
    if (selectedUnits.isNotEmpty) {
      sections.add(
        '选择的具体语法（优先使用；覆盖规则见系统要求）：\n- '
        '${selectedUnits.map((unit) => unit.title).join('\n- ')}',
      );
    }
    if (requireAllSelectedGrammar &&
        (selectedUnits.isNotEmpty || selectedParts.isNotEmpty)) {
      sections.add('老师明确要求：所有已选语法范围都必须覆盖。');
    }
    if (selectedParts.isEmpty && selectedUnits.isEmpty) {
      sections.add('没有指定语法，请从不同章节自动选择 4–6 种适合该主题的语法。');
    }

    sections.add('输入题目是最高优先级；内容类型只能补充题目，不能覆盖或改变题意。');
    return sections.join('\n\n');
  }
}
