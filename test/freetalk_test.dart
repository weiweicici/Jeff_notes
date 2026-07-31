import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/models.dart';
import 'package:jeff_notes/recording_provider.dart';
import 'package:jeff_notes/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CredentialStore.instance.setAdapter(InMemorySecureStorageAdapter());
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => Directory.systemTemp.path,
        );
  });

  group('FreeTalk Mode Unit Tests', () {
    late RecordingProvider provider;

    test('1. AppMode.freeTalk enum presence', () {
      expect(AppMode.freeTalk.name, 'freeTalk');
      expect(AppMode.values.contains(AppMode.freeTalk), true);
    });

    test(
      '2. Verification of production RecordingProvider.formatFreeTalkContent output',
      () async {
        final mockNotes = [
          InsightNote(
            summary: '',
            transcript: 'Hello.',
            translatedContent: '你好。',
            timestamp: DateTime.now(),
          ),
          InsightNote(
            summary: '',
            transcript: 'Nice to meet you.',
            translatedContent: '很高兴认识你。',
            timestamp: DateTime.now().add(const Duration(seconds: 1)),
          ),
          InsightNote(
            summary: '',
            transcript: '[Error: bad audio]',
            translatedContent: null,
            timestamp: DateTime.now().add(const Duration(seconds: 2)),
          ),
          InsightNote(
            summary: '',
            transcript: 'Goodbye.',
            translatedContent: '再见。',
            timestamp: DateTime.now().add(const Duration(seconds: 3)),
          ),
        ];

        final result = RecordingProvider.formatFreeTalkContent(mockNotes);
        final expectedContent =
            '你好。\n很高兴认识你。\n再见。\n\nHello.\nNice to meet you.\nGoodbye.\n';
        expect(result, expectedContent);
      },
    );

    test('3. FreeTalk mode initialization in RecordingProvider', () async {
      provider = RecordingProvider();
      await provider.updateSettings(mode: AppMode.freeTalk);
      expect(provider.currentMode, AppMode.freeTalk);
    });
  });
}
