import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/adapters/audio_recorder_adapter.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:record/record.dart';

class _ControlledRecorder implements AudioRecorderAdapter {
  final List<String> startedPaths = <String>[];
  int stopCount = 0;
  String? currentPath;
  Completer<void>? stopGate;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<void> start(RecordConfig config, {required String path}) async {
    currentPath = path;
    startedPaths.add(path);
  }

  @override
  Future<String?> stop() async {
    stopCount++;
    await stopGate?.future;
    final path = currentPath;
    currentPath = null;
    return path;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  group('recording handoff audio ownership', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('handoff_race_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('old completion cannot stop the next session keepalive', () async {
      final recorder = _ControlledRecorder();
      final coordinator = ProcessingAudioLeaseCoordinator(recorder);
      var idleReleaseCount = 0;

      await coordinator.startKeepalive(
        sessionId: 'session_A',
        path: '${tempDir.path}/keepalive_A.wav',
        config: const RecordConfig(encoder: AudioEncoder.wav),
      );
      coordinator.beginForegroundCapture();
      await coordinator.takeOverForForegroundCapture();
      expect(recorder.stopCount, 1);
      coordinator.releaseForegroundForProcessingHandoff();

      await coordinator.startKeepalive(
        sessionId: 'session_B',
        path: '${tempDir.path}/keepalive_B.wav',
        config: const RecordConfig(encoder: AudioEncoder.wav),
      );
      expect(coordinator.keepaliveSessionId, 'session_B');

      await coordinator.releaseProcessingSession(
        'session_A',
        onAudioIdle: () async => idleReleaseCount++,
      );
      expect(recorder.stopCount, 1);
      expect(coordinator.keepaliveSessionId, 'session_B');
      expect(idleReleaseCount, 0);

      await coordinator.releaseProcessingSession(
        'session_B',
        onAudioIdle: () async => idleReleaseCount++,
      );
      expect(recorder.stopCount, 2);
      expect(coordinator.keepaliveSessionId, isNull);
      expect(idleReleaseCount, 1);
    });

    test(
      'retrying the same session releases each newly acquired lease',
      () async {
        final recorder = _ControlledRecorder();
        final coordinator = ProcessingAudioLeaseCoordinator(recorder);
        var idleReleaseCount = 0;
        for (var attempt = 0; attempt < 2; attempt++) {
          await coordinator.startKeepalive(
            sessionId: 'recovered_session',
            path: '${tempDir.path}/recovery_$attempt.wav',
            config: const RecordConfig(encoder: AudioEncoder.wav),
          );
          await coordinator.releaseProcessingSession(
            'recovered_session',
            onAudioIdle: () async => idleReleaseCount++,
          );
          expect(coordinator.hasKeepalive, isFalse);
        }
        expect(recorder.stopCount, 2);
        expect(idleReleaseCount, 2);
        await coordinator.releaseProcessingSession(
          'recovered_session',
          onAudioIdle: () async => idleReleaseCount++,
        );
        expect(recorder.stopCount, 2);
        expect(idleReleaseCount, 2);
      },
    );

    test(
      'late done and error releases are serialized and idempotent',
      () async {
        final recorder = _ControlledRecorder();
        final coordinator = ProcessingAudioLeaseCoordinator(recorder);
        var idleReleaseCount = 0;

        await coordinator.startKeepalive(
          sessionId: 'session_A',
          path: '${tempDir.path}/keepalive_A.wav',
          config: const RecordConfig(encoder: AudioEncoder.wav),
        );
        coordinator.beginForegroundCapture();
        recorder.stopGate = Completer<void>();

        final takeover = coordinator.takeOverForForegroundCapture();
        final lateDone = coordinator.releaseProcessingSession(
          'session_A',
          onAudioIdle: () async => idleReleaseCount++,
        );
        final lateError = coordinator.releaseProcessingSession(
          'session_A',
          onAudioIdle: () async => idleReleaseCount++,
        );

        recorder.stopGate!.complete();
        await Future.wait(<Future<void>>[takeover, lateDone, lateError]);

        expect(recorder.stopCount, 1);
        expect(idleReleaseCount, 0);
        expect(coordinator.keepaliveSessionId, isNull);
      },
    );

    test(
      'foreground claim protects a new recording or Watch standby',
      () async {
        final recorder = _ControlledRecorder();
        final coordinator = ProcessingAudioLeaseCoordinator(recorder);
        var idleReleaseCount = 0;

        await coordinator.startKeepalive(
          sessionId: 'old_session',
          path: '${tempDir.path}/old_keepalive.wav',
          config: const RecordConfig(encoder: AudioEncoder.wav),
        );
        coordinator.beginForegroundCapture();
        await coordinator.takeOverForForegroundCapture();
        await coordinator.releaseProcessingSession(
          'old_session',
          onAudioIdle: () async => idleReleaseCount++,
        );

        expect(recorder.stopCount, 1);
        expect(idleReleaseCount, 0);
      },
    );

    test(
      'stale recovery keepalive cannot steal foreground ownership',
      () async {
        final recorder = _ControlledRecorder();
        final coordinator = ProcessingAudioLeaseCoordinator(recorder);
        coordinator.beginForegroundCapture();

        final started = await coordinator.startKeepalive(
          sessionId: 'stale_recovery',
          path: '${tempDir.path}/stale_recovery.wav',
          config: const RecordConfig(encoder: AudioEncoder.wav),
        );

        expect(started, isFalse);
        expect(recorder.startedPaths, isEmpty);
        expect(coordinator.hasForegroundCapture, isTrue);
        expect(coordinator.keepaliveSessionId, isNull);
      },
    );

    test('explicit foreground handoff still starts a keepalive', () async {
      final recorder = _ControlledRecorder();
      final coordinator = ProcessingAudioLeaseCoordinator(recorder);
      coordinator.beginForegroundCapture();
      await coordinator.takeOverForForegroundCapture();
      coordinator.releaseForegroundForProcessingHandoff();

      final started = await coordinator.startKeepalive(
        sessionId: 'normal_handoff',
        path: '${tempDir.path}/normal_handoff.wav',
        config: const RecordConfig(encoder: AudioEncoder.wav),
      );

      expect(started, isTrue);
      expect(coordinator.hasForegroundCapture, isFalse);
      expect(coordinator.keepaliveSessionId, 'normal_handoff');
      expect(recorder.startedPaths, hasLength(1));
    });
  });

  test('record button stays enabled while an older session processes', () {
    final source = File('lib/screens/notes_screen.dart').readAsStringSync();
    expect(
      source,
      isNot(
        contains(
          'onPressed: provider.isProcessingRecording || provider.isPending',
        ),
      ),
    );
    expect(source, contains('onPressed: provider.isPending'));
    expect(
      source,
      isNot(
        contains(
          'if (!provider.isRecording && !provider.isProcessingRecording)',
        ),
      ),
    );
    expect(source, contains('if (!provider.isRecording)'));
  });

  test('Watch standby is not rejected only because processing continues', () {
    final source = File('lib/recording_provider.dart').readAsStringSync();
    expect(
      source,
      isNot(
        contains('if (_isRecording || _isProcessingRecording) return false'),
      ),
    );
    expect(source, contains('takeOverForForegroundCapture()'));
  });

  test('Watch processing state can start the next recording', () {
    final source = File(
      'ios/JeffNotesWatch/ContentView.swift',
    ).readAsStringSync();
    final processingBranch = source
        .split('} else if recording.snapshot.isProcessing {')[1]
        .split('} else {')[0];

    expect(processingBranch, contains('send("startListeningRecording")'));
    expect(processingBranch, contains('Label("开始下一段录音"'));
    expect(processingBranch, contains('.disabled(isSending)'));
  });
}
