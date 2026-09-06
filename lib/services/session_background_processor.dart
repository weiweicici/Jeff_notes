import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

import '../api_scheduler.dart';
import '../models.dart';
import '../models/recording_session_context.dart';
import '../prompt_provider.dart';
import 'shadow_draft_service.dart';
import 'cloud_sync_service.dart';
import '../models/session_ready_event.dart';
import 'diagnostic_log_service.dart';
import 'transcript_assembler.dart';
import 'wav_stitch_service.dart';

class HandoverPayload {
  final RecordingSessionContext context;
  final bool enableFinalRecap;

  /// Main isolate callbacks
  final void Function(SessionReadyEvent event) onDone;
  final void Function(String statusMsg) onStatus;

  /// Recoverable incompleteness (pending STT, rate limit, or a drain timeout)
  /// is reported separately from a failed Markdown/export write.
  final void Function(String deferredMsg)? onDeferred;
  final void Function(String errorMsg)? onError;

  HandoverPayload({
    required this.context,
    required this.enableFinalRecap,
    required this.onDone,
    required this.onStatus,
    this.onDeferred,
    this.onError,
  });
}

/// [Phase 3 Architecture]
/// Background worker processing a completed recording session.
///
/// Flow:
/// 1. Seal session in ApiScheduler (reject new tasks)
/// 2. Flush orchestrator translation buffer
/// 3. Drain orchestrator & ApiScheduler (closed-loop quiescence)
/// 4. Generate Final Academic Review / Shorthand (if enableFinalRecap)
/// 5. Write Markdown file to disk
/// 6. VERIFY file exists and size > 0
/// 7. IF Verified:
///      - Delete Shadow Draft
///      - Cloud Upsert to Supabase archives (by session_id)
///      - Notify UI onDone
///    ELSE (Failure/Timeout):
///      - KEEP Shadow Draft for recovery!
///      - Notify UI onError
class SessionBackgroundProcessor {
  static final SessionBackgroundProcessor instance =
      SessionBackgroundProcessor._();
  SessionBackgroundProcessor._();

  CloudSyncService cloudSyncService = const SupabaseCloudSyncService();
  final Map<String, Future<void>> _exportWriteQueues = {};
  int _nextAtomicWriteSequence = 0;

  Future<void> submit(HandoverPayload payload) => _process(payload);

  Future<void> _process(HandoverPayload payload) async {
    final ctx = payload.context;
    bool writeVerified = false;
    bool finalizationIncomplete = false;
    String? finalizationWarning;

    unawaited(
      DiagnosticLogService.instance.record(
        'background',
        'processing_started',
        sessionId: ctx.sessionId,
        fields: {'mode': ctx.mode.name},
      ),
    );

    try {
      // Wait for every slice admitted before handover. These pipelines may
      // still need to enqueue STT and translation work.
      payload.onStatus('Finalizing audio slices...');
      try {
        await ctx.drainPipelines(timeout: const Duration(seconds: 90));
      } catch (e) {
        finalizationIncomplete = true;
        finalizationWarning =
            'Audio finalization was incomplete; saved available transcript and kept recovery draft.';
        debugPrint(
          '[SessionBGP] Pipeline drain timeout/error for ${ctx.sessionId}: $e',
        );
      }
      if (ctx.pendingAudioNotes.isNotEmpty) {
        finalizationIncomplete = true;
        finalizationWarning ??=
            'Speech recognition was temporarily unavailable; saved available transcript and kept audio for recovery.';
      }

      // Flush only after every STT producer has settled.
      payload.onStatus('Flushing buffer...');
      try {
        if (ctx.orchestrator != null) {
          // One bounded retry of a restored/failed translation batch. Failed
          // items remain durable; drain below reports them as deferred.
          await ctx.orchestrator!.retryPendingTranslations(
            onStatus: (msg) => payload.onStatus(msg),
          );
          await ctx.orchestrator!.flush(
            onStatus: (msg) => payload.onStatus(msg),
          );
        }
      } catch (e) {
        finalizationIncomplete = true;
        finalizationWarning ??=
            'Translation finalization was incomplete; saved available transcript and kept recovery draft.';
        debugPrint('[SessionBGP] Flush error for ${ctx.sessionId}: $e');
      }

      // ─── 3. Drain orchestrator & scheduler ───────────────────
      payload.onStatus('Finalizing translations...');
      try {
        if (ctx.orchestrator != null) {
          await ctx.orchestrator!.drain(timeout: const Duration(seconds: 90));
        } else {
          await ApiScheduler().drain(
            ctx.sessionId,
            timeout: const Duration(seconds: 90),
          );
        }
      } catch (e) {
        finalizationIncomplete = true;
        finalizationWarning ??=
            'Translation finalization was incomplete; saved available transcript and kept recovery draft.';
        debugPrint('[SessionBGP] Drain timeout/error for ${ctx.sessionId}: $e');
      }

      // ─── 4. [Fix 7] Generate Final Academic Review (if enabled) ───
      if (!finalizationIncomplete &&
          payload.enableFinalRecap &&
          ctx.mode != AppMode.freeTalk) {
        payload.onStatus('Generating final AI review...');
        try {
          await _generateFinalReview(ctx);
        } catch (e) {
          finalizationIncomplete = true;
          finalizationWarning ??=
              'Final review is pending; saved available notes and kept the recovery draft.';
          debugPrint('[SessionBGP] Final recap generation error: $e');
        }
      }

      if (ctx.pendingTranslations.isNotEmpty) {
        finalizationIncomplete = true;
        finalizationWarning ??=
            'Translation is pending; saved available notes and kept the recovery draft.';
      }
      if (!await ctx.saveShadowDraft()) {
        throw StateError('Could not persist final recovery state');
      }

      // ─── 5. Write Markdown file ───────────────────────────────
      payload.onStatus('Saving Markdown notes...');
      final file = File(ctx.exportPath);
      await _writeMarkdownFile(ctx, file);

      // Restore the real-classroom recording that the MD player expects.
      // Audio failure must not destroy otherwise valid notes.
      final wavPath = ctx.exportPath.replaceAll(RegExp(r'\.md$'), '.wav');
      var audioSaved = false;
      try {
        audioSaved = await WavStitchService.stitch(
          inputPaths: ctx.rawAudioPaths,
          outputPath: wavPath,
        );
      } catch (error) {
        // A note export remains usable even when a long recovered recording
        // cannot be stitched. Never turn that optional audio failure into a
        // failed lecture session.
        debugPrint('[SessionBGP] Audio stitch failed: $error');
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'background',
          audioSaved ? 'audio_export_verified' : 'audio_export_unavailable',
          sessionId: ctx.sessionId,
          fields: {'sliceCount': ctx.rawAudioPaths.length},
        ),
      );

      // ─── 6. [Fix 6] Disk Write Verification ───────────────────
      if (await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          writeVerified = true;
        }
      }

      if (writeVerified) {
        unawaited(
          DiagnosticLogService.instance.record(
            'background',
            finalizationIncomplete
                ? 'partial_export_verified'
                : 'export_verified',
            sessionId: ctx.sessionId,
            fields: {
              'fileCount': ctx.mode == AppMode.exam ? 2 : 1,
              'primaryFile': file.uri.pathSegments.last,
            },
          ),
        );
        // ─── 7. Export verified OK ─────────────────────────────
        final eventContent = ctx.finalReviewContent?.trim().isNotEmpty == true
            ? ctx.finalReviewContent!.trim()
            : await file.readAsString();
        final readyEvent = SessionReadyEvent(
          sessionId: ctx.sessionId,
          mode: ctx.mode,
          content: eventContent,
          exportPath: ctx.exportPath,
          isFinal: !finalizationIncomplete,
          eventSequence: 1,
          recordedAt: ctx.createdAt,
        );

        payload.onStatus(
          finalizationIncomplete
              ? 'Saved available transcript; recovery draft kept.'
              : 'Saved OK!',
        );
        if (finalizationIncomplete) {
          // The Markdown snapshot is usable, but the draft may contain data
          // needed for recovery after an STT/translation timeout.
          payload.onDeferred?.call(finalizationWarning!);
          payload.onDone(readyEvent);
          // A verified partial snapshot is safe to sync. The next complete
          // export upserts the same session row with the recovered content.
          unawaited(_upsertToSupabase(ctx, file));
        } else {
          payload.onDone(readyEvent);
          // Delete Shadow Draft ONLY after a fully finalized export.
          await ShadowDraftService.instance.deleteDraft(ctx.shadowDraftPath);

          // Cloud sync the fully finalized document.
          unawaited(_upsertToSupabase(ctx, file));
        }
      } else {
        // Write verification failed!
        debugPrint(
          '[SessionBGP] CRITICAL: File write verification failed for ${ctx.sessionId}!',
        );
        payload.onError?.call('Export failed to write file cleanly.');
      }
    } catch (e, st) {
      unawaited(
        DiagnosticLogService.instance.record(
          'background',
          'processing_failed',
          sessionId: ctx.sessionId,
          fields: {'errorType': e.runtimeType},
        ),
      );
      debugPrint(
        '[SessionBGP] Unhandled process error for ${ctx.sessionId}: $e\n$st',
      );
      payload.onError?.call('Session process error: $e');
    } finally {
      // Clean up session scheduler state and close sessionHttpClient
      ApiScheduler().cancelSession(ctx.sessionId);
      ctx.dispose();
    }
  }

  /// [Fix 7] Generates final review / exam answer card / shorthand recap.
  Future<void> _generateFinalReview(RecordingSessionContext ctx) async {
    final transcript = TranscriptAssembler.english(ctx.notes);
    final timestampedTranscript = TranscriptAssembler.timestampedEnglish(
      ctx.notes,
      sessionStart: ctx.createdAt,
    );
    final rollingDraft = ctx.segmentSummaries.isEmpty
        ? '(No rolling draft was available.)'
        : ctx.segmentSummaries.last;
    final material =
        '[ROLLING NOTE DRAFT]\n$rollingDraft\n\n'
        '[FULL TRANSCRIPT — SOURCE OF TRUTH]\n$transcript\n\n'
        '[TIMESTAMPED EVIDENCE]\n$timestampedTranscript';

    if (transcript.isEmpty) {
      ctx.finalReviewContent = "Not enough material for final review.";
      return;
    }

    final finalReview = await _generateReviewWithFailover(
      ctx,
      material: material,
      mode: ctx.mode,
      diagnosticName: 'final_review',
      maxGeminiOutputTokens: ctx.mode == AppMode.exam ? 4096 : 2400,
    );
    if (_isUsableAiContent(finalReview)) {
      ctx.finalReviewContent = finalReview!.trim();
    } else {
      throw StateError('Final review is still unavailable');
    }

    if (ctx.mode == AppMode.exam) {
      final shorthand = await _generateReviewWithFailover(
        ctx,
        material: material,
        mode: AppMode.lecture,
        diagnosticName: 'shorthand',
        maxGeminiOutputTokens: 3200,
      );
      if (_isUsableAiContent(shorthand)) {
        ctx.shorthandReviewContent = shorthand!.trim();
      } else {
        throw StateError('Shorthand review is still unavailable');
      }
    }
  }

  Future<String?> _generateReviewWithFailover(
    RecordingSessionContext ctx, {
    required String material,
    required AppMode mode,
    required String diagnosticName,
    required int maxGeminiOutputTokens,
  }) async {
    Object? primaryError;
    final primary = ctx.translationService;
    // Gemini is the preferred model for the final study document. Groq is
    // second for speed, and OpenRouter is wired into fallbackTranslationService
    // as the paid third layer.
    final geminiResult = await ctx.orchestrator?.generateSummaryWithGemini(
      systemPrompt: PromptProvider.getSystemPrompt(
        PromptStrategy.recap,
        AIProvider.gemini,
        mode: mode,
        unit: ctx.unit,
      ),
      userMessage: material,
      maxOutputTokens: maxGeminiOutputTokens,
    );
    if (_isValidGeneratedContent(geminiResult, mode: mode)) {
      unawaited(
        DiagnosticLogService.instance.record(
          'ai',
          '${diagnosticName}_recovered',
          sessionId: ctx.sessionId,
          fields: {'provider': 'gemini'},
        ),
      );
      return geminiResult!.trim();
    }
    if (_isUsableAiContent(geminiResult)) {
      unawaited(
        DiagnosticLogService.instance.record(
          'ai',
          '${diagnosticName}_candidate_rejected',
          sessionId: ctx.sessionId,
          fields: {'provider': 'gemini', 'reason': 'incomplete_structure'},
        ),
      );
    }

    if (primary != null) {
      try {
        final result = await primary.summarize(
          material,
          strategy: PromptStrategy.recap,
          mode: mode,
          unit: ctx.unit,
        );
        if (_isValidGeneratedContent(result, mode: mode)) {
          return result.trim();
        }
        primaryError = StateError(
          mode == AppMode.lecture
              ? 'incomplete_shorthand_structure'
              : 'empty_or_invalid_response',
        );
      } catch (error) {
        primaryError = error;
      }
      unawaited(
        DiagnosticLogService.instance.record(
          'ai',
          '${diagnosticName}_primary_failed',
          sessionId: ctx.sessionId,
          fields: {'reason': _safeAiFailureCode(primaryError)},
        ),
      );
      debugPrint(
        '[SessionBGP] $diagnosticName Groq failed: '
        '${_safeAiFailureCode(primaryError)}',
      );
    }

    final fallback = ctx.fallbackTranslationService;
    if (fallback != null && !identical(fallback, primary)) {
      try {
        final result = await fallback.summarize(
          material,
          strategy: PromptStrategy.recap,
          mode: mode,
          unit: ctx.unit,
        );
        if (_isValidGeneratedContent(result, mode: mode)) {
          unawaited(
            DiagnosticLogService.instance.record(
              'ai',
              '${diagnosticName}_recovered',
              sessionId: ctx.sessionId,
              fields: {'provider': 'openrouter'},
            ),
          );
          return result.trim();
        }
      } catch (error) {
        debugPrint(
          '[SessionBGP] $diagnosticName fallback failed: '
          '${_safeAiFailureCode(error)}',
        );
      }
    }

    if (primary != null &&
        primaryError != null &&
        _isRetryableAiFailure(primaryError)) {
      await Future<void>.delayed(const Duration(seconds: 3));
      try {
        final result = await primary.summarize(
          material,
          strategy: PromptStrategy.recap,
          mode: mode,
          unit: ctx.unit,
        );
        if (_isValidGeneratedContent(result, mode: mode)) {
          unawaited(
            DiagnosticLogService.instance.record(
              'ai',
              '${diagnosticName}_recovered',
              sessionId: ctx.sessionId,
              fields: {'provider': 'primary_retry'},
            ),
          );
          return result.trim();
        }
      } catch (error) {
        debugPrint(
          '[SessionBGP] $diagnosticName retry failed: '
          '${_safeAiFailureCode(error)}',
        );
      }
    }

    unawaited(
      DiagnosticLogService.instance.record(
        'ai',
        '${diagnosticName}_failed_all',
        sessionId: ctx.sessionId,
      ),
    );
    return null;
  }

  bool _isUsableAiContent(String? content) {
    final trimmed = content?.trim() ?? '';
    return trimmed.isNotEmpty && !trimmed.startsWith('[');
  }

  bool _isValidGeneratedContent(String? content, {required AppMode mode}) {
    if (!_isUsableAiContent(content)) return false;
    if (mode != AppMode.lecture) return true;
    final value = content!;
    return value.contains('【全篇逻辑播报·可播放】') && value.contains('【答题重点与危险位置·可播放】');
  }

  bool _isRetryableAiFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('429') ||
        message.contains('500') ||
        message.contains('502') ||
        message.contains('503') ||
        message.contains('504') ||
        message.contains('network') ||
        message.contains('socket') ||
        message.contains('connection') ||
        message.contains('incomplete_shorthand_structure');
  }

  String _safeAiFailureCode(Object error) {
    if (error.toString().contains('incomplete_shorthand_structure')) {
      return 'incomplete_structure';
    }
    final status = RegExp(r'\b[45]\d\d\b').firstMatch(error.toString());
    return status?.group(0) ?? error.runtimeType.toString();
  }

  Future<void> _writeMarkdownFile(
    RecordingSessionContext ctx,
    File file,
  ) async {
    final now = DateTime.now();
    final isDiscussion = ctx.mode == AppMode.discussion;
    final isExam = ctx.mode == AppMode.exam;
    final isFreeTalk = ctx.mode == AppMode.freeTalk;

    if (isFreeTalk) {
      final formatted = _formatFreeTalk(ctx.notes);
      // A silent or unrecognized FreeTalk slice is still a valid recording.
      // Write a truthful audio-only marker so export verification succeeds;
      // never manufacture transcript text or leave the draft in a retry loop.
      final content = formatted.trim().isEmpty
          ? '# Free Talk Recording\n\n'
                'No transcript was produced for this recording. '
                'Check the original audio on the recording device.\n\n'
                'Session: ${ctx.sessionId}'
          : formatted;
      await _writeAtomically(file, content);
      return;
    }

    final sb = StringBuffer();
    if (isDiscussion) {
      sb.writeln('# Group Discussion Session');
      sb.writeln('**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}');
      sb.writeln(
        '**Context:** ${ctx.identifiedLectureContext ?? 'Group Discussion'}',
      );
    } else if (isExam) {
      sb.writeln('# Exam Listening Session');
      sb.writeln('**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}');
      sb.writeln(
        '**Context:** ${ctx.identifiedLectureContext ?? 'Exam Listening'}',
      );
    } else {
      sb.writeln('# Academic Lecture Session');
      sb.writeln('**Date:** ${DateFormat('yyyy-MM-dd HH:mm').format(now)}');
      sb.writeln(
        '**Context:** ${ctx.identifiedLectureContext ?? 'General Academic Lecture'}',
      );
    }
    sb.writeln();

    // Part 1: AI Review
    final reviewContent =
        ctx.finalReviewContent ?? ctx.segmentSummaries.join('\n\n');
    if (reviewContent.isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      if (isDiscussion) {
        sb.writeln('## Part 1 · AI Discussion Recap');
      } else if (isExam) {
        sb.writeln('## Part 1 · Exam Answer Card');
      } else {
        sb.writeln('## Part 1 · AI Academic Review');
      }
      sb.writeln();
      sb.writeln(reviewContent);
      sb.writeln();
    }

    // Part 2: Full Script
    final transcripts = TranscriptAssembler.validNotes(ctx.notes);
    if (transcripts.isNotEmpty) {
      sb.writeln('---');
      sb.writeln();
      sb.writeln('## Part 2 · Full Script');
      sb.writeln();

      final chineseTranscript = TranscriptAssembler.chinese(transcripts);
      final englishTranscript = TranscriptAssembler.english(transcripts);

      sb.writeln('### 中文全文 (Chinese Transcript)');
      sb.writeln();
      sb.writeln(chineseTranscript);
      sb.writeln();
      sb.writeln();
      sb.writeln('### 英文全文 (English Transcript)');
      sb.writeln();
      sb.writeln(
        _highlightText(_applyVocabHighlight(englishTranscript, ctx.unit)),
      );
      sb.writeln();
    }

    await _writeAtomically(file, sb.toString());

    // Exam sessions historically produce two documents: the answer card/full
    // transcript above and a separate shorthand document. Keep that public
    // behavior when exporting through the background session architecture.
    if (isExam) {
      final shorthandFile = File(
        '${file.parent.path}/Jeff_速记_${ctx.sessionId}.md',
      );
      await _writeAtomically(
        shorthandFile,
        _formatExamShorthand(ctx, transcripts),
      );
      if (!await shorthandFile.exists() || await shorthandFile.length() == 0) {
        throw FileSystemException(
          'Exam shorthand export verification failed',
          shorthandFile.path,
        );
      }
    }
  }

  String _formatExamShorthand(
    RecordingSessionContext ctx,
    List<InsightNote> transcripts,
  ) {
    final shorthand = ctx.shorthandReviewContent?.trim();
    final sb = StringBuffer();

    if (shorthand != null && shorthand.isNotEmpty) {
      sb.writeln(_compactShorthandLayout(shorthand));
    } else {
      debugPrint(
        '[SessionBGP] Shorthand generation unavailable for ${ctx.sessionId}',
      );
      sb
        ..writeln('【全篇逻辑播报·可播放】')
        ..writeln('AI逻辑播报整理未完成，请直接使用后方中英文全文核对讲座内容。')
        ..writeln('━━━━━━━━━━━━')
        ..writeln('【答题重点与危险位置·可播放】')
        ..writeln('AI答题证据整理未完成，请根据全文核对英文原词、数字、否定、转折和限定范围。');
    }

    final chineseTranscript = TranscriptAssembler.chinese(transcripts);
    final englishTranscript = TranscriptAssembler.english(transcripts);

    sb
      ..writeln('━━━━━━━━━━━━')
      ..writeln('【中文全文】')
      ..writeln(chineseTranscript)
      ..writeln('━━━━━━━━━━━━')
      ..writeln('【英文全文】')
      ..writeln(
        _highlightText(_applyVocabHighlight(englishTranscript, ctx.unit)),
      );
    return sb.toString();
  }

  String _compactShorthandLayout(String content) => content
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .join('\n')
      .trim();

  Future<void> _writeAtomically(File file, String content) {
    // A recovery can be requested again while an earlier recovery is still
    // finalizing.  Never let those attempts share `<export>.tmp`: the first
    // rename would otherwise remove the second attempt's temporary file.
    final outputPath = file.path;
    final previous = _exportWriteQueues[outputPath] ?? Future<void>.value();
    final operation = previous.then((_) => _writeAtomicallyOnce(file, content));
    late final Future<void> queueTail;
    queueTail = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    _exportWriteQueues[outputPath] = queueTail;

    return operation.whenComplete(() {
      if (identical(_exportWriteQueues[outputPath], queueTail)) {
        _exportWriteQueues.remove(outputPath);
      }
    });
  }

  Future<void> _writeAtomicallyOnce(File file, String content) async {
    final tempFile = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}_${_nextAtomicWriteSequence++}.tmp',
    );
    try {
      await tempFile.writeAsString(content, flush: true);
      if (await file.exists()) await file.delete();
      await tempFile.rename(file.path);
    } finally {
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    }
  }

  String _formatFreeTalk(List<InsightNote> notes) {
    final chinese = <String>[];
    final english = <String>[];
    for (final note in notes.where((n) => !n.isSummary)) {
      final en = note.transcript.trim();
      if (en.isNotEmpty && en != '...' && !en.startsWith('[')) english.add(en);
      final zh = note.translatedContent?.trim();
      if (zh != null && zh.isNotEmpty && !zh.startsWith('[')) chinese.add(zh);
    }
    final buf = StringBuffer();
    for (final zh in chinese) buf.writeln(zh);
    if (chinese.isNotEmpty && english.isNotEmpty) buf.writeln();
    for (final en in english) buf.writeln(en);
    return buf.toString();
  }

  String _highlightText(String text) {
    String result = text;
    result = result.replaceAllMapped(
      RegExp(
        r'(\d+(?:\.\d+)?\s*(?:%|percent|million|billion|thousand|trillion))',
        caseSensitive: false,
      ),
      (m) => '==${m[1]}==',
    );
    const signalWords = [
      'however',
      'therefore',
      'because of',
      'as a result',
      'consequently',
      'in contrast',
      'on the other hand',
      'for example',
      'for instance',
      'in addition',
      'moreover',
      'furthermore',
      'nevertheless',
      'notably',
      'importantly',
      'specifically',
      'in particular',
    ];
    for (final word in signalWords) {
      result = result.replaceAllMapped(
        RegExp(
          '(?<![=])\\b${RegExp.escape(word)}\\b(?![=])',
          caseSensitive: false,
        ),
        (m) => '==${m[0]}==',
      );
    }
    return result;
  }

  String _applyVocabHighlight(String text, PathwaysUnit unit) {
    if (unit == PathwaysUnit.none) return text;
    final vocab = PromptProvider.getUnitVocabularyList(unit);
    String result = text;
    for (final word in vocab) {
      final pattern = RegExp(
        '(?<!==)(?<![A-Za-z])${RegExp.escape(word)}(?![A-Za-z])(?!==)',
        caseSensitive: false,
      );
      result = result.replaceAllMapped(pattern, (m) => '==${m[0]}==');
    }
    return result;
  }

  /// [Phase 5] Supabase Upsert using CloudSyncService (Phase 1 & 5 SQL migration compliant)
  Future<void> _upsertToSupabase(RecordingSessionContext ctx, File file) async {
    try {
      await cloudSyncService.syncArchiveSession(context: ctx, file: file);
    } catch (e) {
      debugPrint('[SessionBGP Cloud Sync Error] $e');
    }
  }
}
