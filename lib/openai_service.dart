import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:async';
import 'models.dart';
import 'prompt_provider.dart';

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
    if (_isDisposed) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len < 100) return ""; 
    } catch (e) { return null; }

    try {
      final url = Uri.parse("$baseUrl/audio/transcriptions");
      final request = http.MultipartRequest("POST", url)
        ..fields['model'] = whisperModel.trim()
        ..fields['response_format'] = 'json';
      
      // 硅基流动 API 特殊处理
      if (baseUrl.contains("siliconflow")) {
        debugPrint("硅基流动 STT 请求: URL=$url, API Key 前几位: ${apiKey.substring(0, 10)}...");
        debugPrint("硅基流动 API Key 完整长度: ${apiKey.length}");
        // 硅基流动使用 Authorization 头，格式为 Bearer
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
        debugPrint("硅基流动请求头: Authorization: Bearer ${apiKey.substring(0, 10)}...");
        // 注意：硅基流动部署的 SenseVoiceSmall 模型不支持 language 和 prompt 参数，发送会导致 API Error 400
      } else {
        request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
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

      final streamedResponse = await _client.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      // 硅基流动 API 详细调试信息
      if (baseUrl.contains("siliconflow")) {
        debugPrint("硅基流动 STT 响应状态码: ${response.statusCode}");
        debugPrint("硅基流动 STT 响应头: ${response.headers}");
        debugPrint("硅基流动 STT 响应体: ${response.body}");
      }

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

  Future<String> translate(String text, {String? modelOverride, List<Map<String, String>>? history}) async {
    if (_isDisposed) throw Exception("Service disposed");
    try {
      final url = Uri.parse("$baseUrl/chat/completions");
      
      final messages = <Map<String, dynamic>>[
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
        }
      ];

      if (history != null) {
        for (final item in history) {
          final en = item['english'] ?? '';
          final zh = item['chinese'] ?? '';
          if (en.isNotEmpty && zh.isNotEmpty) {
            messages.add({'role': 'user', 'content': '[Previous Context] English: $en'});
            messages.add({'role': 'assistant', 'content': '[Previous Context] Translation: $zh'});
          }
        }
      }

      messages.add({'role': 'user', 'content': text});

      final response = await _client.post(
        url,
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': (modelOverride ?? defaultModel).trim(),
          'messages': messages,
          'temperature': 0.1,
        }),
      ).timeout(const Duration(seconds: 30));

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

  Future<String> summarize(String text, {PromptStrategy strategy = PromptStrategy.general, AIProvider provider = AIProvider.groq, AppMode mode = AppMode.lecture, PathwaysUnit unit = PathwaysUnit.none}) async {
    if (_isDisposed) throw Exception("Service disposed");
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
            {'role': 'system', 'content': PromptProvider.getSystemPrompt(strategy, provider, mode: mode, unit: unit)},
            {'role': 'user', 'content': text},
          ],
          'temperature': 0.5,
        }),
      ).timeout(const Duration(seconds: 120)); // 作文生成 prompt 长，Qwen-72B 需要更多时间

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
