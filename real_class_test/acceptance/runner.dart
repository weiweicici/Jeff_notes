import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:jeff_notes/services/credential_store.dart';
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/services/nait_audio_import_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_processing_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_storage_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_week_consolidation_service.dart';

const root = 'D:/Jeff_notes_project/real_class_test';
final evidence = File('$root/acceptance/runtime.json');
final result = <String, dynamic>{};
Future<void> record(String stage, dynamic value) async {
  result[stage] = value;
  await evidence.writeAsString(const JsonEncoder.withIndent('  ').convert(result), flush: true);
  stdout.writeln('ACCEPTANCE: $stage');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Center(child: Text('NAIT real-class acceptance running')))));
  final secrets = <String>[];
  var geminiRetries = 0;
  var groqFallback = false;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message == null) return;
    if (message.contains('trying Groq fallback')) groqFallback = true;
    if (message.contains('retrying in')) geminiRetries++;
    var clean = message;
    for (final key in secrets) { clean = clean.replaceAll(key, '[REDACTED]'); }
    stdout.writeln(clean);
  };
  try {
    final key = await CredentialStore.instance.readKey(CredentialStore.keyGemini);
    final groq = await CredentialStore.instance.readKey(CredentialStore.keyGroq);
    if (key != null && key.isNotEmpty) secrets.add(key);
    if (groq != null && groq.isNotEmpty) secrets.add(groq);
    await record('credentials', {'gemini': key?.isNotEmpty == true, 'groq': groq?.isNotEmpty == true});
    if (key == null || key.isEmpty) throw StateError('Gemini credential unavailable');
    final storage = NaitStorageService()..setBaseDir(Directory('$root/acceptance/nait'));
    final dir = await storage.getSessionDir('real_class', 1, '20260904');
    const resumeAnalysis = bool.fromEnvironment('RESUME_ANALYSIS');
    final original = resumeAnalysis ? File('${dir.path}/original_audio.mp4') : await NaitAudioImportService.preserveOriginalAudio(sourceAudio: File('$root/audio.mp4'), sessionDir: dir);
    final transcriptFile = resumeAnalysis ? File('${dir.path}/transcript.json') : (await NaitAudioImportService.importTranscript(sourceTranscript: File('$root/transcripts.json'), sessionDir: dir)).file;
    await record('import', {'reused': resumeAnalysis, 'audioBytes': await original.length(), 'transcriptPath': transcriptFile.path});
    final now = DateTime.now();
    final session = NaitClassSession(id: '20260904', courseId: 'real_class', weekNumber: 1, classDate: DateTime(2026,9,4), createdAt: now, updatedAt: now, originalAudioPath: original.path, transcriptPath: transcriptFile.path);
    final wav = resumeAnalysis ? File('${dir.path}/normalized.wav') : await NaitAudioImportService.normalizeAudio(inputFile: original, outputWavFile: File('${dir.path}/normalized.wav'));
    session.normalizedAudioPath = wav.path;
    await record('normalized', {'path': wav.path, 'bytes': await wav.length()});
    final processed = await NaitProcessingService(storageService: storage).processClassSession(session: session, onProgress: (s) => stdout.writeln('ACCEPTANCE: $s'));
    await record('analysis', {
      'geminiRetries': geminiRetries,
      'groqFallback': groqFallback,
      'status': processed.status.name,
      'mustDo': processed.analysis?.mustDo.length ?? 0,
      'lab': processed.analysis?.lab.length ?? 0,
      'important': processed.analysis?.important.length ?? 0,
      'nextClass': processed.analysis?.nextClass.length ?? 0,
      'technicalPoints': processed.analysis?.technicalPoints.length ?? 0,
      'classroomEnglish': processed.analysis?.classroomEnglish.length ?? 0,
      'askTeacher': processed.analysis?.askTeacher.length ?? 0,
      'classmateEnglish': processed.analysis?.classmateEnglish.length ?? 0,
      'clips': processed.clips.length,
    });
    final pack = await NaitWeekConsolidationService(storageService: storage).consolidateWeek(courseId: 'real_class', weekNumber: 1);
    await record('pack', {'path': pack.listeningPackPath, 'selectedClips': pack.selectedClips.map((c) => c.toJson()).toList()});
    await record('complete', true);
    exit(0);
  } catch (e) {
    var clean = e.toString();
    for (final key in secrets) { clean = clean.replaceAll(key, '[REDACTED]'); }
    await record('error', clean);
    exit(1);
  }
}
