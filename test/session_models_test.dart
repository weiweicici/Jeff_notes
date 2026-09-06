import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/models/session_ready_event.dart';
import 'package:jeff_notes/services/shadow_draft_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_models_test_');
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Phase 2 Session Models & ShadowDraftService Tests', () {
    test('1. InsightNote model serialization & standalone import', () {
      final now = DateTime.now();
      final note = InsightNote(
        summary: 'Standalone Test Summary',
        transcript: 'Testing standalone InsightNote model',
        translatedContent: '测试独立 InsightNote 模型',
        timestamp: now,
        isSummary: true,
      );

      final jsonMap = note.toJson();
      expect(jsonMap['transcript'], 'Testing standalone InsightNote model');
      expect(jsonMap['isSummary'], true);

      final deserialized = InsightNote.fromJson(jsonMap);
      expect(deserialized.transcript, note.transcript);
      expect(deserialized.translatedContent, note.translatedContent);
      expect(deserialized.isSummary, true);
    });

    test(
      '2. RecordingSessionContext factory & custom ID path sanitization',
      () {
        final ctx1 = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
          customSessionId: 'sess/with:invalid*characters\\and\\backslashes',
        );

        expect(ctx1.sessionId.contains('/'), false);
        expect(ctx1.sessionId.contains('\\'), false);
        expect(ctx1.sessionId.contains(':'), false);
        expect(ctx1.sessionId.contains('*'), false);
        expect(ctx1.exportPath.endsWith('.md'), true);
        expect(ctx1.shadowDraftPath.contains('shadow_draft_'), true);
      },
    );

    test('3. SessionReadyEvent structure and eventKey', () {
      final event = SessionReadyEvent(
        sessionId: 'sess_999',
        mode: AppMode.exam,
        content: '# Exam Summary',
        exportPath: '/tmp/notes_sess_999.md',
        isFinal: true,
        eventSequence: 2,
      );

      expect(event.sessionId, 'sess_999');
      expect(event.mode, AppMode.exam);
      expect(event.isFinal, true);
      expect(event.eventKey, 'sess_999_2');
    });

    test(
      '4. ShadowDraftService atomic save, complete recovery fields, and deletion',
      () async {
        final ctx = RecordingSessionContext.create(
          mode: AppMode.discussion,
          unit: PathwaysUnit.unit4,
          baseDirectory: tempDir.path,
        );

        ctx.addNote(
          InsightNote(
            summary: 'Discussion Point',
            transcript: 'Atomic draft test',
            translatedContent: '原子草稿测试',
            timestamp: DateTime.now(),
          ),
        );
        ctx.shorthandReviewContent = 'Shorthand Content';
        ctx.identifiedLectureContext = 'Academic Discussion';
        ctx.registerPendingAudio('${tempDir.path}/slice.wav');
        ctx.bindPendingAudioToNote(
          '${tempDir.path}/slice.wav',
          ctx.notes.first.id,
        );

        // Atomic save
        final saveSuccess = await ShadowDraftService.instance.saveDraft(ctx);
        expect(saveSuccess, true);
        expect(
          await ShadowDraftService.instance.hasDraft(ctx.shadowDraftPath),
          true,
        );

        // Read back context and verify complete fields
        final recoveredCtx = await ShadowDraftService.instance.readDraft(
          ctx.shadowDraftPath,
        );
        expect(recoveredCtx, isNotNull);
        expect(recoveredCtx!.sessionId, ctx.sessionId);
        expect(recoveredCtx.mode, AppMode.discussion);
        expect(recoveredCtx.unit, PathwaysUnit.unit4);
        expect(recoveredCtx.notes.length, 1);
        expect(recoveredCtx.notes.first.transcript, 'Atomic draft test');
        expect(recoveredCtx.shorthandReviewContent, 'Shorthand Content');
        expect(recoveredCtx.identifiedLectureContext, 'Academic Discussion');
        expect(
          recoveredCtx.pendingAudioNotes['${tempDir.path}/slice.wav'],
          ctx.notes.first.id,
        );

        // Reading a draft hydrates an in-memory context only. It must not
        // enqueue a partial snapshot or mutate the source file.
        await ShadowDraftService.instance.waitForPendingWrites(
          ctx.shadowDraftPath,
        );
        final draftFile = File(ctx.shadowDraftPath);
        final beforeBytes = await draftFile.readAsBytes();
        final beforeModified = (await draftFile.stat()).modified;
        final secondRecovered = await ShadowDraftService.instance.readDraft(
          ctx.shadowDraftPath,
        );
        expect(secondRecovered, isNotNull);
        await ShadowDraftService.instance.waitForPendingWrites(
          ctx.shadowDraftPath,
        );
        expect(await draftFile.readAsBytes(), beforeBytes);
        expect((await draftFile.stat()).modified, beforeModified);

        // Delete draft
        final deleteSuccess = await ShadowDraftService.instance.deleteDraft(
          ctx.shadowDraftPath,
        );
        expect(deleteSuccess, true);
        expect(
          await ShadowDraftService.instance.hasDraft(ctx.shadowDraftPath),
          false,
        );
      },
    );

    test(
      '5. ShadowDraftService rejects corrupted/invalid schema drafts',
      () async {
        final corruptFile = File('${tempDir.path}/shadow_draft_corrupt.json');

        // Write corrupted JSON
        await corruptFile.writeAsString(
          '{ "sessionId": "bad_schema", "mode": 999 }',
        );

        expect(
          await ShadowDraftService.instance.hasDraft(corruptFile.path),
          false,
        );
        final result = await ShadowDraftService.instance.readDraft(
          corruptFile.path,
        );
        expect(result, isNull);
      },
    );

    test(
      '6. Atomic write protects pre-existing valid draft when write target fails',
      () async {
        final ctx1 = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
        );

        ctx1.addNote(
          InsightNote(
            summary: 'Original Note',
            transcript: 'Original Content',
            timestamp: DateTime.now(),
          ),
        );

        // Save initial valid draft
        await ShadowDraftService.instance.saveDraft(ctx1);
        expect(
          await ShadowDraftService.instance.hasDraft(ctx1.shadowDraftPath),
          true,
        );

        // Create a directory at the temp path location to force atomic rename failure
        final tempPath = '${ctx1.shadowDraftPath}.tmp';
        await Directory(tempPath).create();

        // Attempt to save draft - should fail atomically without destroying original draft
        final saveResult = await ShadowDraftService.instance.saveDraft(ctx1);
        expect(saveResult, false);

        // Clean up temp dir block
        await Directory(tempPath).delete();

        // Verify original draft is still intact and readable
        final originalRead = await ShadowDraftService.instance.readDraft(
          ctx1.shadowDraftPath,
        );
        expect(originalRead, isNotNull);
        expect(originalRead!.notes.first.transcript, 'Original Content');
      },
    );

    test(
      '7. Restored drafts rebase stale iOS container paths to their current Documents directory',
      () async {
        final currentDirectory = Directory('${tempDir.path}/Documents');
        await currentDirectory.create();
        final draftPath = '${currentDirectory.path}/shadow_draft_rebased.json';
        const oldContainer =
            '/var/mobile/Containers/Data/Application/OLD-CONTAINER/Documents';
        const exportName = 'Jeff_FreeTalk_rebased.md';
        const audioName = 'rec_123.wav';
        const stitchedName = 'rec_123_stitched.wav';
        final draft = <String, dynamic>{
          'schemaVersion': ShadowDraftService.currentSchemaVersion,
          'sessionId': 'rebased',
          'mode': AppMode.freeTalk.index,
          'unit': PathwaysUnit.none.index,
          'createdAt': DateTime.now().toIso8601String(),
          'exportPath': '$oldContainer/$exportName',
          'notes': <Map<String, dynamic>>[],
          'segmentSummaries': <String>[],
          'rawAudioPaths': <String>['$oldContainer/$audioName'],
          'stitchedAudioPaths': <String>['$oldContainer/$stitchedName'],
          'pendingAudioNotes': <String, String?>{
            '$oldContainer/$audioName': null,
          },
          'finalReviewContent': null,
          'shorthandReviewContent': null,
          'identifiedLectureContext': null,
          'isCompleted': false,
        };
        await File(draftPath).writeAsString(jsonEncode(draft));

        final restored = await ShadowDraftService.instance.readDraft(draftPath);

        expect(restored, isNotNull);
        expect(restored!.exportPath, '${currentDirectory.path}/$exportName');
        expect(restored.rawAudioPaths, ['${currentDirectory.path}/$audioName']);
        expect(restored.stitchedAudioPaths, [
          '${currentDirectory.path}/$stitchedName',
        ]);
        expect(restored.pendingAudioNotes, {
          '${currentDirectory.path}/$audioName': null,
        });
      },
    );

    test(
      'capture order stays stable when a later STT slice finishes first',
      () async {
        final context = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.none,
          baseDirectory: tempDir.path,
          customSessionId: 'capture-order',
        );
        final firstPath = '${tempDir.path}/first.wav';
        final secondPath = '${tempDir.path}/second.wav';
        context.registerPendingAudio(firstPath);
        context.registerPendingAudio(secondPath);

        final second = InsightNote(
          id: 'second',
          summary: '',
          transcript: '...',
          timestamp: DateTime.now(),
        );
        context.bindPendingAudioToNote(secondPath, second.id);
        context.addAudioNote(secondPath, second);
        final first = InsightNote(
          id: 'first',
          summary: '',
          transcript: '...',
          timestamp: DateTime.now(),
        );
        context.bindPendingAudioToNote(firstPath, first.id);
        context.addAudioNote(firstPath, first);

        expect(context.notes.map((note) => note.id), ['first', 'second']);
        context.completeTranscriptForAudio(secondPath, 'Second transcript.');
        expect(context.lastTranscript, isNull);
        context.completeTranscriptForAudio(firstPath, 'First transcript.');
        expect(context.lastTranscript, 'Second transcript.');

        await context.saveShadowDraft();
        final recovered = await ShadowDraftService.instance.readDraft(
          context.shadowDraftPath,
        );
        expect(recovered!.pendingAudioSequences[firstPath], 1);
        expect(recovered.pendingAudioSequences[secondPath], 2);
      },
    );

    test(
      '8. Rejects unknown schema versions and malformed recoverable fields',
      () async {
        final ctx = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
        );
        ctx.addNote(
          InsightNote(
            summary: 'Valid',
            transcript: 'Valid note',
            timestamp: DateTime.now(),
          ),
        );
        expect(await ShadowDraftService.instance.saveDraft(ctx), true);

        final draftFile = File(ctx.shadowDraftPath);
        final valid =
            jsonDecode(await draftFile.readAsString()) as Map<String, dynamic>;

        for (final invalid in <Map<String, dynamic>>[
          {...valid, 'schemaVersion': 999},
          {...valid}..remove('schemaVersion'),
          {...valid, 'schemaVersion': 0},
          {...valid}..remove('createdAt'),
          {...valid, 'createdAt': 'not-a-date'},
          {
            ...valid,
            'notes': ['not-a-note-map'],
          },
          {
            ...valid,
            'rawAudioPaths': [42],
          },
          {...valid, 'isCompleted': 'false'},
        ]) {
          await draftFile.writeAsString(jsonEncode(invalid), flush: true);
          expect(
            await ShadowDraftService.instance.hasDraft(draftFile.path),
            false,
          );
          expect(
            await ShadowDraftService.instance.readDraft(draftFile.path),
            isNull,
          );
        }
      },
    );

    test(
      '9. Serializes overlapping saves and keeps the latest snapshot',
      () async {
        final ctx = RecordingSessionContext.create(
          mode: AppMode.exam,
          unit: PathwaysUnit.unit2,
          baseDirectory: tempDir.path,
        );
        ctx.addNote(
          InsightNote(
            summary: 'First',
            transcript: 'First snapshot',
            timestamp: DateTime.now(),
          ),
        );

        final firstSave = ShadowDraftService.instance.saveDraft(ctx);
        ctx.notes.first.transcript = 'Second snapshot';
        ctx.segmentSummaries.add('Latest summary');
        final secondSave = ShadowDraftService.instance.saveDraft(ctx);

        expect(await firstSave, true);
        expect(await secondSave, true);

        final recovered = await ShadowDraftService.instance.readDraft(
          ctx.shadowDraftPath,
        );
        expect(recovered, isNotNull);
        expect(recovered!.notes.first.transcript, 'Second snapshot');
        expect(recovered.segmentSummaries, ['Latest summary']);
      },
    );

    test(
      '10. Pipeline drain waits for admitted work and rejects late work',
      () async {
        final ctx = RecordingSessionContext.create(
          mode: AppMode.lecture,
          unit: PathwaysUnit.unit1,
          baseDirectory: tempDir.path,
        );
        var completed = false;
        var lateRan = false;
        ctx.runPipeline(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          completed = true;
        });
        ctx.sealPipelines();
        ctx.runPipeline(() async {
          lateRan = true;
        });

        await ctx.drainPipelines();
        expect(completed, isTrue);
        expect(lateRan, isFalse);
        ctx.dispose();
      },
    );
  });
}
