import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:async';
import 'prompt_provider.dart';
import 'recording_provider.dart';
import 'models.dart';

class OpenAIService {
  final String apiKey;
  final String baseUrl;
  final String defaultModel;
  final String whisperModel;
  
  http.Client _client = http.Client();
  bool _isDisposed = false;

  OpenAIService({
    required this.apiKey,
    required this.baseUrl,
    required this.defaultModel,
    this.whisperModel = 'whisper-large-v3',
  });

  void dispose() {
    _isDisposed = true;
    _client.close();
  }



  String _sanitizeResponse(String text) {
    String cleaned = text.trim();
    // 移除 AI 常见的开头废话
    final preambleRegex = RegExp(r'^(Here is the review:|Review:|Analysis:|以下是复盘报告[:：]|翻译结果[:：])', caseSensitive: false);
    cleaned = cleaned.replaceFirst(preambleRegex, '').trim();
    
    // [Fix] 移除 AI 常见的末尾备注 (Note: ...)
    final noteRegex = RegExp(r'\n?\(?Note:.*$', caseSensitive: false, dotAll: true);
    cleaned = cleaned.replaceFirst(noteRegex, '').trim();

    final fenceRegex = RegExp(r'```[a-zA-Z]*\n?|```');
    cleaned = cleaned.replaceAll(fenceRegex, '').trim();
    return cleaned;
  }

  Future<String?> transcribe(String filePath, {String? previousText}) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len < 100) return ""; 
    } catch (e) { return null; }

    try {
      final url = Uri.parse("$baseUrl/audio/transcriptions");
      final request = http.MultipartRequest("POST", url)
        ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
        ..fields['model'] = whisperModel.trim()
        ..fields['response_format'] = 'json';
      
      if (!baseUrl.contains("siliconflow")) {
        request.fields['language'] = 'en';
        if (previousText != null && previousText.isNotEmpty && previousText != "...") {
          request.fields['prompt'] = previousText;
        }
      }
      
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        filePath,
        contentType: MediaType('audio', 'wav'),
      ));

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] ?? "";
      } else {
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        print("[STT ERROR ${response.statusCode}] @ $url");
        print("[Response Body] ${response.body}");
        print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!");
        throw Exception("API Error ${response.statusCode}"); 
      }
    } on SocketException {
      throw Exception("Network unavailable. Check connection.");
    } on TimeoutException {
      throw Exception("Connection timeout. Retrying...");
    } catch (e) {
      rethrow;
    }
  }

  Future<String> translate(String text, {String? modelOverride}) async {
    try {
      final url = Uri.parse("$baseUrl/chat/completions");
      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': (modelOverride ?? defaultModel).trim(),
          'messages': [
            {
              'role': 'system', 
              'content': 'You are a professional academic simultaneous interpreter. '
                         'Your task: translate English academic lecture notes into natural, fluent, scholarly Chinese. '
                         'Rules: '
                         '1. Translate ONLY what is in the input. Do NOT add any context, background knowledge, or examples. '
                         '2. Keep proper nouns (names of people, places, institutions, specific titles) in their original form. '
                         '3. For domain-specific academic terms you are uncertain about, keep the English term with a Chinese translation in parentheses. '
                         '4. Output ONLY the translated Chinese text. No notes, no explanations, no preamble, no postscript.'
            },
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _sanitizeResponse(data['choices'][0]['message']['content']);
      } else {
        // [Architect: Diagnostic UI] 翻译报错回显
        final errorMsg = "[Translation Error ${response.statusCode}]";
        print("\x1B[31m$errorMsg\x1B[0m");
        throw Exception(errorMsg);
      }
    } on SocketException {
      throw Exception("Network error during translation.");
    } on TimeoutException {
      throw Exception("Translation timeout.");
    } catch (e) {
      rethrow;
    }
  }

  Future<String> summarize(String text, {PromptStrategy strategy = PromptStrategy.general, AIProvider provider = AIProvider.groq, AppMode mode = AppMode.lecture}) async {
    try {
      final url = Uri.parse("$baseUrl/chat/completions");
      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': defaultModel.trim(),
          'messages': [
            {'role': 'system', 'content': PromptProvider.getSystemPrompt(strategy, provider, mode: mode)},
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.5,
        }),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return _sanitizeResponse(data['choices'][0]['message']['content']);
      } else {
        throw Exception("Summarize error ${response.statusCode}");
      }
    } on SocketException {
      throw Exception("Network error during summary.");
    } on TimeoutException {
      throw Exception("Summary timeout.");
    } catch (e) {
      rethrow;
    }
  }
}
