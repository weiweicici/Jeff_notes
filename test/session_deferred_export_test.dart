import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/models/session_ready_event.dart';
import 'package:jeff_notes/services/cloud_sync_service.dart';
import 'package:jeff_notes/services/session_background_processor.dart';

class _RecordingCloudSync implements CloudSyncService {
  final List<String> sessions = [];
  final Completer<void> called = Completer<void>();

  @override
  Future<bool> syncArchiveSession({
    required RecordingSessionContext context,
    required File file,
  }) async {
    sessions.add(context.sessionId);
    if (!called.isCompleted) called.complete();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late CloudSyncService previousCloudSync;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('jeff_deferred_export_');
    previousCloudSync = SessionBackgroundProcessor.instance.cloudSyncService;
  });

  tearDown(() async {
    SessionBackgroundProcessor.instance.cloudSyncService = previousCloudSync;
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test(
    'partial FreeTalk export is usable, deferred, and sent to cloud',
    () async {
      final context = RecordingSessionContext.create(
        mode: AppMode.freeTalk,
        unit: PathwaysUnit.none,
        baseDirectory: tempDir.path,
        customSessionId: 'partial_freetalk_test',
      );
      context.addNote(
        InsightNote(
          summary: '',
          transcript: 'available transcript',
          translatedContent: '可用转写',
          timestamp: DateTime.now(),
        ),
      );
      context.registerPendingAudio('${tempDir.path}/pending.wav');
      await context.saveShadowDraft();
      context.sealPipelines();

      final fakeCloud = _RecordingCloudSync();
      SessionBackgroundProcessor.instance.cloudSyncService = fakeCloud;
      final events = <String>[];
      SessionReadyEvent? ready;
      String? error;
      await SessionBackgroundProcessor.instance.submit(
        HandoverPayload(
          context: context,
          enableFinalRecap: false,
          onStatus: (_) {},
          onDeferred: (_) => events.add('deferred'),
          onDone: (event) {
            events.add('done');
            ready = event;
          },
          onError: (message) {
            events.add('error');
            error = message;
          },
        ),
      );
      await fakeCloud.called.future;

      expect(events, ['deferred', 'done']);
      expect(error, isNull);
      expect(ready?.isFinal, isFalse);
      expect(
        await File(context.exportPath).readAsString(),
        contains('available transcript'),
      );
      expect(await File(context.shadowDraftPath).exists(), isTrue);
      expect(fakeCloud.sessions, [context.sessionId]);
    },
  );

  test('Markdown write failure reports error without ready event', () async {
    final context = RecordingSessionContext(
      sessionId: 'write_failure_test',
      mode: AppMode.freeTalk,
      unit: PathwaysUnit.none,
      exportPath: '${tempDir.path}/missing/export.md',
      shadowDraftPath: '${tempDir.path}/shadow.json',
    );
    context.sealPipelines();
    var done = false;
    String? error;
    await SessionBackgroundProcessor.instance.submit(
      HandoverPayload(
        context: context,
        enableFinalRecap: false,
        onStatus: (_) {},
        onDone: (_) => done = true,
        onError: (message) => error = message,
      ),
    );

    expect(done, isFalse);
    expect(error, contains('Session process error'));
  });
}
