import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Apple Watch offline companion contract', () {
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
      expect(source, contains('AVAudioPlayer(contentsOf: document.audioURL)'));
      expect(source, contains('WatchConnectivity'));
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
        expect(source, contains('SentenceRepeatMode.allCases'));
        expect(source, contains('playback.loopEnabled.toggle()'));
        expect(source, contains('[0.75, 1.0, 1.25, 1.5]'));
      },
    );

    test('phone queues only finished local package files', () {
      final bridge = File(
        'ios/Runner/WatchTransferService.swift',
      ).readAsStringSync();
      final sync = File(
        'lib/services/watch_sync_service.dart',
      ).readAsStringSync();

      for (final kind in ['audio', 'boundaries', 'markdown', 'manifest']) {
        expect(bridge, contains('("$kind",'));
      }
      expect(sync, contains("'audio_file': 'audio.mp3'"));
      expect(sync, contains("'markdown_file': 'document.md'"));
      expect(sync, contains("'repeat_count'"));
      expect(sync, contains("'loop_enabled'"));
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
