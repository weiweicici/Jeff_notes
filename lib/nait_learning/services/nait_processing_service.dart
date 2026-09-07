import 'dart:convert';
import 'dart:io';
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
import 'nait_storage_service.dart';
import 'nait_transcript_parser.dart';

class NaitProcessingService {
  final NaitStorageService _storageService;
  static const String _geminiModel = 'gemini-2.5-flash';
  static const String _groqModel = 'llama-3.3-70b-versatile';

  NaitProcessingService({NaitStorageService? storageService})
      : _storageService = storageService ?? NaitStorageService();

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

  /// Calls AI (Gemini first with Groq fallback) with the prompt and transcript.
  Future<String> callAi({required String transcriptText}) async {
    final systemPrompt = PromptProvider.getNaitClassAnalysisPrompt();
    final userPrompt = 'Transcript to analyze:\n$transcriptText';

    final geminiKey = await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    final groqKey = await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';

    // 1. Try Gemini
    if (geminiKey.isNotEmpty) {
      try {
        final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$geminiKey',
        );
        final response = await http
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

    // 2. Try Groq
    if (groqKey.isNotEmpty) {
      try {
        final url = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
        final response = await http
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
  }

  /// Processes a class session completely:
  /// 1. Reads & formats transcript
  /// 2. Invokes AI
  /// 3. Validates & parses JSON into NaitClassAnalysis
  /// 4. Extracts audio clips if normalized audio is available
  /// 5. Saves session state persistently
  Future<NaitClassSession> processClassSession({
    required NaitClassSession session,
    void Function(String statusMessage)? onProgress,
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
      final formattedTranscript = NaitTranscriptParser.formatForLlm(entries);

      onProgress?.call('Analyzing class with AI...');
      final rawAiResponse = await callAi(transcriptText: formattedTranscript);

      onProgress?.call('Extracting classroom English...');
      final analysis = parseAnalysisJson(
        rawAiResponse,
        courseId: session.courseId,
        sessionId: session.id,
        weekNumber: session.weekNumber,
      );

      // 4. Extract audio clips if normalized audio exists
      final List<NaitAudioClip> clips = [];
      if (session.normalizedAudioPath != null) {
        final normWav = File(session.normalizedAudioPath!);
        if (await normWav.exists()) {
          onProgress?.call('Creating listening clips...');
          final sessionDir = await _storageService.getSessionDir(
            session.courseId,
            session.weekNumber,
            session.id,
          );
          final clipsDir = Directory(p.join(sessionDir.path, 'clips'));
          if (!await clipsDir.exists()) {
            await clipsDir.create(recursive: true);
          }

          for (int i = 0; i < analysis.classroomEnglish.length; i++) {
            final chunk = analysis.classroomEnglish[i];
            if (chunk.audioStart != null && chunk.audioEnd != null) {
              try {
                final clipId = 'clip_${(i + 1).toString().padLeft(3, '0')}';
                final clipFile = File(p.join(clipsDir.path, '$clipId.wav'));
                await NaitAudioExtractService.extractClip(
                  normalizedWavFile: normWav,
                  start: chunk.audioStart!,
                  end: chunk.audioEnd!,
                  outputClipFile: clipFile,
                );

                final clip = NaitAudioClip(
                  id: clipId,
                  classSessionId: session.id,
                  courseId: session.courseId,
                  weekNumber: session.weekNumber,
                  label: chunk.phrase,
                  phrase: chunk.phrase,
                  start: chunk.audioStart!,
                  end: chunk.audioEnd!,
                  filePath: clipFile.path,
                  durationMs: (chunk.audioEnd! - chunk.audioStart!).inMilliseconds,
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

      onProgress?.call('Saving class...');
      session.analysis = analysis;
      session.clips = clips;
      session.status = NaitSessionStatus.processed;
      session.updatedAt = DateTime.now();
      await _storageService.saveSession(session);

      onProgress?.call('Complete');
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
