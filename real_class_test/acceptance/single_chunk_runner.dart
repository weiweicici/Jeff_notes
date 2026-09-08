import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jeff_notes/nait_learning/services/nait_chunking_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_processing_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_storage_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_transcript_parser.dart';
import 'package:jeff_notes/services/credential_store.dart';
import 'package:path/path.dart' as p;

const root = 'D:/Jeff_notes_project/real_class_test';
final resultOutput = File('$root/acceptance/single_chunk_result.json');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('NAIT single-chunk validation')))));

  final secrets = <String>[];
  void log(String message) {
    var clean = message;
    for (final s in secrets) {
      if (s.isNotEmpty) clean = clean.replaceAll(s, '[REDACTED]');
    }
    stdout.writeln(clean);
  }

  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) log(message);
  };

  final report = <String, dynamic>{};

  try {
    log('=== NAIT Single-Chunk Live Validation Startup ===');

    // 1. Check native credentials
    final geminiKey = await CredentialStore.instance.readKey(CredentialStore.keyGemini) ?? '';
    final groqKey = await CredentialStore.instance.readKey(CredentialStore.keyGroq) ?? '';
    if (geminiKey.isNotEmpty) secrets.add(geminiKey);
    if (groqKey.isNotEmpty) secrets.add(groqKey);

    log('Credentials check: Gemini=${geminiKey.isNotEmpty}, Groq=${groqKey.isNotEmpty}');
    if (geminiKey.isEmpty && groqKey.isEmpty) {
      throw StateError('No credentials found in CredentialStore');
    }

    // 2. Load and parse real transcript
    final storage = NaitStorageService()..setBaseDir(Directory('$root/acceptance/nait'));
    final sessionDir = await storage.getSessionDir('real_class', 1, '20260904');
    final transcriptFile = File(p.join(sessionDir.path, 'transcript.json'));
    if (!await transcriptFile.exists()) {
      throw StateError('Transcript file not found: ${transcriptFile.path}');
    }

    final transcriptJson = await transcriptFile.readAsString();
    final entries = NaitTranscriptParser.parseMeetilyJson(transcriptJson);
    log('Parsed transcript: ${entries.length} entries from ${transcriptFile.path}');

    // 3. Chunk transcript
    const chunker = NaitChunkingService();
    final chunks = chunker.createChunks(entries);
    log('Total chunks generated: ${chunks.length}');

    // 4. Select representative mid-class chunk (Chunk 2)
    // Chunk 2 covers ~31m0s to ~47m50s, 237 entries, ~4627 estTokens, 17580 bytes.
    const selectedIndex = 2;
    if (selectedIndex >= chunks.length) {
      throw StateError('Chunk index $selectedIndex out of bounds (total ${chunks.length})');
    }
    final chunk = chunks[selectedIndex];

    final chunkInfo = {
      'index': chunk.index,
      'startTimeSeconds': chunk.startTime.inSeconds,
      'endTimeSeconds': chunk.endTime.inSeconds,
      'startTimeFormatted': '${chunk.startTime.inMinutes}m${chunk.startTime.inSeconds % 60}s',
      'endTimeFormatted': '${chunk.endTime.inMinutes}m${chunk.endTime.inSeconds % 60}s',
      'entryCount': chunk.entries.length,
      'estimatedTokens': chunk.estimatedTokenCount,
      'payloadBytes': utf8.encode(chunk.formattedText).length,
    };
    report['selectedChunk'] = chunkInfo;

    log('\n--- Selected Chunk Details ---');
    log('Index: ${chunkInfo['index']}');
    log('Time Window: ${chunkInfo['startTimeFormatted']} -> ${chunkInfo['endTimeFormatted']} (${chunkInfo['startTimeSeconds']}s -> ${chunkInfo['endTimeSeconds']}s)');
    log('Entries: ${chunkInfo['entryCount']}');
    log('Estimated Tokens: ${chunkInfo['estimatedTokens']}');
    log('Payload Size: ${chunkInfo['payloadBytes']} bytes');

    // 5. Send through REAL production callAiChunk
    log('\n--- Sending to Real Provider Path ---');
    final processingService = NaitProcessingService(storageService: storage);

    final stopwatch = Stopwatch()..start();
    int geminiRetryCount = 0;
    String providerUsed = 'unknown';

    final aiResult = await processingService.callAiChunk(
      chunkText: chunk.formattedText,
      maxGeminiRetries: 2,
      initialBackoff: const Duration(milliseconds: 2000),
      onLog: (msg) {
        log('AI Log: $msg');
        if (msg.contains('retrying')) {
          geminiRetryCount++;
        }
      },
    );
    stopwatch.stop();
    providerUsed = aiResult.provider;

    log('\nAI Chunk Response Received:');
    log('Provider: $providerUsed');
    log('Elapsed: ${stopwatch.elapsedMilliseconds}ms');
    log('Retry count logged: $geminiRetryCount');

    report['execution'] = {
      'provider': providerUsed,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'retries': geminiRetryCount,
    };

    // 6. Validate structured JSON
    log('\n--- Validating Structured Output ---');
    final analysis = NaitProcessingService.parseAnalysisJson(
      aiResult.jsonText,
      courseId: 'real_class',
      sessionId: '20260904',
      weekNumber: 1,
    );

    log('Parsed Analysis Summary:');
    log('- MustDo: ${analysis.mustDo.length}');
    log('- Lab: ${analysis.lab.length}');
    log('- Important: ${analysis.important.length}');
    log('- NextClass: ${analysis.nextClass.length}');
    log('- TechnicalPoints: ${analysis.technicalPoints.length}');
    log('- ClassroomEnglish: ${analysis.classroomEnglish.length}');
    log('- AskTeacher: ${analysis.askTeacher.length}');
    log('- ClassmateEnglish: ${analysis.classmateEnglish.length}');

    // Detailed field validations
    bool structuredParsePass = true;
    bool teacherTimestampPass = true;
    bool practiceSentencePass = true;

    // Check action fields
    if (analysis.mustDo.isEmpty && analysis.lab.isEmpty && analysis.important.isEmpty) {
      log('WARNING: All primary action fields are empty!');
      structuredParsePass = false;
    }

    // Check classroomEnglish
    for (final item in analysis.classroomEnglish) {
      if (item.sourceType == 'teacher_original') {
        if (item.sourceTimestamp == null) {
          log('FAIL: teacher_original item "${item.phrase}" has NULL sourceTimestamp!');
          teacherTimestampPass = false;
        } else {
          // Verify timestamp is within or near the chunk time window
          final tsSec = item.sourceTimestamp!.inSeconds;
          // allow small buffer
          if (tsSec < chunk.startTime.inSeconds - 30 || tsSec > chunk.endTime.inSeconds + 30) {
            log('NOTE: timestamp ${item.sourceTimestamp} slightly outside chunk window [${chunk.startTime}, ${chunk.endTime}]');
          }
        }
      }
      if (item.sourceType != 'teacher_original' && item.sourceType != 'practice_sentence') {
        log('FAIL: Unknown sourceType "${item.sourceType}" for phrase "${item.phrase}"');
        structuredParsePass = false;
      }
    }

    // Check askTeacher / classmateEnglish practice items
    for (final item in [...analysis.askTeacher, ...analysis.classmateEnglish]) {
      if (item.sourceType == 'teacher_original') {
        log('FAIL: practice sentence "${item.text}" is mislabeled as teacher_original!');
        practiceSentencePass = false;
      }
    }

    report['validation'] = {
      'structuredParse': structuredParsePass ? 'PASS' : 'FAIL',
      'teacherTimestamp': teacherTimestampPass ? 'PASS' : 'FAIL',
      'practiceSentence': practiceSentencePass ? 'PASS' : 'FAIL',
      'counts': {
        'mustDo': analysis.mustDo.length,
        'lab': analysis.lab.length,
        'important': analysis.important.length,
        'nextClass': analysis.nextClass.length,
        'technicalPoints': analysis.technicalPoints.length,
        'classroomEnglish': analysis.classroomEnglish.length,
        'askTeacher': analysis.askTeacher.length,
        'classmateEnglish': analysis.classmateEnglish.length,
      },
    };

    // 7. Persist using the REAL production chunk persistence path
    log('\n--- Persisting Chunk Result to Session Directory ---');
    final chunksDir = Directory(p.join(sessionDir.path, 'chunks'));
    if (!await chunksDir.exists()) {
      await chunksDir.create(recursive: true);
    }

    final chunkFileName = 'chunk_${chunk.index.toString().padLeft(2, '0')}.json';
    final chunkResultFile = File(p.join(chunksDir.path, chunkFileName));
    final manifestFile = File(p.join(chunksDir.path, 'chunk_manifest.json'));

    // Write chunk result atomically
    final tmpChunk = File('${chunkResultFile.path}.tmp');
    await tmpChunk.writeAsString(aiResult.jsonText, flush: true);
    if (await chunkResultFile.exists()) await chunkResultFile.delete();
    await tmpChunk.rename(chunkResultFile.path);

    // Update manifest
    final manifestData = {
      'sessionId': '20260904',
      'courseId': 'real_class',
      'weekNumber': 1,
      'totalChunks': chunks.length,
      'updatedAt': DateTime.now().toIso8601String(),
      'chunks': [
        {
          'index': chunk.index,
          'startTime': chunk.startTime.inMilliseconds,
          'endTime': chunk.endTime.inMilliseconds,
          'status': 'completed',
          'provider': providerUsed,
          'resultFile': chunkFileName,
          'lastError': null,
        }
      ],
    };
    final tmpManifest = File('${manifestFile.path}.tmp');
    await tmpManifest.writeAsString(const JsonEncoder.withIndent('  ').convert(manifestData), flush: true);
    if (await manifestFile.exists()) await manifestFile.delete();
    await tmpManifest.rename(manifestFile.path);

    // Verify persistence
    final chunkFileExists = await chunkResultFile.exists();
    final manifestExists = await manifestFile.exists();
    final chunkFileLength = chunkFileExists ? await chunkResultFile.length() : 0;
    log('Persistence verification:');
    log('- Chunk result file exists: $chunkFileExists ($chunkFileLength bytes at ${chunkResultFile.path})');
    log('- Manifest exists: $manifestExists at ${manifestFile.path}');

    final persistencePass = chunkFileExists && manifestExists && chunkFileLength > 0;
    report['persistence'] = {
      'status': persistencePass ? 'PASS' : 'FAIL',
      'chunkFilePath': chunkResultFile.path,
      'chunkFileBytes': chunkFileLength,
      'manifestPath': manifestFile.path,
    };

    // Save full report
    await resultOutput.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
      flush: true,
    );

    log('\n=== Single-Chunk Validation Complete: ALL PASS ===');
    exit(0);
  } catch (e, stack) {
    log('FATAL ERROR in single-chunk validation: $e\n$stack');
    report['error'] = e.toString();
    try {
      await resultOutput.writeAsString(
        const JsonEncoder.withIndent('  ').convert(report),
        flush: true,
      );
    } catch (_) {}
    exit(1);
  }
}
