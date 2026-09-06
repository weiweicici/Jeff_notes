import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_scheduler.dart';
import 'text_sanitizer.dart';
import 'terminology_interceptor.dart';
import 'openai_service.dart';
import 'services/diagnostic_log_service.dart';
import 'services/api_rate_limit_service.dart';
import 'services/local_translation_service.dart';

/// [Architect: Pipeline Result Container]
class PipelineResult {
  final String noteId;
  final String content;
  final bool isRepair;
  PipelineResult(this.noteId, this.content, {this.isRepair = false});
}

/// A provider failure is different from an actually silent recording. The
/// caller keeps the pending WAV when this is thrown so recovery can retry it.
class SttUnavailableException implements Exception {
  final String reason;
  const SttUnavailableException([
    this.reason = 'speech recognition unavailable',
  ]);

  @override
  String toString() => 'SttUnavailableException: $reason';
}

class TranslationDeferredException implements Exception {
  final int count;
  const TranslationDeferredException(this.count);
  @override
  String toString() =>
      'TranslationDeferredException: $count batch item(s) pending';
}

/// A provider returned syntactically successful content that becomes empty
/// after removing only structural wrappers (for example `Translation:` or a
/// markdown fence).  It is a failed translation, not a completed blank note.
class EmptyTranslationException implements Exception {
  const EmptyTranslationException();

  @override
  String toString() =>
      'EmptyTranslationException: translation was empty after cleanup';
}

class PendingTranslation {
  final String noteId;
  final String text;
  const PendingTranslation(this.noteId, this.text);
}

/// Deliberately narrow: normal Chinese may retain isolated product names,
/// commands, IPs and paths.  Only a complete, prose-like English sentence
/// returned essentially unchanged is eligible for one background repair.
bool needsTranslationRepair(String english, String chinese) {
  final source = english.trim();
  final result = chinese.trim();
  if (source.length < 28 || !RegExp(r'[.!?]$').hasMatch(source)) {
    return false;
  }
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(result)) {
    return false;
  }
  if (RegExp(
    r'^(?:https?://|/|~[/\\]|[A-Za-z]:[/\\]|(?:git|npm|flutter|dart|cd|ls|curl)\b)',
    caseSensitive: false,
  ).hasMatch(source))
    return false;
  if (RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}(?::\d+)?$').hasMatch(source))
    return false;
  final words = RegExp(
    r"[A-Za-z]+(?:[-'][A-Za-z]+)?",
  ).allMatches(result).length;
  return words >= 5 && result.toLowerCase() == source.toLowerCase();
}

/// One durable note boundary plus the translation context captured when its
/// matching STT result completed. Keeping these in one queue entry prevents
/// independent list mutations from ever mismatching note id, text, or context.
class _TranslationRequest {
  final String noteId;
  final String text;
  final List<Map<String, String>> history;
  final bool isRepair;

  const _TranslationRequest({
    required this.noteId,
    required this.text,
    required this.history,
    this.isRepair = false,
  });
}

/// Checks 16-bit PCM WAV signal strength without sending audio anywhere.
/// A conservative threshold prevents audible lecture speech from being
/// discarded merely because an STT provider returned an empty response.
Future<bool> wavContainsAudibleSignal(
  String filePath, {
  double rmsThresholdDb = -48.0,
}) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    if (bytes.length < 46) return false;

    final data = ByteData.sublistView(bytes);
    int dataStart = 44;
    int dataLength = bytes.length - dataStart;
    if (String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WAVE') {
      var offset = 12;
      while (offset + 8 <= bytes.length) {
        final chunkId = String.fromCharCodes(bytes.skip(offset).take(4));
        final chunkLength = data.getUint32(offset + 4, Endian.little);
        final chunkStart = offset + 8;
        if (chunkId == 'data') {
          dataStart = chunkStart;
          dataLength = math.min(chunkLength, bytes.length - chunkStart);
          break;
        }
        offset = chunkStart + chunkLength + (chunkLength.isOdd ? 1 : 0);
      }
    }

    if (dataLength < 2 || dataStart + dataLength > bytes.length) return false;
    var sumSquares = 0.0;
    var peak = 0;
    var samples = 0;
    final end = dataStart + dataLength - 1;
    // Sampling every fourth value is sufficient and keeps long recovery files cheap.
    for (var offset = dataStart; offset < end; offset += 8) {
      final value = data.getInt16(offset, Endian.little).abs();
      peak = math.max(peak, value);
      final normalized = value / 32768.0;
      sumSquares += normalized * normalized;
      samples++;
    }
    if (samples == 0 || peak < 80) return false;
    final rms = math.sqrt(sumSquares / samples);
    if (rms <= 0) return false;
    final rmsDb = 20 * math.log(rms) / math.ln10;
    return rmsDb >= rmsThresholdDb;
  } catch (_) {
    // Unknown-but-substantial audio should be retried, never discarded as silence.
    try {
      return await File(filePath).length() > 3200;
    } catch (_) {
      return false;
    }
  }
}

/// [Architect: Pipeline Assembly]
/// AI 编排服务：快轨（英文字幕）+ 慢轨（中文翻译）
class AIOrchestratorService {
  final OpenAIService sttService;
  final OpenAIService translationService;
  final OpenAIService? translationFallbackService;
  final LocalTextTranslator? localTranslator;
  final String sessionId;

  final _fastEnglishController = StreamController<PipelineResult>.broadcast();
  final _accurateChineseController =
      StreamController<PipelineResult>.broadcast();

  Stream<PipelineResult> get fastEnglishStream => _fastEnglishController.stream;
  Stream<PipelineResult> get accurateChineseStream =>
      _accurateChineseController.stream;

  final List<_TranslationRequest> _translationQueue = [];
  static const int batchSize = 1;
  static const int maxConcurrentTranslations = 2;

  /// Keep real-time English independent from a slow translation provider.
  /// Overflow is durable via [onTranslationsDeferred], rather than retaining
  /// an unbounded in-memory list for a multi-hour lecture.
  static const int maxInMemoryTranslationBacklog = 24;

  // 防止同时触发多个 batch 翻译
  final Set<Future<void>> _translationWorkers = {};
  int _translationQueuePeak = 0;
  bool _isDisposed = false;

  // [Phase 3] 翻译批次完成信号，用于 drain() 等待正在进行的批次
  Completer<void>? _translationBatchCompleter;

  final String _geminiApiKey;
  void Function(List<PendingTranslation>)? onTranslationsDeferred;
  void Function(List<String>)? onTranslationsCompleted;

  /// Returns true after the durable per-note one-repair budget was claimed.
  bool Function(String noteId)? onTranslationRepairRequested;
  final Set<String> _repairNoteIds = {};
  final Map<String, PendingTranslation> _deferredTranslations = {};
  final ApiRateLimitService _rateLimitService;

  // [Phase 3] 每实例独立 http.Client，dispose() 时关闭以终止底层 HTTP 连接
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  AIOrchestratorService({
    required this.sttService,
    required this.translationService,
    this.translationFallbackService,
    this.localTranslator,
    required this.sessionId,
    String geminiApiKey = '',
    ApiRateLimitService? rateLimitService,
    this.onTranslationsDeferred,
    this.onTranslationsCompleted,
    http.Client? httpClient,
  }) : _geminiApiKey = geminiApiKey,
       _rateLimitService = rateLimitService ?? ApiRateLimitService.instance,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  List<PendingTranslation> get pendingTranslations =>
      List.unmodifiable(_deferredTranslations.values);
  int get translationQueuePeak => _translationQueuePeak;
  int get activeTranslationWorkers => _translationWorkers.length;
  bool get _isTranslating => _translationWorkers.isNotEmpty;

  void restorePendingTranslations(Iterable<PendingTranslation> items) {
    for (final item in items) {
      _deferredTranslations[item.noteId] = item;
    }
  }

  void restoreTranslationRepairAttempts(Iterable<String> noteIds) {
    _repairNoteIds.addAll(noteIds);
  }

  @visibleForTesting
  void enqueueTranslationForTesting(String noteId, String text) {
    _enqueueTranslation(
      _TranslationRequest(
        noteId: noteId,
        text: text,
        history: const <Map<String, String>>[],
      ),
    );
  }

  void _enqueueTranslation(
    _TranslationRequest request, {
    Function(String)? onStatus,
  }) {
    // The two running workers count against the bounded live backlog too.
    // Defer before enqueueing, so a process death cannot lose overflow.
    if (_translationQueue.length + _translationWorkers.length >=
        maxInMemoryTranslationBacklog) {
      _deferredTranslations[request.noteId] = PendingTranslation(
        request.noteId,
        request.text,
      );
      onTranslationsDeferred?.call([
        PendingTranslation(request.noteId, request.text),
      ]);
      return;
    }
    _translationQueue.add(request);
    if (_translationQueue.length > _translationQueuePeak) {
      _translationQueuePeak = _translationQueue.length;
    }
    onTranslationsDeferred?.call([
      PendingTranslation(request.noteId, request.text),
    ]);
    _pumpTranslations(onStatus: onStatus);
  }

  Future<http.Response> _postJson(
    Uri url, {
    required String body,
    required Duration timeout,
  }) async {
    final abort = Completer<void>();
    final timer = Timer(timeout, () {
      if (!abort.isCompleted) abort.complete();
    });
    final request =
        http.AbortableRequest('POST', url, abortTrigger: abort.future)
          ..headers['Content-Type'] = 'application/json'
          ..body = body;
    try {
      final streamed = await _httpClient.send(request);
      return await http.Response.fromStream(streamed);
    } on http.RequestAbortedException {
      throw TimeoutException('HTTP request timed out');
    } finally {
      timer.cancel();
    }
  }

  Future<void> retryPendingTranslations({Function(String)? onStatus}) async {
    if (_deferredTranslations.isEmpty || _isDisposed) return;
    // A note whose one automatic repair was already claimed must never be
    // silently sent again after a retry button, finalization pass, or restart.
    // Keep it durable for diagnosis/export, but exclude it from automatic
    // recovery. Non-repair translation failures retain their normal recovery.
    final retryable = _deferredTranslations.values.where(
      (item) => !_repairNoteIds.contains(item.noteId),
    );
    _translationQueue.addAll(
      retryable.map(
        (item) => _TranslationRequest(
          noteId: item.noteId,
          text: item.text,
          history: const <Map<String, String>>[],
          isRepair: _repairNoteIds.contains(item.noteId),
        ),
      ),
    );
    if (_translationQueue.length > _translationQueuePeak) {
      _translationQueuePeak = _translationQueue.length;
    }
    _deferredTranslations.removeWhere(
      (noteId, _) => !_repairNoteIds.contains(noteId),
    );
    _pumpTranslations(onStatus: onStatus);
  }

  Future<String> _translateWithGemini(
    String text, {
    List<Map<String, String>>? history,
  }) async {
    if (_geminiApiKey.isEmpty) {
      throw StateError('Gemini translation API key is not configured');
    }
    const model = 'gemini-2.5-flash';
    await _rateLimitService.ensureAvailable('gemini', model);
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_geminiApiKey',
      );
      final recentContext = (history ?? const <Map<String, String>>[])
          .where(
            (item) =>
                (item['english'] ?? '').trim().isNotEmpty &&
                (item['chinese'] ?? '').trim().isNotEmpty,
          )
          .take(2)
          .map(
            (item) =>
                'English: ${item['english']}\nChinese: ${item['chinese']}',
          )
          .join('\n\n');
      final userText = recentContext.isEmpty
          ? text
          : 'Previous context for reference only:\n$recentContext\n\n'
                'Translate only this current English text:\n$text';
      // [Phase 3] 使用实例级 client（关闭 client 即可终止此会话的请求）
      final response = await _postJson(
        url,
        body: jsonEncode({
          'system_instruction': {
            'parts': [
              {
                'text':
                    'You are a professional academic simultaneous interpreter. '
                    'Translate only the current English text into natural, accurate Chinese. '
                    'Use previous context only to resolve terminology and incomplete clauses. '
                    'Keep proper nouns and technical terms in their original form when appropriate. '
                    'Output only the Chinese translation of the current text, with no labels such as '
                    'Translation: or 翻译：, no explanations, markdown, or quotation marks.',
              },
            ],
          },
          'contents': [
            {
              'parts': [
                {'text': userText},
              ],
            },
          ],
          'generationConfig': {'temperature': 0.1},
        }),
        timeout: const Duration(seconds: 30),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final result = parts[0]['text'] as String?;
            if (result != null && result.trim().isNotEmpty) {
              final cleaned = TextSanitizer.cleanTranslation(result);
              if (cleaned.isNotEmpty) return cleaned;
              throw const EmptyTranslationException();
            }
          }
        }
      }
      if (response.statusCode == 429) {
        Object? body;
        try {
          body = jsonDecode(response.body);
        } catch (_) {}
        final retryAt = await _rateLimitService.register429(
          provider: 'gemini',
          model: model,
          serverDelay:
              ApiRateLimitService.parseRetryAfter(
                response.headers['retry-after'],
              ) ??
              ApiRateLimitService.parseGeminiRetryDelay(body),
        );
        throw ApiRateLimitException(
          provider: 'gemini',
          model: model,
          retryAt: retryAt,
        );
      }
      throw Exception('Gemini translation failed: HTTP ${response.statusCode}');
    } on ApiRateLimitException {
      rethrow;
    } on TimeoutException {
      throw TimeoutException('Gemini translation timed out');
    } catch (e) {
      debugPrint('[Orchestrator Gemini Translation] Error: ${e.runtimeType}');
      rethrow;
    }
  }

  /// Uses the session-scoped Gemini connection as a provider-independent
  /// fallback for final reviews. No transcript or response body is logged.
  Future<String?> generateSummaryWithGemini({
    required String systemPrompt,
    required String userMessage,
    int maxOutputTokens = 3200,
  }) async {
    if (_geminiApiKey.isEmpty || _isDisposed) return null;
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
      );
      final response = await _httpClient
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
              'generationConfig': {
                'temperature': 0.15,
                'maxOutputTokens': maxOutputTokens,
                'thinkingConfig': {'thinkingBudget': 0},
              },
            }),
          )
          .timeout(const Duration(seconds: 120));
      if (response.statusCode != 200) {
        debugPrint(
          '[Orchestrator Gemini Summary] Failed status ${response.statusCode}',
        );
        return null;
      }

      final data = jsonDecode(response.body);
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) return null;
      final candidate = Map<String, dynamic>.from(candidates.first as Map);
      final finishReason = candidate['finishReason'] as String?;
      if (finishReason != null && finishReason != 'STOP') {
        debugPrint(
          '[Orchestrator Gemini Summary] Rejected finishReason=$finishReason',
        );
        return null;
      }
      final parts = candidate['content']?['parts'] as List?;
      if (parts == null || parts.isEmpty) return null;
      final text = parts
          .map((part) => part is Map ? part['text'] : null)
          .whereType<String>()
          .join('\n')
          .replaceAll(RegExp(r'```[a-zA-Z]*\n?|```'), '')
          .trim();
      return text.isEmpty ? null : text;
    } on TimeoutException {
      debugPrint('[Orchestrator Gemini Summary] Timeout');
      return null;
    } catch (error) {
      debugPrint('[Orchestrator Gemini Summary] Error: ${error.runtimeType}');
      return null;
    }
  }

  /// [STT 降级兜底] 当 Groq STT 失败/429/超时，调用 Gemini 2.5 Flash 进行多模态音频转写
  Future<String?> _transcribeGemini(String filePath) async {
    if (_geminiApiKey.isEmpty) return null;
    const model = 'gemini-2.5-flash';
    await _rateLimitService.ensureAvailable('gemini', model);
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.length < 100) return "";

      final base64Audio = base64Encode(bytes);
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
      );
      // [Phase 3] 使用实例级 client
      final response = await _httpClient
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'system_instruction': {
                'parts': [
                  {
                    'text':
                        'You are an expert English speech-to-text transcriber. Transcribe the given audio slice into raw English text. Output ONLY the clean transcribed English text with no markdown, no quotes, no explanations, and no conversational filler. If the audio contains only silence or background noise, output NOTHING.',
                  },
                ],
              },
              'contents': [
                {
                  'parts': [
                    {
                      'inline_data': {
                        'mime_type': 'audio/wav',
                        'data': base64Audio,
                      },
                    },
                    {'text': 'Transcribe this English audio recording slice.'},
                  ],
                },
              ],
              'generationConfig': {'temperature': 0.1},
            }),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final result = parts[0]['text'] as String?;
            if (result != null && result.trim().isNotEmpty) {
              final cleaned = result.trim();
              final lower = cleaned.toLowerCase();
              if (lower.contains("no speech") ||
                  lower.contains("silence") ||
                  lower.contains("background noise")) {
                unawaited(
                  DiagnosticLogService.instance.record(
                    'stt',
                    'gemini_reported_silence',
                  ),
                );
                return "";
              }
              return cleaned;
            }
          }
        }
      } else {
        if (response.statusCode == 429) {
          Object? body;
          try {
            body = jsonDecode(response.body);
          } catch (_) {}
          final retryAt = await _rateLimitService.register429(
            provider: 'gemini',
            model: model,
            serverDelay:
                ApiRateLimitService.parseRetryAfter(
                  response.headers['retry-after'],
                ) ??
                ApiRateLimitService.parseGeminiRetryDelay(body),
          );
          throw ApiRateLimitException(
            provider: 'gemini',
            model: model,
            retryAt: retryAt,
          );
        }
        unawaited(
          DiagnosticLogService.instance.record(
            'stt',
            'gemini_http_failed',
            fields: {'status': response.statusCode},
          ),
        );
        debugPrint(
          '[Orchestrator Gemini STT] Failed status ${response.statusCode}: ${response.body}',
        );
      }
    } on TimeoutException {
      unawaited(DiagnosticLogService.instance.record('stt', 'gemini_timeout'));
      debugPrint('[Orchestrator Gemini STT] Timeout');
      return null;
    } catch (e) {
      if (e is ApiRateLimitException) rethrow;
      unawaited(
        DiagnosticLogService.instance.record(
          'stt',
          'gemini_error',
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint('[Orchestrator Gemini STT] Error: $e');
    }
    unawaited(
      DiagnosticLogService.instance.record('stt', 'gemini_empty_response'),
    );
    return null;
  }

  void _addFastEnglish(PipelineResult result) {
    if (_isDisposed) return;
    _fastEnglishController.add(result);
  }

  void _addAccurateChinese(PipelineResult result) {
    if (_isDisposed) return;
    _accurateChineseController.add(result);
  }

  List<Map<String, String>> _snapshotHistory(
    List<Map<String, String>>? history,
  ) => List<Map<String, String>>.unmodifiable([
    for (final item in history ?? const <Map<String, String>>[])
      Map<String, String>.unmodifiable(Map<String, String>.from(item)),
  ]);

  Future<void> processAudioSegment(
    String noteId,
    String filePath, {
    String? context,
    List<Map<String, String>>? translationHistory,
    Function(String)? onStatus,
  }) async {
    if (_isDisposed) return;
    final translationHistorySnapshot = _snapshotHistory(translationHistory);
    try {
      onStatus?.call("STT requesting...");

      // 1. STT 阶段（快车道）：Groq 主服务 → Gemini 2.5 Flash 自动降级兜底
      String? rawEnglish;
      Object? groqFailure;
      try {
        rawEnglish = await ApiScheduler().enqueue(
          () => sttService.transcribe(filePath, previousText: context),
          priority: 0,
          sessionId: sessionId,
          lane: ApiTaskLane.realtime,
          maxAttempts: 1,
        );
      } catch (sttErr) {
        groqFailure = sttErr;
        final statusMatch = RegExp(
          r'\b([45][0-9]{2})\b',
        ).firstMatch(sttErr.toString());
        unawaited(
          DiagnosticLogService.instance.record(
            'stt',
            'groq_failed',
            sessionId: sessionId,
            fields: {
              'status': statusMatch?.group(1) ?? 'transport',
              'errorType': sttErr.runtimeType,
            },
          ),
        );
        debugPrint(
          "[Orchestrator STT] Main Groq STT failed: $sttErr. Trying Gemini 2.5 Flash fallback...",
        );
      }

      if (_isDisposed) return;

      // Groq 失败或返回空时只调用一次 Gemini，避免同一音频被重复上传。
      String? geminiResult;
      if (rawEnglish == null || rawEnglish.trim().isEmpty) {
        if (_geminiApiKey.isNotEmpty) {
          onStatus?.call("正在使用 Gemini 复核语音...");
          try {
            geminiResult = await _transcribeGemini(filePath);
          } on ApiRateLimitException {
            // If both providers are cooling down, retain a typed limit error
            // so recovery can pause until the earliest provider is available.
            if (groqFailure is ApiRateLimitException) rethrow;
            rethrow;
          }
          if (geminiResult != null && geminiResult.trim().isNotEmpty) {
            rawEnglish = geminiResult;
          }
        }
      }

      // A rate-limited primary must remain typed when no fallback transcript
      // was obtained, so recovery can pause until the persisted cooldown.
      if ((rawEnglish == null || rawEnglish.trim().isEmpty) &&
          groqFailure is ApiRateLimitException) {
        throw groqFailure;
      }

      if (rawEnglish == null || rawEnglish.trim().isEmpty) {
        final audible = await wavContainsAudibleSignal(filePath);
        // A clear waveform plus an empty/failed provider response is not silence.
        // Throwing keeps the original pending slice in the recovery draft.
        if (audible) {
          var audioBytes = 0;
          try {
            audioBytes = await File(filePath).length();
          } catch (_) {}
          unawaited(
            DiagnosticLogService.instance.record(
              'stt',
              'audible_audio_unrecognized',
              sessionId: sessionId,
              fields: {
                'audioBytes': audioBytes,
                'approxSeconds': (audioBytes / 32000).toStringAsFixed(1),
                'geminiConfigured': _geminiApiKey.isNotEmpty,
              },
            ),
          );
          final providerState = groqFailure != null
              ? 'Groq failed and fallback produced no transcript'
              : 'provider returned an empty transcript for audible audio';
          throw SttUnavailableException(providerState);
        }
        onStatus?.call("Silence detected");
        _addFastEnglish(PipelineResult(noteId, "[Silence]"));
        return;
      }

      onStatus?.call("Cleaning text...");
      String cleanEnglish = await compute(TextSanitizer.clean, rawEnglish);

      // 2. 去重逻辑
      if (context != null && context.isNotEmpty && context != "...") {
        final merged = TextSanitizer.mergeOverlappingText(
          context,
          cleanEnglish,
        );
        if (merged.length > context.length) {
          cleanEnglish = merged.substring(context.length).trim();
        }
      }

      // 如果清洗后为空也当静音处理
      if (cleanEnglish.trim().isEmpty) {
        _addFastEnglish(PipelineResult(noteId, "[Silence]"));
        return;
      }

      if (_isDisposed) return;

      onStatus?.call("Displaying English...");
      _addFastEnglish(PipelineResult(noteId, cleanEnglish));

      // 3. 进入翻译缓冲（慢车道）
      _enqueueTranslation(
        _TranslationRequest(
          noteId: noteId,
          text: cleanEnglish,
          history: translationHistorySnapshot,
        ),
        onStatus: onStatus,
      );

      if (_translationQueue.isNotEmpty) {
        onStatus?.call("Translating batch...");
        // 非阻塞：启动翻译，不阻断 STT 快车道
      } else {
        onStatus?.call('Translation deferred for recovery');
      }
    } on SttUnavailableException {
      onStatus?.call("识别服务暂时不可用，录音已保留");
      rethrow;
    } on ApiRateLimitException {
      onStatus?.call("识别服务限流，录音已保留");
      rethrow;
    } catch (e, st) {
      debugPrint("[Orchestrator Error $noteId] $e\n$st");
      onStatus?.call("Pipeline Error");
      _addFastEnglish(PipelineResult(noteId, "[Error:$e]"));
    }
  }

  void _pumpTranslations({Function(String)? onStatus}) {
    while (!_isDisposed &&
        _translationQueue.isNotEmpty &&
        _translationWorkers.length < maxConcurrentTranslations) {
      final completed = Completer<void>();
      final worker = completed.future;
      _translationWorkers.add(worker);
      unawaited(
        _processTranslationBatch(onStatus: onStatus).then(
          (_) {
            _translationWorkers.remove(worker);
            _pumpTranslations(onStatus: onStatus);
            completed.complete();
          },
          onError: (Object error, StackTrace stackTrace) {
            _translationWorkers.remove(worker);
            _pumpTranslations(onStatus: onStatus);
            completed.completeError(error, stackTrace);
          },
        ),
      );
    }
  }

  Future<void> _processTranslationBatch({Function(String)? onStatus}) async {
    if (_translationQueue.isEmpty || _isDisposed) return;

    // Consume exactly one note at a time. A provider returns one free-form
    // Chinese string, so sentence-count splitting cannot safely reconstruct
    // the original note boundaries (for example IP addresses contain dots).
    final request = _translationQueue.removeAt(0);
    final batch = <String>[request.text];
    final ids = <String>[request.noteId];
    final history = request.history;
    // Persist the work before making the network request. If the app is
    // killed while translation is in flight, recovery can resubmit it.
    onTranslationsDeferred?.call([
      for (var i = 0; i < ids.length; i++) PendingTranslation(ids[i], batch[i]),
    ]);

    try {
      // [Fix] 先做 TerminologyInterceptor，用安全的方式，任何异常都有降级
      String fullEnglish = batch.join(" ");

      String textToTranslate;
      Map<String, String> lookupTable;

      try {
        final interceptResult = TerminologyInterceptor.encode(fullEnglish);
        textToTranslate = interceptResult.safeText;
        lookupTable = interceptResult.lookupTable;
      } catch (e) {
        // TerminologyInterceptor 失败时降级：直接翻译原始英文
        debugPrint(
          "[Orchestrator] TerminologyInterceptor failed, using raw text: $e",
        );
        textToTranslate = fullEnglish;
        lookupTable = {};
      }

      if (_isDisposed) return;
      onStatus?.call(
        localTranslator == null ? "Calling translation API..." : "正在使用本机翻译...",
      );

      String translatedText;
      if (localTranslator != null) {
        // Lecture and Free Talk take this branch. There is deliberately no
        // cloud fallback: English transcript text never leaves the device for
        // translation, even if the local model is temporarily unavailable.
        translatedText = await localTranslator!.translateEnglishToChinese(
          textToTranslate,
        );
      } else {
        try {
          if (_geminiApiKey.isEmpty) {
            throw StateError('Gemini translation API key is not configured');
          }
          onStatus?.call('Gemini translating...');
          translatedText = await ApiScheduler().enqueue(
            () => _translateWithGemini(textToTranslate, history: history),
            priority: 1,
            sessionId: sessionId,
            lane: ApiTaskLane.translation,
            maxAttempts: 1,
          );
        } catch (geminiError, geminiStackTrace) {
          debugPrint(
            "[Orchestrator] Gemini translation failed: ${geminiError.runtimeType}",
          );
          // The dedicated Groq translation key is now the first fallback.
          // It still receives only the English transcript, never audio.
          try {
            onStatus?.call('Gemini unavailable. Using Groq translation...');
            translatedText = await ApiScheduler().enqueue(
              () => translationService.translate(
                textToTranslate,
                history: history,
              ),
              priority: 1,
              sessionId: sessionId,
              lane: ApiTaskLane.translation,
              maxAttempts: 1,
            );
          } catch (groqError, groqStackTrace) {
            debugPrint(
              '[Orchestrator] Groq translation fallback failed: '
              '${groqError.runtimeType}',
            );
            if (translationFallbackService != null) {
              try {
                onStatus?.call('Gemini and Groq failed. Using OpenRouter...');
                translatedText = await ApiScheduler().enqueue(
                  () => translationFallbackService!.translate(
                    textToTranslate,
                    history: history,
                  ),
                  priority: 1,
                  sessionId: sessionId,
                  lane: ApiTaskLane.translation,
                  maxAttempts: 1,
                );
              } catch (fallbackError, fallbackStackTrace) {
                debugPrint(
                  '[Orchestrator] OpenRouter fallback also failed: '
                  '${fallbackError.runtimeType}',
                );
                Error.throwWithStackTrace(fallbackError, fallbackStackTrace);
              }
            } else {
              // Preserve the most actionable provider failure. If Groq is not
              // configured, surface the Gemini error instead.
              if (groqError is StateError) {
                Error.throwWithStackTrace(geminiError, geminiStackTrace);
              }
              Error.throwWithStackTrace(groqError, groqStackTrace);
            }
          }
        }
      }

      if (_isDisposed) return;

      // 还原术语
      final finalChinese = TextSanitizer.cleanTranslation(
        lookupTable.isEmpty
            ? translatedText
            : TerminologyInterceptor.decode(translatedText, lookupTable),
      );

      // HTTP success is not translation success when the provider returned
      // only a label, whitespace, or a markdown wrapper.  Do this after
      // terminology restoration too, because a malformed placeholder can
      // otherwise be stripped at that stage.  The catch below persists every
      // original noteId/text pair for recovery and emits no blank completion.
      if (finalChinese.isEmpty) {
        throw const EmptyTranslationException();
      }

      onStatus?.call(localTranslator == null ? "Chinese ready" : "本机中文已就绪");

      final repairNeeded =
          !request.isRepair &&
          needsTranslationRepair(request.text, finalChinese) &&
          (onTranslationRepairRequested?.call(request.noteId) ?? false);
      _addAccurateChinese(
        PipelineResult(ids.single, finalChinese, isRepair: request.isRepair),
      );
      for (final id in ids) {
        _deferredTranslations.remove(id);
      }
      onTranslationsCompleted?.call(ids);
      if (repairNeeded) {
        _repairNoteIds.add(request.noteId);
        _deferredTranslations[request.noteId] = PendingTranslation(
          request.noteId,
          request.text,
        );
        onTranslationsDeferred?.call([
          PendingTranslation(request.noteId, request.text),
        ]);
        _translationQueue.add(
          _TranslationRequest(
            noteId: request.noteId,
            text: request.text,
            history: request.history,
            isRepair: true,
          ),
        );
        if (_translationQueue.length > _translationQueuePeak) {
          _translationQueuePeak = _translationQueue.length;
        }
      }
    } catch (e) {
      debugPrint("[Translation Batch Error] $e");
      onStatus?.call(
        localTranslator == null ? "Translation failed" : "本机翻译暂不可用",
      );
      final deferred = <PendingTranslation>[];
      for (var i = 0; i < ids.length; i++) {
        final item = PendingTranslation(ids[i], batch[i]);
        _deferredTranslations[item.noteId] = item;
        deferred.add(item);
      }
      onTranslationsDeferred?.call(deferred);
    } finally {
      // [Phase 3] 通知 drain() 此批次已完成
      final batchDone = _translationBatchCompleter;
      _translationBatchCompleter = null;
      if (batchDone != null && !batchDone.isCompleted) batchDone.complete();
    }
  }

  /// 录音结束时强制冲刷缓冲区中的剩余文本
  Future<void> flush({Function(String)? onStatus}) async {
    if (_translationQueue.isNotEmpty) {
      onStatus?.call("Flushing final buffer...");
      // flush 时需要 await，确保数据在导出前落盘
      _pumpTranslations(onStatus: onStatus);
    }
  }

  /// [Phase 3: Closed-Loop Session Drain]
  /// 等待该实例所有在途 STT、翻译批次与 ApiScheduler 任务全部归零。
  Future<void> drain({Duration timeout = const Duration(seconds: 90)}) async {
    final stopwatch = Stopwatch()..start();

    while (true) {
      // 1. 若缓冲区有数据，强制触发批次翻译
      if (_translationQueue.isNotEmpty) {
        _pumpTranslations();
      }

      // 2. Wait for every bounded worker, not merely the last worker to
      // install a completer. This keeps drain correct with two translations.
      if (_isTranslating) {
        final remaining = timeout - stopwatch.elapsed;
        if (remaining <= Duration.zero) {
          throw TimeoutException(
            'Orchestrator translation batch timed out for session $sessionId',
          );
        }
        try {
          await Future.wait(
            List<Future<void>>.from(_translationWorkers),
          ).timeout(remaining);
        } on TimeoutException {
          throw TimeoutException(
            'Orchestrator translation batch timed out for session $sessionId',
          );
        }
      }

      // 3. 等待 ApiScheduler 中该 session 的所有排队与在途 Future settle
      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'ApiScheduler drain timed out for session $sessionId',
        );
      }

      await ApiScheduler().drain(sessionId, timeout: remaining);

      // 4. 判断闭环 quiescence 状态：没有在途翻译，且缓冲区为空
      if (!_isTranslating && _translationQueue.isEmpty) {
        if (_deferredTranslations.isNotEmpty) {
          throw TranslationDeferredException(_deferredTranslations.length);
        }
        // Controllers are asynchronous. Let the last worker's accurate
        // result reach RecordingSessionContext before callers export/check
        // quiescence.
        await Future<void>.delayed(Duration.zero);
        break;
      }
    }
  }

  void dispose() {
    _isDisposed = true;
    _fastEnglishController.close();
    _accurateChineseController.close();
    // A RecordingSessionContext owns its shared client. Closing an injected
    // client here would abort unrelated STT/translation requests in it.
    if (_ownsHttpClient) {
      try {
        _httpClient.close();
      } catch (_) {}
    }
  }
}
