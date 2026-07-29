import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vocab_card.dart';

class VocabExtractorService {
  static const String _geminiModel = 'gemini-2.5-flash';

  static Future<List<VocabCard>> extractFromText(
    String fullText, {
    required String sourceTitle,
  }) async {
    if (fullText.trim().isEmpty) return [];

    final prefs = await SharedPreferences.getInstance();
    final geminiKey = prefs.getString('api_key_gemini') ?? '';

    final prompt = """You are an expert English linguist and academic exam coach. Analyze the following text and extract 4 to 6 key items consisting of:
1. High-frequency academic vocabulary words or collocations/phrases.
2. 1 or 2 complex long sentences with deep grammar breakdown.

Respond STRICTLY in valid JSON array format, with NO Markdown wrapping, NO explanation outside JSON.
Each JSON object must have:
- "wordOrPhrase": The key English word, phrase, or sentence excerpt.
- "phonetic": IPA pronunciation if it's a word/phrase (null if long sentence).
- "definition": Chinese translation & academic usage tip.
- "exampleSentence": The exact original sentence from the text containing this item.
- "exampleTranslation": Precise Chinese translation of the example sentence.
- "grammarBreakdown": Grammatical analysis (syntax structure, clause type, exam significance, transition function).

JSON schema:
[
  {
    "wordOrPhrase": "financial burden",
    "phonetic": "/faɪˈnænʃl ˈbɜːdn/",
    "definition": "财务负担（写作高频对比短语）",
    "exampleSentence": "Providing free meals significantly reduces the financial burden on families.",
    "exampleTranslation": "提供免费午餐能显著减轻家庭的财务负担。",
    "grammarBreakdown": "【语法结构】动名词作主语(Providing...) + 动词谓语(reduces) + 宾语(financial burden)。"
  }
]

Text to analyze:
$fullText""";

    // Try Gemini first
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
        );
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'system_instruction': {'parts': [{'text': 'You are an academic English flashcard generator. Output JSON array only.'}]},
            'contents': [{'parts': [{'text': prompt}]}],
            'generationConfig': {'temperature': 0.3},
          }),
        ).timeout(const Duration(seconds: 45));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates[0]['content']?['parts'] as List?;
            if (parts != null && parts.isNotEmpty) {
              var text = parts[0]['text'] as String?;
              if (text != null) {
                text = text.trim();
                if (text.startsWith('```')) {
                  text = text.replaceAll(RegExp(r'^```(json)?\n?'), '').replaceAll(RegExp(r'\n?```$'), '').trim();
                }
                final jsonList = jsonDecode(text) as List;
                return _parseVocabCards(jsonList, sourceTitle);
              }
            }
          }
        }
        debugPrint('[VocabExtractor] Gemini failed (${response.statusCode}), falling back to Groq...');
      } catch (e) {
        debugPrint('[VocabExtractor] Gemini exception: $e, falling back to Groq...');
      }
    }

    // Fallback: Groq
    final groqKey = prefs.getString('api_key_groq') ?? prefs.getString('api_key_siliconflow') ?? '';
    if (groqKey.isEmpty) {
      throw Exception('请先在设置页面配置 API Key');
    }

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
                {'role': 'system', 'content': 'You are an academic English flashcard generator. Output JSON array only.'},
                {'role': 'user', 'content': prompt},
              ],
              'temperature': 0.3,
            }),
          )
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('API 请求失败 HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body);
      var responseText = (data['choices'][0]['message']['content'] as String).trim();

      if (responseText.startsWith('```')) {
        responseText = responseText.replaceAll(RegExp(r'^```(json)?\n?'), '').replaceAll(RegExp(r'\n?```$'), '').trim();
      }

      final jsonList = jsonDecode(responseText) as List;
      return _parseVocabCards(jsonList, sourceTitle);
    } catch (e) {
      debugPrint('[VocabExtractor Error] $e');
      rethrow;
    }
  }

  static List<VocabCard> _parseVocabCards(List jsonList, String sourceTitle) {
    final results = <VocabCard>[];
    final now = DateTime.now();
    for (int i = 0; i < jsonList.length; i++) {
      final item = jsonList[i] as Map<String, dynamic>;
      results.add(VocabCard(
        id: '${now.millisecondsSinceEpoch}_$i',
        wordOrPhrase: item['wordOrPhrase'] as String? ?? '',
        phonetic: item['phonetic'] as String?,
        definition: item['definition'] as String? ?? '',
        exampleSentence: item['exampleSentence'] as String? ?? '',
        exampleTranslation: item['exampleTranslation'] as String? ?? '',
        grammarBreakdown: item['grammarBreakdown'] as String? ?? '',
        sourceTitle: sourceTitle,
        createdAt: now,
      ));
    }
    return results;
  }
}
