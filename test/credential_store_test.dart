import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jeff_notes/services/credential_store.dart';

class _FailingSecureStorageAdapter implements SecureStorageAdapter {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('secure storage unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CredentialStore Unit Tests', () {
    late InMemorySecureStorageAdapter mockStorage;

    setUp(() {
      mockStorage = InMemorySecureStorageAdapter();
      CredentialStore.instance.setAdapter(mockStorage);
      SharedPreferences.setMockInitialValues({});
    });

    test('1. Write and read key via secure storage adapter', () async {
      await CredentialStore.instance.writeKey(
        CredentialStore.keyGroq,
        'gsk_test_12345',
      );
      final val = await CredentialStore.instance.readKey(
        CredentialStore.keyGroq,
      );
      expect(val, 'gsk_test_12345');
    });

    test(
      '2. Migrate legacy SharedPreferences keys to secure storage',
      () async {
        SharedPreferences.setMockInitialValues({
          'gemini_api_key': 'AIza_legacy_gemini',
        });

        await CredentialStore.instance.migrateFromSharedPreferences();

        final geminiVal = await CredentialStore.instance.readKey(
          CredentialStore.keyGemini,
        );

        expect(geminiVal, 'AIza_legacy_gemini');

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.containsKey('gemini_api_key'), isFalse);
      },
    );

    test('3. Redact helper produces safe output', () {
      expect(CredentialStore.redact('sk-1234567890'), '[REDACTED]');
      expect(CredentialStore.redact(''), '[EMPTY]');
      expect(CredentialStore.redact(null), '[EMPTY]');
    });

    test('4. Migration preserves legacy key when secure write fails', () async {
      SharedPreferences.setMockInitialValues({
        'api_key_groq': 'legacy_groq_key',
      });
      CredentialStore.instance.setAdapter(_FailingSecureStorageAdapter());

      await CredentialStore.instance.migrateFromSharedPreferences();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('api_key_groq'), 'legacy_groq_key');
    });

    test('5. Direct write reports secure storage failure', () async {
      SharedPreferences.setMockInitialValues({
        CredentialStore.keyGemini: 'existing_gemini_key',
      });
      CredentialStore.instance.setAdapter(_FailingSecureStorageAdapter());

      await expectLater(
        CredentialStore.instance.writeKey(
          CredentialStore.keyGemini,
          'new_gemini_key',
        ),
        throwsA(isA<StateError>()),
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CredentialStore.keyGemini), 'existing_gemini_key');
    });
  });
}
