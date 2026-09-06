import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Apple Watch phone remote companion contract', () {
    final watchDirectory = Directory('ios/JeffNotesWatch');

    test('watch target has no AI, TTS, credential, or network client', () {
      final source = watchDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.swift'))
          .map((file) => file.readAsStringSync())
          .join('\n');

      for (final forbidden in [
        'URLSession',
        'Network.framework',
        'http://',
        'https://',
        'Gemini',
        'EdgeTts',
        'APIKey',
        'CredentialStore',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(source, isNot(contains('AVAudioPlayer')));
      expect(source, contains('WatchConnectivity'));
      expect(source, contains('sendRemoteCommand'));
    });

    test(
      'player exposes the five requested controls in the requested order',
      () {
        final source = File(
          'ios/JeffNotesWatch/ContentView.swift',
        ).readAsStringSync();
        final symbols = [
          'backward.end.fill',
          'gobackward.5',
          'playback.togglePlayPause()',
          'goforward.5',
          'forward.end.fill',
        ];
        final positions = symbols.map(source.indexOf).toList();

        expect(positions, everyElement(greaterThanOrEqualTo(0)));
        expect(List<int>.from(positions)..sort(), positions);
        expect(source, contains('控制手机 TTS'));
      },
    );

    test(
      'watch exposes phone loop and speed controls below the transport row',
      () {
        final view = File(
          'ios/JeffNotesWatch/ContentView.swift',
        ).readAsStringSync();
        final controller = File(
          'ios/JeffNotesWatch/WatchPlaybackController.swift',
        ).readAsStringSync();
        final tts = File('lib/services/tts_service.dart').readAsStringSync();

        expect(view, contains('playback.toggleLoop()'));
        expect(view, contains('playback.cycleSpeed()'));
        expect(view, contains('repeat.circle.fill'));
        expect(controller, contains('[0.75, 1.0, 1.25, 1.5]'));
        expect(controller, contains('send("toggleLoop")'));
        expect(controller, contains('send("setSpeed:\\(speed)")'));
        expect(tts, contains("case 'toggleLoop':"));
        expect(tts, contains("command.startsWith('setSpeed:')"));
      },
    );

    test(
      'phone queues markdown and optional sentence metadata, never audio',
      () {
        final bridge = File(
          'ios/Runner/WatchTransferService.swift',
        ).readAsStringSync();
        final sync = File(
          'lib/services/watch_sync_service.dart',
        ).readAsStringSync();

        for (final kind in ['boundaries', 'markdown', 'manifest']) {
          expect(bridge, contains('("$kind",'));
        }
        expect(bridge, isNot(contains('("audio",')));
        expect(bridge, isNot(contains('guard session.isWatchAppInstalled')));
        expect(sync, contains("'audio_file': 'audio.mp3'"));
        expect(sync, contains("'markdown_file': 'document.md'"));
        expect(sync, contains("'repeat_count'"));
        expect(sync, contains("'loop_enabled'"));
        expect(sync, contains('queueMarkdownDocument'));
      },
    );

    test(
      'phone retains the command channel and acknowledges real handling',
      () {
        final appDelegate = File(
          'ios/Runner/AppDelegate.swift',
        ).readAsStringSync();
        final bridge = File(
          'ios/Runner/WatchTransferService.swift',
        ).readAsStringSync();
        final sync = File(
          'lib/services/watch_sync_service.dart',
        ).readAsStringSync();

        expect(appDelegate, contains('private var watchSyncChannel:'));
        expect(appDelegate, contains('watchSyncChannel = channel'));
        expect(appDelegate, isNot(contains('[weak watchSyncChannel]')));
        expect(bridge, contains('replyHandler(["ok": accepted])'));
        expect(sync, contains('await handler(command);'));
        expect(sync, contains('return true;'));
      },
    );

    test('watch home retains document and listening entrances', () {
      final view = File(
        'ios/JeffNotesWatch/ContentView.swift',
      ).readAsStringSync();

      expect(view, contains('struct WatchHomeView'));
      expect(view, contains('title: "全部文档"'));
      expect(view, contains('title: "听力录音"'));
      expect(view, contains('WatchListeningView'));
      expect(view, contains('停止并生成'));
      expect(view, contains('latestEnglish'));
      expect(view, contains('latestChinese'));
    });

    test('phone owns recording while watch only sends remote commands', () {
      final provider = File('lib/recording_provider.dart').readAsStringSync();
      final sync = File(
        'lib/services/watch_sync_service.dart',
      ).readAsStringSync();
      final bridge = File(
        'ios/Runner/WatchTransferService.swift',
      ).readAsStringSync();

      expect(provider, contains('enterRecordingStandby'));
      expect(provider, contains('_startProcessingKeepalive'));
      expect(provider, contains('registerPendingAudio'));
      expect(provider, contains('resumeInterruptedSessions'));
      expect(sync, contains("'startListeningRecording'"));
      expect(sync, contains("'stopListeningRecording'"));
      expect(sync, contains('updateRecordingState'));
      expect(bridge, contains('updateApplicationContext(envelope)'));
    });

    test('recording commands are queued, idempotent, and acknowledged', () {
      final view = File(
        'ios/JeffNotesWatch/ContentView.swift',
      ).readAsStringSync();
      final receiver = File(
        'ios/JeffNotesWatch/WatchDocumentStore.swift',
      ).readAsStringSync();
      final bridge = File(
        'ios/Runner/WatchTransferService.swift',
      ).readAsStringSync();
      final sync = File(
        'lib/services/watch_sync_service.dart',
      ).readAsStringSync();
      final main = File('lib/main.dart').readAsStringSync();

      expect(receiver, contains('sendRecordingCommand'));
      expect(receiver, contains('"commandId": UUID().uuidString'));
      expect(receiver, contains('session.transferUserInfo(message)'));
      expect(bridge, contains('message["commandId"] is String'));
      expect(bridge, contains('pendingCommands.append(message)'));
      expect(sync, contains('_handledRecordingCommandIds'));
      expect(sync, contains('_recordingCommandTail'));
      expect(sync, contains("'recording_command_completed'"));
      expect(
        main,
        contains('final armed = await provider.enterRecordingStandby()'),
      );
      expect(view, contains('手机已收到命令'));
      expect(view, contains('命令已排队，等待手机连接'));
      expect(view, isNot(contains('Button(action: {})')));
      expect(view, isNot(contains('onLongPressGesture(minimumDuration: 0.8)')));
    });

    test('watch app is embedded inside the iPhone app bundle', () {
      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();

      expect(project, contains('Embed Watch Content'));
      expect(project, contains('dstPath = Watch;'));
      expect(project, contains('dstSubfolderSpec = 1;'));
      expect(project, contains('JeffNotesWatch.app in Embed Watch Content'));
      expect(project, contains('remoteInfo = JeffNotesWatch;'));
    });
  });
}
