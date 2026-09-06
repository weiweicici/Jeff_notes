import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:async';
import 'models.dart';
import 'prompt_provider.dart';
import 'services/api_rate_limit_service.dart';
import 'text_sanitizer.dart';

class OpenAIService {
  final String apiKey;
  final String baseUrl;
  final String defaultModel;
  final String whisperModel;
  final String provider;
  final ApiRateLimitService rateLimitService;
  final Duration translationTimeout;

  final http.Client _client;
  final bool _ownsClient;
  bool _isDisposed = false;

  OpenAIService({
    required this.apiKey,
    required this.baseUrl,
    required this.defaultModel,
    this.whisperModel = 'whisper-large-v3',
    this.provider = 'groq',
    this.translationTimeout = const Duration(seconds: 30),
    ApiRateLimitService? rateLimitService,
    http.Client? httpClient,
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null,
       rateLimitService = rateLimitService ?? ApiRateLimitService.instance;

  void dispose() {
    _isDisposed = true;
    if (_ownsClient) {
      try {
        _client.close();
      } catch (_) {}
    }
  }

  String _sanitizeResponse(String text) {
    String cleaned = text.trim();
    // 移除 AI 常见的开头废话
    final preambleRegex = RegExp(
      r'^(Here is the essay:|Here is the review:|Review:|Analysis:|以下是作文[:：]|以下是复盘报告[:：]|翻译结果[:：])',
      caseSensitive: false,
    );
    cleaned = cleaned.replaceFirst(preambleRegex, '').trim();

    // 仅移除位于文档最末尾独立一行的备注 (防止强行跨行干掉整篇作文)
    cleaned = cleaned
        .replaceFirst(
          RegExp(r'\n\s*\(?Note\s*:[^\n]*\)?$', caseSensitive: false),
          '',
        )
        .trim();

    final fenceRegex = RegExp(r'```[a-zA-Z]*\n?|```');
    cleaned = cleaned.replaceAll(fenceRegex, '').trim();
    return cleaned;
  }

  String get _rateLimitProvider {
    final host = Uri.tryParse(baseUrl)?.host.toLowerCase() ?? '';
    if (host.endsWith('openrouter.ai')) return 'openrouter';
    if (host.endsWith('groq.com')) return 'groq';
    return provider;
  }

  /// `Future.timeout` merely abandons its waiter. AbortableRequest closes the
  /// actual per-request transport without closing the session's shared client.
  Future<http.Response> _postJson(
    Uri url, {
    required Map<String, String> headers,
    required String body,
    required Duration timeout,
  }) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request =
        http.AbortableRequest('POST', url, abortTrigger: abort.future)
          ..headers.addAll(headers)
          ..body = body;
    try {
      final streamed = await _client.send(request);
      return await http.Response.fromStream(streamed);
    } on http.RequestAbortedException {
      throw TimeoutException('HTTP request timed out');
    } finally {
      timer.cancel();
    }
  }

  Future<String?> transcribe(String filePath, {String? previousText}) async {
    if (_isDisposed) return null;
    await rateLimitService.ensureAvailable(provider, whisperModel);
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final len = await file.length();
      if (len < 100) return "";
    } catch (e) {
      return null;
    }

    try {
      final url = Uri.parse("$baseUrl/audio/transcriptions");
      final request = http.MultipartRequest("POST", url)
        ..fields['model'] = whisperModel.trim()
        ..fields['response_format'] = 'json';

      request.headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      request.fields['language'] = 'en';
      if (previousText != null &&
          previousText.isNotEmpty &&
          previousText != "...") {
        request.fields['prompt'] = previousText;
      }

      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: MediaType('audio', 'wav'),
        ),
      );

      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['text'] ?? "";
      } else {
        debugPrint("[STT ERROR ${response.statusCode}]");
        if (response.statusCode == 429) {
          final retryAt = await rateLimitService.register429(
            provider: provider,
            model: whisperModel,
            serverDelay: ApiRateLimitService.parseRetryAfter(
              response.headers['retry-after'],
            ),
          );
          throw ApiRateLimitException(
            provider: provider,
            model: whisperModel,
            retryAt: retryAt,
          );
        }
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

  Future<String> translate(
    String text, {
    String? modelOverride,
    List<Map<String, String>>? history,
  }) async {
    if (_isDisposed) throw Exception("Service disposed");
    final model = (modelOverride ?? defaultModel).trim();
    final rateLimitProvider = _rateLimitProvider;
    await rateLimitService.ensureAvailable(rateLimitProvider, model);
    try {
      final url = Uri.parse("$baseUrl/chat/completions");

      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content':
              'You are a professional academic simultaneous interpreter. '
              'Your task: translate English academic lecture notes/utterances into natural, fluent, scholarly Chinese. '
              'Important: The input is a real-time 5-second slice. It might be an unfinished sentence. '
              'Rules: '
              '1. Translate ONLY what is in the input. '
              '2. If the input ends without punctuation (like . ? !), it is an unfinished clause. Translate it in a natural "hanging/unfinished" tone to ensure it seamlessly connects to the next chunk. Do NOT append final periods. '
              '3. Keep proper nouns in their original form. For uncertain terms, keep the English with a Chinese translation in parentheses. '
              '4. Output ONLY the translated Chinese text for the current input. '
              'Do not output labels such as Translation: or 翻译：, explanations, or markdown.',
        },
      ];

      if (history != null) {
        for (final item in history) {
          final en = item['english'] ?? '';
          final zh = item['chinese'] ?? '';
          if (en.isNotEmpty && zh.isNotEmpty) {
            messages.add({
              'role': 'user',
              'content': '[Previous Context] English: $en',
            });
            messages.add({'role': 'assistant', 'content': zh});
          }
        }
      }

      messages.add({'role': 'user', 'content': text});

      final response = await _postJson(
        url,
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': messages,
          'temperature': 0.1,
        }),
        timeout: translationTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final translated = TextSanitizer.cleanTranslation(
          data['choices'][0]['message']['content'],
        );
        if (translated.isEmpty) {
          throw StateError('Translation response was empty after sanitization');
        }
        return translated;
      } else {
        if (response.statusCode == 429) {
          final retryAt = await rateLimitService.register429(
            provider: rateLimitProvider,
            model: model,
            serverDelay: ApiRateLimitService.parseRetryAfter(
              response.headers['retry-after'],
            ),
          );
          throw ApiRateLimitException(
            provider: rateLimitProvider,
            model: model,
            retryAt: retryAt,
          );
        }
        // [Architect: Diagnostic UI] 翻译报错回显
        final errorMsg = "[Translation Error ${response.statusCode}]";
        debugPrint(errorMsg);
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

  Future<String> summarize(
    String text, {
    PromptStrategy strategy = PromptStrategy.general,
    AIProvider provider = AIProvider.groq,
    AppMode mode = AppMode.lecture,
    PathwaysUnit unit = PathwaysUnit.none,
  }) async {
    if (_isDisposed) throw Exception("Service disposed");
    try {
      final url = Uri.parse("$baseUrl/chat/completions");
      final maxTokens = strategy == PromptStrategy.recap
          ? mode == AppMode.lecture
                ? 1800
                : 4096
          : 1600;
      final response = await _client
          .post(
            url,
            headers: {
              'Authorization': 'Bearer ${apiKey.trim()}',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': defaultModel.trim(),
              'messages': [
                {
                  'role': 'system',
                  'content': PromptProvider.getSystemPrompt(
                    strategy,
                    provider,
                    mode: mode,
                    unit: unit,
                  ),
                },
                {'role': 'user', 'content': text},
              ],
              'temperature': strategy == PromptStrategy.recap ? 0.15 : 0.2,
              'max_tokens': maxTokens,
            }),
          )
          .timeout(
            const Duration(seconds: 120),
          ); // 作文生成 prompt 长，Qwen-72B 需要更多时间

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
