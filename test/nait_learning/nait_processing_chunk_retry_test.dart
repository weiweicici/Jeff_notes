import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:jeff_notes/nait_learning/models/nait_class_session.dart';
import 'package:jeff_notes/nait_learning/models/nait_transcript_entry.dart';
import 'package:jeff_notes/nait_learning/services/nait_chunking_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_processing_service.dart';
import 'package:jeff_notes/nait_learning/services/nait_storage_service.dart';
import 'package:jeff_notes/services/credential_store.dart';

class MockClient extends http.BaseClient {
  final Future<http.Response> Function(http.Request request) handler;
  MockClient(this.handler);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final req = request as http.Request;
    final res = await handler(req);
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      headers: res.headers,
    );
  }
}

http.Response mockJsonResponse(String body, int statusCode) {
  return http.Response(
    body,
    statusCode,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

const sampleChunkJson = '''
{
  "mustDo": ["Submit lab 1 on Moodle"],
  "lab": ["Step 1: Set NAT"],
  "important": ["Take snapshot"],
  "nextClass": ["Bring completed VM"],
  "technicalPoints": ["DNS resolution"],
  "classroomEnglish": [
    {
      "phrase": "leave it at default",
      "chineseMeaning": "保持默认",
      "context": "Just leave it at default.",
      "priority": 3,
      "sourceType": "teacher_original",
      "sourceTimestamp": "00:10:00"
    }
  ],
  "askTeacher": [
    {"text": "Is NAT required?", "sourceType": "practice_sentence"}
  ],
  "classmateEnglish": [
    {"text": "Is your VM working?", "sourceType": "practice_sentence"}
  ]
}
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Inject mock credentials so readKey returns non-empty strings
    CredentialStore.instance.setAdapter(InMemorySecureStorageAdapter());
    await CredentialStore.instance.writeKey(CredentialStore.keyGemini, 'mock_gemini_key');
    await CredentialStore.instance.writeKey(CredentialStore.keyGroq, 'mock_groq_key');
  });

  group('NaitProcessingService Chunk Retry & Fallback Tests', () {
    test('1. Gemini transient 503 retries with bounded backoff and succeeds on retry', () async {
      int geminiCalls = 0;
      int groqCalls = 0;

      final client = MockClient((request) async {
        if (request.url.host.contains('googleapis')) {
          geminiCalls++;
          if (geminiCalls == 1) {
            // First attempt fails with transient 503
            return http.Response('Service Unavailable', 503);
          }
          // Second attempt succeeds
          return mockJsonResponse(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': sampleChunkJson}
                    ]
                  }
                }
              ]
            }),
            200,
          );
        } else if (request.url.host.contains('groq')) {
          groqCalls++;
          return mockJsonResponse('{}', 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = NaitProcessingService(httpClient: client);

      final result = await service.callAiChunk(
        chunkText: 'Sample transcript segment text',
        maxGeminiRetries: 2,
        initialBackoff: const Duration(milliseconds: 10), // Fast test backoff
      );

      // Verify Gemini retried once and succeeded
      expect(geminiCalls, equals(2));
      // Groq was NOT called because Gemini succeeded
      expect(groqCalls, equals(0));
      expect(result.provider, equals('gemini'));
      expect(result.jsonText, contains('Submit lab 1'));
    });

    test('2. Gemini exhausted retries triggers Groq fallback for that chunk', () async {
      int geminiCalls = 0;
      int groqCalls = 0;

      final client = MockClient((request) async {
        if (request.url.host.contains('googleapis')) {
          geminiCalls++;
          // Always return 503 for Gemini
          return http.Response('Service Unavailable', 503);
        } else if (request.url.host.contains('groq')) {
          groqCalls++;
          // Groq fallback succeeds
          return mockJsonResponse(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': sampleChunkJson,
                  }
                }
              ]
            }),
            200,
          );
        }
        return http.Response('Not Found', 404);
      });

      final service = NaitProcessingService(httpClient: client);

      final result = await service.callAiChunk(
        chunkText: 'Sample transcript segment text',
        maxGeminiRetries: 2,
        initialBackoff: const Duration(milliseconds: 10),
      );

      // Gemini failed 3 times (initial + 2 retries)
      expect(geminiCalls, equals(3));
      // Groq was called exactly once and succeeded
      expect(groqCalls, equals(1));
      expect(result.provider, equals('groq'));
      expect(result.jsonText, contains('Submit lab 1'));
    });

    test('3. Chunk resume reuses completed chunk and processes only pending/failed chunks', () async {
      final tempDir = await Directory.systemTemp.createTemp('nait_resume_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      final storage = NaitStorageService()..setBaseDir(tempDir);
      final sessionDir = await storage.getSessionDir('course1', 1, 'session1');
      final chunksDir = Directory('${sessionDir.path}/chunks');
      await chunksDir.create(recursive: true);

      // Pre-seed Chunk 0 as completed in manifest and on disk
      final chunk0File = File('${chunksDir.path}/chunk_00.json');
      await chunk0File.writeAsString(sampleChunkJson);

      final manifestFile = File('${chunksDir.path}/chunk_manifest.json');
      await manifestFile.writeAsString(jsonEncode({
        'sessionId': 'session1',
        'courseId': 'course1',
        'weekNumber': 1,
        'totalChunks': 2,
        'chunks': [
          {
            'index': 0,
            'startTime': 0,
            'endTime': 1000000,
            'status': 'completed',
            'provider': 'gemini',
            'resultFile': 'chunk_00.json',
            'lastError': null,
          },
          {
            'index': 1,
            'startTime': 900000,
            'endTime': 2000000,
            'status': 'failed',
            'provider': null,
            'resultFile': null,
            'lastError': 'Previous network drop',
          }
        ]
      }));

      // Create transcript file with exactly 2 chunks
      final transcriptFile = File('${sessionDir.path}/transcript.json');
      final entries = [
        ...List.generate(15, (i) => NaitTranscriptEntry(timestamp: Duration(seconds: i * 20), text: 'Part 1 entry $i')),
        ...List.generate(10, (i) => NaitTranscriptEntry(timestamp: Duration(seconds: 320 + i * 20), text: 'Part 2 entry $i')),
      ];
      await transcriptFile.writeAsString(jsonEncode({
        'segments': entries.map((e) => {
          'audio_start_time': e.timestamp.inMilliseconds / 1000.0,
          'text': e.text,
        }).toList(),
      }));

      final now = DateTime.now();
      final session = NaitClassSession(
        id: 'session1',
        courseId: 'course1',
        weekNumber: 1,
        classDate: DateTime(2026, 9, 4),
        createdAt: now,
        updatedAt: now,
        transcriptPath: transcriptFile.path,
      );

      int networkCalls = 0;
      final client = MockClient((request) async {
        networkCalls++;
        return mockJsonResponse(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': sampleChunkJson}
                  ]
                }
              }
            ]
          }),
          200,
        );
      });

      final chunkingService = const NaitChunkingService(
        targetChunkDuration: Duration(minutes: 6),
        overlapDuration: Duration(seconds: 60),
      );

      final service = NaitProcessingService(
        storageService: storage,
        httpClient: client,
        chunkingService: chunkingService,
      );

      final processed = await service.processClassSession(
        session: session,
        maxGeminiRetries: 1,
        initialBackoff: const Duration(milliseconds: 5),
      );

      // Chunk 0 was loaded from disk, so network was called ONLY for Chunk 1!
      expect(networkCalls, equals(1));
      expect(processed.status, equals(NaitSessionStatus.processed));
      expect(processed.analysis, isNotNull);
      expect(processed.analysis!.mustDo, isNotEmpty);

      // Verify manifest now has both chunks completed
      final updatedManifest = jsonDecode(await manifestFile.readAsString());
      expect(updatedManifest['chunks'][0]['status'], equals('completed'));
      expect(updatedManifest['chunks'][1]['status'], equals('completed'));
    });
  });
}
