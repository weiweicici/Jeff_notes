import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../../prompt_provider.dart';
import '../../services/credential_store.dart';
import '../models/nait_class_analysis.dart';
import '../models/nait_class_session.dart';
import '../models/nait_english_chunk.dart';
import '../models/nait_teacher_mode_task.dart';
import '../models/nait_audio_clip.dart';
import 'nait_audio_extract_service.dart';
import 'nait_chunking_service.dart';
import 'nait_consolidation_service.dart';
import 'nait_storage_service.dart';
import 'nait_transcript_parser.dart';

class NaitProcessingService {
  final NaitStorageService _storageService;
  final NaitChunkingService _chunkingService;
  final NaitConsolidationService _consolidationService;
  final http.Client? _httpClient;

  static const String _geminiModel = 'gemini-2.5-flash';
  static const String _groqModel = 'openai/gpt-oss-120b';

  NaitProcessingService({
    NaitStorageService? storageService,
    NaitChunkingService? chunkingService,
    NaitConsolidationService? consolidationService,
    http.Client? httpClient,
  })  : _storageService = storageService ?? NaitStorageService(),
        _chunkingService = chunkingService ?? const NaitChunkingService(),
        _consolidationService = consolidationService ?? const NaitConsolidationService(),
        _httpClient = httpClient;

  /// Robust JSON cleanup: strips markdown ```json ... ``` codeblocks, handles leading/trailing whitespace.
  static String sanitizeJsonResponse(String rawResponse) {
    var text = rawResponse.trim();
    if (text.startsWith('```')) {
      text = text
          .replaceAll(RegExp(r'^```(?:json)?\s*', caseSensitive: false), '')
          .replaceAll(RegExp(r'\s*```$', caseSensitive: false), '')
          .trim();
    }
    // In case the model output has text before the first '{' or after the last '}'
    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      text = text.substring(firstBrace, lastBrace + 1).trim();
    }
    return text;
  }

  /// Parses raw JSON string into a structured [NaitClassAnalysis].
  static NaitClassAnalysis parseAnalysisJson(String jsonStr, {
    String courseId = '',
    String sessionId = '',
    int weekNumber = 1,
  }) {
    final cleanJson = sanitizeJsonResponse(jsonStr);
    final Map<String, dynamic> data = jsonDecode(cleanJson) as Map<String, dynamic>;

    List<String> parseStringList(dynamic val) {
      if (val is List) {
        return val.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      return [];
    }

    final mustDo = parseStringList(data['mustDo']);
    final lab = parseStringList(data['lab']);
    final important = parseStringList(data['important']);
    final nextClass = parseStringList(data['nextClass']);
    final technicalPoints = parseStringList(data['technicalPoints']);

    // Parse Classroom English chunks
    final List<NaitEnglishChunk> chunks = [];
    final rawChunks = data['classroomEnglish'] as List<dynamic>? ?? [];
    for (int i = 0; i < rawChunks.length; i++) {
      final item = rawChunks[i];
      if (item is Map) {
        final phrase = item['phrase'] as String? ?? '';
        if (phrase.trim().isEmpty) continue;
        final chunkId = '${sessionId}_chunk_${i + 1}';
        final chunk = NaitEnglishChunk(
          id: chunkId,
          phrase: phrase.trim(),
          chineseMeaning: item['chineseMeaning'] as String? ?? '',
          context: item['context'] as String? ?? '',
          courseId: courseId,
          classSessionId: sessionId,
          weekNumber: weekNumber,
          sourceTimestamp: NaitEnglishChunk.parseDurationString(item['sourceTimestamp']),
          audioStart: NaitEnglishChunk.parseDurationString(item['audioStart']),
          audioEnd: NaitEnglishChunk.parseDurationString(item['audioEnd']),
          priority: (item['priority'] as num?)?.toInt() ?? 1,
          sourceType: item['sourceType'] as String? ?? 'teacher_original',
        );
        chunks.add(chunk);
      }
    }

    // Parse Ask Teacher
    final List<NaitPracticeItem> askTeacher = [];
    final rawAskTeacher = data['askTeacher'] as List<dynamic>? ?? [];
    for (final item in rawAskTeacher) {
      if (item is Map) {
        final text = item['text'] as String? ?? '';
        if (text.isNotEmpty) {
          askTeacher.add(NaitPracticeItem(
            text: text,
            sourceType: item['sourceType'] as String? ?? 'practice_sentence',
          ));
        }
      } else if (item is String && item.isNotEmpty) {
        askTeacher.add(NaitPracticeItem(text: item, sourceType: 'practice_sentence'));
      }
    }

    // Parse Classmate English
    final List<NaitPracticeItem> classmateEnglish = [];
    final rawClassmates = data['classmateEnglish'] as List<dynamic>? ?? [];
    for (final item in rawClassmates) {
      if (item is Map) {
        final text = item['text'] as String? ?? '';
        if (text.isNotEmpty) {
          classmateEnglish.add(NaitPracticeItem(
            text: text,
            sourceType: item['sourceType'] as String? ?? 'practice_sentence',
          ));
        }
      } else if (item is String && item.isNotEmpty) {
        classmateEnglish.add(NaitPracticeItem(text: item, sourceType: 'practice_sentence'));
      }
    }

    // Parse Teacher Mode
    NaitTeacherModeTask? teacherMode;
    if (data['teacherMode'] is Map) {
      final tm = data['teacherMode'] as Map<String, dynamic>;
      teacherMode = NaitTeacherModeTask(
        prompt: tm['prompt'] as String? ?? '',
        suggestedOpening: tm['suggestedOpening'] as String? ?? '',
        targetChunks: parseStringList(tm['targetChunks']),
      );
    }

    return NaitClassAnalysis(
      mustDo: mustDo,
      lab: lab,
      important: important,
      nextClass: nextClass,
      technicalPoints: technicalPoints,
      classroomEnglish: chunks,
      askTeacher: askTeacher,
      classmateEnglish: classmateEnglish,
      teacherMode: teacherMode,
    );
  }

  /// Legacy single-pass AI caller preserved for backward compatibility.
  Future<String> callAi({required String transcriptText}) async {
    final systemPrompt = PromptProvider.getNaitClassAnalysisPrompt();
    final userPrompt = 'Transcript to analyze:\n$transcriptText';

    final geminiKey = await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    final groqKey = await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';

    final client = _httpClient ?? http.Client();
    final shouldCloseClient = _httpClient == null;

    try {
      if (geminiKey.isNotEmpty) {
        try {
          final url = Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
          );
          final response = await client
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
                        {'text': userPrompt},
                      ],
                    },
                  ],
                  'generationConfig': {
                    'temperature': 0.2,
                    'responseMimeType': 'application/json',
                  },
                }),
              )
              .timeout(const Duration(seconds: 90));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final candidates = data['candidates'] as List?;
            if (candidates != null && candidates.isNotEmpty) {
              final parts = candidates[0]['content']?['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                final text = parts[0]['text'] as String?;
                if (text != null && text.trim().isNotEmpty) {
                  return text;
                }
              }
            }
          }
          debugPrint('[NaitProcessing] Gemini failed (status ${response.statusCode}), trying Groq...');
        } catch (e) {
          debugPrint('[NaitProcessing] Gemini exception: $e, trying Groq...');
        }
      }

      if (groqKey.isNotEmpty) {
        try {
          final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
          final response = await client
              .post(
                url,
                headers: {
                  'Authorization': 'Bearer $groqKey',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({
                  'model': _groqModel,
                  'messages': [
                    {'role': 'system', 'content': systemPrompt},
                    {'role': 'user', 'content': userPrompt},
                  ],
                  'temperature': 0.2,
                  'response_format': {'type': 'json_object'},
                }),
              )
              .timeout(const Duration(seconds: 90));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final choices = data['choices'] as List?;
            if (choices != null && choices.isNotEmpty) {
              final content = choices[0]['message']?['content'] as String?;
              if (content != null && content.trim().isNotEmpty) {
                return content;
              }
            }
          }
          debugPrint('[NaitProcessing] Groq failed (status ${response.statusCode})');
        } catch (e) {
          debugPrint('[NaitProcessing] Groq exception: $e');
        }
      }

      throw Exception(
        'AI Analysis failed: No response from Gemini or Groq. Check your API keys in Settings.',
      );
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  /// Analyzes a single chunk with bounded retry on Gemini (503/429/timeouts) and Groq fallback.
  Future<({String jsonText, String provider})> callAiChunk({
    required String chunkText,
    int maxGeminiRetries = 2,
    Duration initialBackoff = const Duration(milliseconds: 2000),
    double backoffMultiplier = 2.0,
    void Function(String message)? onLog,
  }) async {
    final systemPrompt = PromptProvider.getNaitChunkAnalysisPrompt();
    final userPrompt = 'Transcript segment to analyze:\n$chunkText';

    final geminiKey = await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    final groqKey = await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';

    final client = _httpClient ?? http.Client();
    final shouldCloseClient = _httpClient == null;

    String? geminiLastError;
    String? groqLastError;

    try {
      // 1. Gemini primary with bounded exponential backoff
      if (geminiKey.isNotEmpty) {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
        );

        for (int attempt = 0; attempt <= maxGeminiRetries; attempt++) {
          try {
            final response = await client
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
                          {'text': userPrompt},
                        ],
                      },
                    ],
                    'generationConfig': {
                      'temperature': 0.2,
                      'responseMimeType': 'application/json',
                    },
                  }),
                )
                .timeout(const Duration(seconds: 90));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final candidates = data['candidates'] as List?;
              if (candidates != null && candidates.isNotEmpty) {
                final parts = candidates[0]['content']?['parts'] as List?;
                if (parts != null && parts.isNotEmpty) {
                  final text = parts[0]['text'] as String?;
                  if (text != null && text.trim().isNotEmpty) {
                    return (jsonText: text, provider: 'gemini');
                  }
                }
              }
              geminiLastError = 'Gemini 200 with empty candidate parts';
            } else {
              geminiLastError = 'HTTP ${response.statusCode}: ${response.body}';
              final isTransient = response.statusCode == 503 ||
                  response.statusCode == 429 ||
                  response.statusCode == 502 ||
                  response.statusCode == 504 ||
                  response.statusCode == 500;

              if (isTransient && attempt < maxGeminiRetries) {
                final delayMs = (initialBackoff.inMilliseconds * pow(backoffMultiplier, attempt)).round();
                final jitter = Random().nextInt(300);
                final waitDuration = Duration(milliseconds: delayMs + jitter);
                final msg = '[NaitProcessing] Gemini transient error (${response.statusCode}), retrying in ${waitDuration.inMilliseconds}ms (attempt ${attempt + 1}/$maxGeminiRetries)...';
                debugPrint(msg);
                onLog?.call(msg);
                await Future.delayed(waitDuration);
                continue;
              }
            }
          } catch (e) {
            geminiLastError = e.toString();
            if (attempt < maxGeminiRetries) {
              final delayMs = (initialBackoff.inMilliseconds * pow(backoffMultiplier, attempt)).round();
              final waitDuration = Duration(milliseconds: delayMs);
              final msg = '[NaitProcessing] Gemini exception ($e), retrying in ${waitDuration.inMilliseconds}ms...';
              debugPrint(msg);
              onLog?.call(msg);
              await Future.delayed(waitDuration);
              continue;
            }
          }
          break;
        }

        final fallbackMsg = '[NaitProcessing] Gemini failed ($geminiLastError), trying Groq fallback...';
        debugPrint(fallbackMsg);
        onLog?.call(fallbackMsg);
      }

      // 2. Groq Fallback
      if (groqKey.isNotEmpty) {
        try {
          final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
          for (int groqAttempt = 0; groqAttempt <= 1; groqAttempt++) {
            final response = await client
                .post(
                  url,
                  headers: {
                    'Authorization': 'Bearer $groqKey',
                    'Content-Type': 'application/json',
                  },
                  body: jsonEncode({
                    'model': _groqModel,
                    'messages': [
                      {'role': 'system', 'content': systemPrompt},
                      {'role': 'user', 'content': userPrompt},
                    ],
                    'temperature': 0.2,
                    'response_format': {'type': 'json_object'},
                  }),
                )
                .timeout(const Duration(seconds: 90));

            if (response.statusCode == 200) {
              final data = jsonDecode(response.body);
              final choices = data['choices'] as List?;
              if (choices != null && choices.isNotEmpty) {
                final content = choices[0]['message']?['content'] as String?;
                if (content != null && content.trim().isNotEmpty) {
                  return (jsonText: content, provider: 'groq');
                }
              }
              groqLastError = 'Groq 200 with empty choices';
            } else if (response.statusCode == 429 && groqAttempt == 0) {
              debugPrint('[NaitProcessing] Groq 429 rate limit, waiting 5s before retry...');
              await Future.delayed(const Duration(seconds: 5));
              continue;
            } else {
              groqLastError = 'HTTP ${response.statusCode}: ${response.body}';
              debugPrint('[NaitProcessing] Groq failed (status ${response.statusCode})');
            }
            break;
          }
        } catch (e) {
          groqLastError = e.toString();
          debugPrint('[NaitProcessing] Groq exception: $e');
        }
      }

      throw Exception(
        'Chunk AI analysis failed: Gemini error ($geminiLastError), Groq error ($groqLastError)',
      );
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  /// Processes a class session using chunk-and-consolidate pipeline:
  /// 1. Reads & parses transcript
  /// 2. Slices into overlapping chunks (~16–18 min, entry-snapped, token-budget bounded)
  /// 3. Executes per-chunk AI with bounded Gemini retry & Groq fallback
  /// 4. Persists chunk results incrementally in `chunks/` manifest for instant resume
  /// 5. Deterministically consolidates extractions
  /// 6. Extracts audio clips from full normalized WAV using timestamps
  /// 7. Saves session state (processed or partial)
  Future<NaitClassSession> processClassSession({
    required NaitClassSession session,
    void Function(String statusMessage)? onProgress,
    int? maxGeminiRetries,
    Duration? initialBackoff,
  }) async {
    session.status = NaitSessionStatus.processing;
    session.errorMessage = null;
    await _storageService.saveSession(session);

    try {
      onProgress?.call('Reading transcript...');
      if (session.transcriptPath == null) {
        throw StateError('Class session has no transcript path');
      }
      final transcriptFile = File(session.transcriptPath!);
      if (!await transcriptFile.exists()) {
        throw FileNotFoundException('Transcript file missing: ${session.transcriptPath}');
      }

      final entries = await NaitTranscriptParser.parseFile(transcriptFile);
      if (entries.isEmpty) {
        throw StateError('Transcript is empty');
      }

      final sessionDir = await _storageService.getSessionDir(
        session.courseId,
        session.weekNumber,
        session.id,
      );
      final chunksDir = Directory(p.join(sessionDir.path, 'chunks'));
      if (!await chunksDir.exists()) {
        await chunksDir.create(recursive: true);
      }
      final manifestFile = File(p.join(chunksDir.path, 'chunk_manifest.json'));

      // 1. Create chunks from entries
      final chunks = _chunkingService.createChunks(entries);
      onProgress?.call('Split transcript into ${chunks.length} chunks.');

      // 2. Load or initialize manifest
      Map<String, dynamic> manifestData = {};
      if (await manifestFile.exists()) {
        try {
          manifestData = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        } catch (_) {}
      }

      final Map<int, Map<String, dynamic>> manifestChunks = {};
      final existingRecords = manifestData['chunks'] as List<dynamic>? ?? [];
      for (final r in existingRecords) {
        if (r is Map) {
          final idx = (r['index'] as num?)?.toInt() ?? -1;
          if (idx >= 0) {
            manifestChunks[idx] = Map<String, dynamic>.from(r);
          }
        }
      }

      Future<void> saveManifest() async {
        final data = {
          'sessionId': session.id,
          'courseId': session.courseId,
          'weekNumber': session.weekNumber,
          'totalChunks': chunks.length,
          'updatedAt': DateTime.now().toIso8601String(),
          'chunks': manifestChunks.values.toList()..sort((a, b) => (a['index'] as int).compareTo(b['index'] as int)),
        };
        final tmp = File('${manifestFile.path}.tmp');
        await tmp.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
        if (await manifestFile.exists()) await manifestFile.delete();
        await tmp.rename(manifestFile.path);
      }

      final List<NaitClassAnalysis> completedAnalyses = [];
      final List<int> failedChunkIndices = [];

      // 3. Process each chunk sequentially
      for (int i = 0; i < chunks.length; i++) {
        final chunk = chunks[i];
        final record = manifestChunks[i] ?? {
          'index': i,
          'startTime': chunk.startTime.inMilliseconds,
          'endTime': chunk.endTime.inMilliseconds,
          'status': 'pending',
          'provider': null,
          'resultFile': null,
          'lastError': null,
        };
        manifestChunks[i] = record;

        final resultFileName = 'chunk_${i.toString().padLeft(2, '0')}.json';
        final chunkResultFile = File(p.join(chunksDir.path, resultFileName));

        // Check if already completed and file exists on disk
        if (record['status'] == 'completed' && await chunkResultFile.exists()) {
          try {
            final jsonStr = await chunkResultFile.readAsString();
            final analysis = parseAnalysisJson(
              jsonStr,
              courseId: session.courseId,
              sessionId: session.id,
              weekNumber: session.weekNumber,
            );
            completedAnalyses.add(analysis);
            onProgress?.call('Chunk ${i + 1}/${chunks.length} reused from cache (${record['provider'] ?? 'disk'})');
            continue;
          } catch (readErr) {
            debugPrint('[NaitProcessing] Failed to read cached chunk $i: $readErr, will reprocess');
          }
        }

        // Process chunk with AI
        onProgress?.call('Analyzing chunk ${i + 1}/${chunks.length} (~${chunk.estimatedTokenCount} tokens)...');
        record['status'] = 'processing';
        await saveManifest();

        try {
          final aiResult = await callAiChunk(
            chunkText: chunk.formattedText,
            maxGeminiRetries: maxGeminiRetries ?? 2,
            initialBackoff: initialBackoff ?? const Duration(milliseconds: 2000),
            onLog: onProgress,
          );

          // Save chunk result JSON atomically
          final tmpChunk = File('${chunkResultFile.path}.tmp');
          await tmpChunk.writeAsString(aiResult.jsonText, flush: true);
          if (await chunkResultFile.exists()) await chunkResultFile.delete();
          await tmpChunk.rename(chunkResultFile.path);

          final analysis = parseAnalysisJson(
            aiResult.jsonText,
            courseId: session.courseId,
            sessionId: session.id,
            weekNumber: session.weekNumber,
          );

          record['status'] = 'completed';
          record['provider'] = aiResult.provider;
          record['resultFile'] = resultFileName;
          record['lastError'] = null;
          await saveManifest();

          completedAnalyses.add(analysis);
          onProgress?.call('Chunk ${i + 1}/${chunks.length} PASS (${aiResult.provider})');

          // 1.0s pacing delay between network calls
          await Future.delayed(const Duration(milliseconds: 1000));
        } catch (chunkErr) {
          debugPrint('[NaitProcessing] Error processing chunk $i: $chunkErr');
          record['status'] = 'failed';
          record['lastError'] = chunkErr.toString();
          await saveManifest();
          failedChunkIndices.add(i);
        }
      }

      // 4. Evaluate outcome
      if (completedAnalyses.isEmpty) {
        throw StateError('AI Analysis failed for all ${chunks.length} chunks. Check your API keys and provider connections.');
      }

      final isFullyCompleted = completedAnalyses.length == chunks.length;

      onProgress?.call(isFullyCompleted
          ? 'Consolidating complete class analysis...'
          : 'Consolidating partial analysis (${completedAnalyses.length}/${chunks.length} chunks)...');

      final consolidatedAnalysis = _consolidationService.consolidate(
        chunkAnalyses: completedAnalyses,
        courseId: session.courseId,
        sessionId: session.id,
        weekNumber: session.weekNumber,
      );

      // 5. Extract clips from full normalized WAV only if normalized audio exists
      final List<NaitAudioClip> clips = [];
      if (session.normalizedAudioPath != null) {
        final normWav = File(session.normalizedAudioPath!);
        if (await normWav.exists()) {
          onProgress?.call('Creating listening clips...');
          final clipsDir = Directory(p.join(sessionDir.path, 'clips'));
          if (!await clipsDir.exists()) {
            await clipsDir.create(recursive: true);
          }

          for (int i = 0; i < consolidatedAnalysis.classroomEnglish.length; i++) {
            final chunk = consolidatedAnalysis.classroomEnglish[i];
            if (chunk.audioStart != null && chunk.audioEnd != null) {
              try {
                final bounds = NaitAudioExtractService.resolveConservativeClipBounds(
                  audioStart: chunk.audioStart!,
                  audioEnd: chunk.audioEnd!,
                  transcriptEntries: entries,
                );
                chunk.audioStart = bounds.start;
                chunk.audioEnd = bounds.end;
                final clipId = 'clip_${(i + 1).toString().padLeft(3, '0')}';
                final clipFile = File(p.join(clipsDir.path, '$clipId.wav'));
                await NaitAudioExtractService.extractClip(
                  normalizedWavFile: normWav,
                  start: bounds.start,
                  end: bounds.end,
                  outputClipFile: clipFile,
                );

                final clip = NaitAudioClip(
                  id: clipId,
                  classSessionId: session.id,
                  courseId: session.courseId,
                  weekNumber: session.weekNumber,
                  label: chunk.phrase,
                  phrase: chunk.phrase,
                  start: bounds.start,
                  end: bounds.end,
                  filePath: clipFile.path,
                  durationMs: (bounds.end - bounds.start).inMilliseconds,
                );
                clips.add(clip);
                chunk.audioClipId = clipId;
              } catch (clipErr) {
                debugPrint('[NaitProcessing] Error extracting clip for "${chunk.phrase}": $clipErr');
              }
            }
          }
        }
      }

      session.analysis = consolidatedAnalysis;
      session.clips = clips;
      session.updatedAt = DateTime.now();

      if (isFullyCompleted) {
        session.status = NaitSessionStatus.processed;
        session.errorMessage = null;
        onProgress?.call('Complete');
      } else {
        session.status = NaitSessionStatus.partial;
        session.errorMessage = 'Partial analysis: ${completedAnalyses.length} of ${chunks.length} chunks completed. '
            'Failed chunk indices: ${failedChunkIndices.join(', ')}';
        onProgress?.call('Completed with partial analysis (${completedAnalyses.length}/${chunks.length} chunks)');
      }

      await _storageService.saveSession(session);
      return session;
    } catch (e, stack) {
      debugPrint('[NaitProcessing] Processing error: $e\n$stack');
      session.status = NaitSessionStatus.failed;
      session.errorMessage = e.toString();
      session.updatedAt = DateTime.now();
      await _storageService.saveSession(session);
      rethrow;
    }
  }
}
