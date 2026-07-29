import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_scheduler.dart';
import 'text_sanitizer.dart';
import 'terminology_interceptor.dart';
import 'openai_service.dart';

/// [Architect: Pipeline Result Container]
class PipelineResult {
  final String noteId;
  final String content;
  PipelineResult(this.noteId, this.content);
}

/// [Architect: Pipeline Assembly]
/// AI 编排服务：快轨（英文字幕）+ 慢轨（中文翻译）
class AIOrchestratorService {
  final OpenAIService sttService;
  final OpenAIService translationService;
  final OpenAIService? translationFallbackService;
  final String sessionId;

  final _fastEnglishController = StreamController<PipelineResult>.broadcast();
  final _accurateChineseController = StreamController<PipelineResult>.broadcast();

  Stream<PipelineResult> get fastEnglishStream => _fastEnglishController.stream;
  Stream<PipelineResult> get accurateChineseStream => _accurateChineseController.stream;

  final List<String> _translationBuffer = [];
  final List<String> _bufferIds = [];
  static const int batchSize = 1;

  // 防止同时触发多个 batch 翻译
  bool _isTranslating = false;
  bool _isDisposed = false;

  final String _geminiApiKey;

  AIOrchestratorService({
    required this.sttService,
    required this.translationService,
    this.translationFallbackService,
    required this.sessionId,
    String geminiApiKey = '',
  }) : _geminiApiKey = geminiApiKey;

  Future<String?> _callGemini(String text) async {
    if (_geminiApiKey.isEmpty) return null;
    try {
      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=$_geminiApiKey',
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'system_instruction': {'parts': [{'text': 'You are a professional translator. Translate the following English to Chinese. Output ONLY the Chinese translation, no explanations.'}]},
          'contents': [{'parts': [{'text': text}]}],
          'generationConfig': {'temperature': 0.1},
        }),
      ).timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final candidates = data['candidates'] as List?;
        if (candidates != null && candidates.isNotEmpty) {
          final parts = candidates[0]['content']?['parts'] as List?;
          if (parts != null && parts.isNotEmpty) {
            final result = parts[0]['text'] as String?;
            if (result != null && result.trim().isNotEmpty) return result.trim();
          }
        }
      }
    } catch (e) {
      debugPrint('[Orchestrator Gemini] Error: $e');
    }
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

  List<Map<String, String>>? _latestHistory;

  Future<void> processAudioSegment(
    String noteId, 
    String filePath, 
    {String? context, List<Map<String, String>>? translationHistory, Function(String)? onStatus}
  ) async {
    if (_isDisposed) return;
    _latestHistory = translationHistory;
    try {
      onStatus?.call("STT requesting...");
      
      // 1. STT 阶段（快车道）
      final rawEnglish = await ApiScheduler().enqueue(
        () => sttService.transcribe(filePath, previousText: context),
        priority: 0,
        sessionId: sessionId,
      );

      if (_isDisposed) return;

      if (rawEnglish == null || rawEnglish.trim().isEmpty) {
        onStatus?.call("Silence detected");
        _addFastEnglish(PipelineResult(noteId, "[Silence]"));
        return;
      }
      
      onStatus?.call("Cleaning text...");
      String cleanEnglish = await compute(TextSanitizer.clean, rawEnglish);
      
      // 2. 去重逻辑
      if (context != null && context.isNotEmpty && context != "...") {
        final merged = TextSanitizer.mergeOverlappingText(context, cleanEnglish);
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
      _translationBuffer.add(cleanEnglish);
      _bufferIds.add(noteId);

      if (_translationBuffer.length >= batchSize && !_isTranslating) {
        onStatus?.call("Translating batch...");
        // 非阻塞：启动翻译，不阻断 STT 快车道
        unawaited(_processTranslationBatch(onStatus: onStatus));
      } else {
        onStatus?.call("Buffering... (${_translationBuffer.length}/$batchSize)");
      }

    } catch (e, st) {
      debugPrint("[Orchestrator Error $noteId] $e\n$st");
      onStatus?.call("Pipeline Error");
      _addFastEnglish(PipelineResult(noteId, "[Error:$e]"));
    }
  }


  Future<void> _processTranslationBatch({Function(String)? onStatus}) async {
    if (_translationBuffer.isEmpty || _isTranslating || _isDisposed) return;
    _isTranslating = true;

    // 立刻快照并清空缓冲区，防止并发写入
    final batch = List<String>.from(_translationBuffer);
    final ids = List<String>.from(_bufferIds);
    _translationBuffer.clear();
    _bufferIds.clear();


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
        debugPrint("[Orchestrator] TerminologyInterceptor failed, using raw text: $e");
        textToTranslate = fullEnglish;
        lookupTable = {};
      }

      if (_isDisposed) return;
      onStatus?.call("Calling translation API...");
      
      String translatedText;
      try {
        translatedText = await ApiScheduler().enqueue(
          () => translationService.translate(textToTranslate, history: _latestHistory),
          priority: 1,
          sessionId: sessionId,
        );
      } catch (mainError) {
        debugPrint("[Orchestrator] Main translation service failed: $mainError");
        bool geminiTried = false;
        if (translationFallbackService != null) {
          try {
            onStatus?.call("Main failed. Using fallback...");
            debugPrint("[Orchestrator] Attempting translation fallback...");
            translatedText = await ApiScheduler().enqueue(
              () => translationFallbackService!.translate(textToTranslate, history: _latestHistory),
              priority: 1,
              sessionId: sessionId,
            );
          } catch (fallbackError) {
            debugPrint("[Orchestrator] Fallback also failed, trying Gemini: $fallbackError");
            onStatus?.call("Fallback failed. Trying Gemini...");
            final geminiResult = await _callGemini(textToTranslate);
            if (geminiResult != null) {
              translatedText = geminiResult;
              geminiTried = true;
            } else {
              rethrow;
            }
          }
        } else {
          final geminiResult = await _callGemini(textToTranslate);
          if (geminiResult != null) {
            translatedText = geminiResult;
            geminiTried = true;
          } else {
            rethrow;
          }
        }
        if (!geminiTried) {
          final geminiResult = await _callGemini(textToTranslate);
          if (geminiResult != null) {
            translatedText = geminiResult;
          } else {
            rethrow;
          }
        }
      }

      if (_isDisposed) return;

      // 还原术语
      final finalChinese = lookupTable.isEmpty 
          ? translatedText 
          : TerminologyInterceptor.decode(translatedText, lookupTable);

      onStatus?.call("Chinese ready");
      
      // [Architect: Batch Distribution] 将翻译后的完整段落按比例分割回填给 batch 内每个 noteId
      final sentences = finalChinese
          .split(RegExp(r'(?<=[。！？.!?])\s*'))
          .where((s) => s.trim().isNotEmpty)
          .toList();

      if (sentences.isEmpty || ids.length == 1) {
        _addAccurateChinese(PipelineResult(ids.last, finalChinese));
        // 对于其余的 id，补发一个空格，防止它们永远保持 null 导致 30 秒超时等待
        for (int i = 0; i < ids.length - 1; i++) {
          _addAccurateChinese(PipelineResult(ids[i], " "));
        }
      } else {
        // 将句子平均分配给每个 noteId
        final int perNote = (sentences.length / ids.length).ceil();
        for (int i = 0; i < ids.length; i++) {
          final start = i * perNote;
          final end = (start + perNote).clamp(0, sentences.length);
          if (start < sentences.length) {
            final chunk = sentences.sublist(start, end).join('');
            _addAccurateChinese(PipelineResult(ids[i], chunk));
          } else {
            _addAccurateChinese(PipelineResult(ids[i], " "));
          }
        }
      }
      
    } catch (e) {
      debugPrint("[Translation Batch Error] $e");
      onStatus?.call("Translation failed");
      // [Fix] 不再显示 [Translation Error]，而是把 batch 合并的英文原文作为降级显示
      // 这样中文字幕区至少不会出现红字 Error
      _addAccurateChinese(PipelineResult(ids.last, "[Translation unavailable]"));
    } finally {
      _isTranslating = false;
      
      // 如果在翻译期间有新数据累积，检查是否需要再次触发
      if (_translationBuffer.length >= batchSize) {
        unawaited(_processTranslationBatch(onStatus: onStatus));
      }
    }
  }

  /// 录音结束时强制冲刷缓冲区中的剩余文本
  Future<void> flush({Function(String)? onStatus}) async {
    if (_translationBuffer.isNotEmpty) {
      onStatus?.call("Flushing final buffer...");
      // flush 时需要 await，确保数据在导出前落盘
      await _processTranslationBatch(onStatus: onStatus);
    }
  }

  void dispose() {
    _isDisposed = true;
    _fastEnglishController.close();
    _accurateChineseController.close();
  }
}
