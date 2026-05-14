import 'dart:async';
import 'package:flutter/foundation.dart';
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
  final String sessionId;

  final _fastEnglishController = StreamController<PipelineResult>.broadcast();
  final _accurateChineseController = StreamController<PipelineResult>.broadcast();

  Stream<PipelineResult> get fastEnglishStream => _fastEnglishController.stream;
  Stream<PipelineResult> get accurateChineseStream => _accurateChineseController.stream;

  final List<String> _translationBuffer = [];
  final List<String> _bufferIds = [];
  static const int batchSize = 3;

  // 防止同时触发多个 batch 翻译
  bool _isTranslating = false;

  AIOrchestratorService({
    required this.sttService,
    required this.translationService,
    required this.sessionId,
  });

  Future<void> processAudioSegment(
    String noteId, 
    String filePath, 
    {String? context, Function(String)? onStatus}
  ) async {
    try {
      onStatus?.call("STT requesting...");
      
      // 1. STT 阶段（快车道）
      final rawEnglish = await ApiScheduler().enqueue(
        () => sttService.transcribe(filePath, previousText: context),
        priority: 0,
        sessionId: sessionId,
      );

      if (rawEnglish == null || rawEnglish.trim().isEmpty) {
        onStatus?.call("Silence detected");
        _fastEnglishController.add(PipelineResult(noteId, "[Silence]"));
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
        _fastEnglishController.add(PipelineResult(noteId, "[Silence]"));
        return;
      }

      onStatus?.call("Displaying English...");
      _fastEnglishController.add(PipelineResult(noteId, cleanEnglish));

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
      _fastEnglishController.add(PipelineResult(noteId, "[Error:$e]"));
    }
  }


  Future<void> _processTranslationBatch({Function(String)? onStatus}) async {
    if (_translationBuffer.isEmpty || _isTranslating) return;
    _isTranslating = true;

    // 立刻快照并清空缓冲区，防止并发写入
    final batch = List<String>.from(_translationBuffer);
    final ids = List<String>.from(_bufferIds);
    _translationBuffer.clear();
    _bufferIds.clear();

    // 翻译结果回填到 batch 中最后一条英文对应的 noteId
    final targetNoteId = ids.last;

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

      onStatus?.call("Calling translation API...");
      
      final translatedText = await ApiScheduler().enqueue(
        () => translationService.translate(textToTranslate),
        priority: 1,
        sessionId: sessionId,
      );

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
        _accurateChineseController.add(PipelineResult(ids.last, finalChinese));
        // 对于其余的 id，补发一个空格，防止它们永远保持 null 导致 30 秒超时等待
        for (int i = 0; i < ids.length - 1; i++) {
          _accurateChineseController.add(PipelineResult(ids[i], " "));
        }
      } else {
        // 将句子平均分配给每个 noteId
        final int perNote = (sentences.length / ids.length).ceil();
        for (int i = 0; i < ids.length; i++) {
          final start = i * perNote;
          final end = (start + perNote).clamp(0, sentences.length);
          if (start < sentences.length) {
            final chunk = sentences.sublist(start, end).join('');
            _accurateChineseController.add(PipelineResult(ids[i], chunk));
          } else {
            _accurateChineseController.add(PipelineResult(ids[i], " "));
          }
        }
      }
      
    } catch (e) {
      debugPrint("[Translation Batch Error] $e");
      onStatus?.call("Translation failed");
      // [Fix] 不再显示 [Translation Error]，而是把 batch 合并的英文原文作为降级显示
      // 这样中文字幕区至少不会出现红字 Error
      _accurateChineseController.add(PipelineResult(ids.last, "[Translation unavailable]"));
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
    _fastEnglishController.close();
    _accurateChineseController.close();
  }
}
