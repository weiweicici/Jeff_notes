import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/watch_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Watch start and stop are acknowledged before serialized execution',
    () async {
      final gate = Completer<void>();
      final executed = <String>[];
      WatchSyncService.instance.setRecordingCommandHandler((command) async {
        executed.add(command);
        if (command == 'startListeningRecording') await gate.future;
      });

      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channelName = 'com.zhenfeng.jeffnotes/watch_sync';
      const codec = StandardMethodCodec();

      Future<void> send(String command, String commandId) async {
        final reply = Completer<ByteData?>();
        messenger.handlePlatformMessage(
          channelName,
          codec.encodeMethodCall(
            MethodCall('watchCommand', <String, Object>{
              'command': command,
              'commandId': commandId,
            }),
          ),
          reply.complete,
        );
        final data = await reply.future.timeout(
          const Duration(milliseconds: 200),
        );
        codec.decodeEnvelope(data!);
      }

      final startAck = send('startListeningRecording', 'start-1');
      final stopAck = send('stopListeningRecording', 'stop-1');
      await Future.wait(<Future<void>>[startAck, stopAck]);
      expect(executed, <String>['startListeningRecording']);

      gate.complete();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(executed, <String>[
        'startListeningRecording',
        'stopListeningRecording',
      ]);
    },
  );
}
