import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/models/recording_session_context.dart';
import 'package:jeff_notes/models/session_ready_event.dart';
import 'package:jeff_notes/services/cloud_sync_service.dart';
import 'package:jeff_notes/services/session_background_processor.dart';
import 'package:jeff_notes/services/wav_stitch_service.dart';

void main() {
  test('empty FreeTalk still exports truthful audio-only markdown', () async {
    final directory = await Directory.systemTemp.createTemp('empty_ft_');
    addTearDown(() => directory.delete(recursive: true));
    final context = RecordingSessionContext.create(
      mode: AppMode.freeTalk,
      unit: PathwaysUnit.none,
      baseDirectory: directory.path,
      customSessionId: 'empty_freetalk',
    );
    final oldCloud = SessionBackgroundProcessor.instance.cloudSyncService;
    final fakeCloud = FakeCloudSyncService();
    SessionBackgroundProcessor.instance.cloudSyncService = fakeCloud;
    addTearDown(() {
      SessionBackgroundProcessor.instance.cloudSyncService = oldCloud;
    });
    final wav = File('${directory.path}/slice.wav');
    await wav.writeAsBytes([
      ...WavStitchService.wavHeader(320),
      ...List<int>.filled(320, 0),
    ]);
    context.addRawAudioPath(wav.path);
    context.sealPipelines();
    SessionReadyEvent? ready;
    String? fatal;
    await SessionBackgroundProcessor.instance.submit(
      HandoverPayload(
        context: context,
        enableFinalRecap: false,
        onDone: (event) => ready = event,
        onStatus: (_) {},
        onError: (error) => fatal = error,
      ),
    );
    final markdown = File(context.exportPath);
    expect(ready, isNotNull);
    expect(ready!.isFinal, isTrue);
    expect(
      await markdown.readAsString(),
      contains('No transcript was produced'),
    );
    expect(await markdown.length(), greaterThan(0));
    expect(fatal, isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final merged = File(
      context.exportPath.replaceAll(RegExp(r'\.md$'), '.wav'),
    );
    expect(await merged.length(), greaterThan(44));
    expect(await wav.exists(), isTrue);
    expect(await File(context.shadowDraftPath).exists(), isFalse);
  });
}
