import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'credential_store.dart';
import '../prompt_provider.dart';
import '../models.dart';

class GrammarService {
  static const String _groqUrl = 'https://api.groq.com/openai/v1/chat/completions';
  static const String _groqModel = 'openai/gpt-oss-120b';
  static const String _geminiModel = 'gemini-2.5-flash';

  static Future<String?> _callAI(String systemPrompt, String userMessage) async {
    // Try Gemini first
    final geminiKey = await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
        );
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {'parts': [{'text': systemPrompt}]},
            'contents': [{'parts': [{'text': userMessage}]}],
            'generationConfig': {'temperature': 0.5},
          }),
        ).timeout(const Duration(seconds: 60));

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
        debugPrint('[GrammarService] Gemini failed (${response.statusCode}), falling back to Groq...');
      } catch (e) {
        debugPrint('[GrammarService] Gemini exception: $e, falling back to Groq...');
      }
    }

    // Fallback: Groq
    final groqKey = await CredentialStore.instance.readKey(CredentialStore.keyGroq);
    if (groqKey == null || groqKey.isEmpty) return '请先在设置中配置 Groq 或 Gemini API Key';

    try {
      final response = await http.post(
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
    GrammarUnit unit, String theme, {
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

  /// 综合写作范文（覆盖多个 Part）
  static Future<String> generateCombinedSample(
    List<GrammarPart> parts, String theme,
  ) async {
    final partIds = parts.map((p) => p.id).toList();
    final partTitles = parts.map((p) => p.title).toList();
    final partRequirements = partIds.map((id) => PromptProvider.getWritingRequirement(id)).toList();

    final prompt = PromptProvider.getCombinedWritingPrompt(
      partIds,
      partTitles,
      partRequirements,
    );
    final partsDesc = partTitles.join('、');
    final userMsg = '请写一篇关于 "$theme" 的范文，必须同时使用以下语法章节的核心语法结构：$partsDesc';
    return await _callAI(prompt, userMsg) ?? '生成失败';
  }
}
