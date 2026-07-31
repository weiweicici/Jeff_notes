import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SecureStorageAdapter {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DefaultSecureStorageAdapter implements SecureStorageAdapter {
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<String?> read(String key) async => await _storage.read(key: key);

  @override
  Future<void> write(String key, String value) async =>
      await _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) async => await _storage.delete(key: key);
}

class InMemorySecureStorageAdapter implements SecureStorageAdapter {
  final Map<String, String> _data = {};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

class CredentialStore {
  CredentialStore._();
  static final CredentialStore instance = CredentialStore._();

  SecureStorageAdapter _adapter = DefaultSecureStorageAdapter();

  @visibleForTesting
  void setAdapter(SecureStorageAdapter adapter) {
    _adapter = adapter;
  }

  static const String keyGroq = 'api_key_groq';
  static const String keyGemini = 'api_key_gemini';
  static const String keyOpenAI = 'api_key_openai';
  static const String keySiliconFlow = 'api_key_siliconFlow';
  static const String keyOpenRouter = 'api_key_openrouter';

  /// Performs one-time migration of legacy API keys stored in SharedPreferences
  /// to secure storage with per-key exception isolation.
  Future<void> migrateFromSharedPreferences() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint(
        '[CredentialStore] Failed to open SharedPreferences for migration: $e',
      );
      return;
    }

    final migrationMappings = <String, String>{
      'api_key_groq': keyGroq,
      'groq_api_key': keyGroq,
      'api_key_gemini': keyGemini,
      'gemini_api_key': keyGemini,
      'api_key_openai': keyOpenAI,
      'openai_api_key': keyOpenAI,
      'api_key_siliconFlow': keySiliconFlow,
      'api_key_siliconflow': keySiliconFlow,
      'siliconflow_api_key': keySiliconFlow,
      'api_key_silicon_flow': keySiliconFlow,
      'api_key_openrouter': keyOpenRouter,
      'openrouter_api_key': keyOpenRouter,
    };

    for (final entry in migrationMappings.entries) {
      final legacyKey = entry.key;
      final targetKey = entry.value;

      try {
        final legacyValue = prefs.getString(legacyKey);
        if (legacyValue != null && legacyValue.trim().isNotEmpty) {
          final existingSecure = await _readSecure(targetKey);
          if (existingSecure == null || existingSecure.trim().isEmpty) {
            await _writeSecure(targetKey, legacyValue.trim());
          }
          await prefs.remove(legacyKey);
        }
      } catch (e) {
        debugPrint('[CredentialStore] Migration failed for key $legacyKey: $e');
      }
    }
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _adapter.read(key);
    } catch (e) {
      debugPrint(
        '[CredentialStore] Native secure storage read failed for $key: $e',
      );
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _adapter.write(key, value);
    } catch (e) {
      debugPrint(
        '[CredentialStore] Native secure storage write failed for $key: $e',
      );
      rethrow;
    }
  }

  Future<String?> readKey(String keyName) async {
    final normalized = _normalizeKey(keyName);
    final secureVal = await _readSecure(normalized);
    if (secureVal != null && secureVal.isNotEmpty) {
      return secureVal;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(keyName) ?? prefs.getString(normalized);
    } catch (_) {
      return null;
    }
  }

  Future<void> writeKey(String keyName, String value) async {
    final normalized = _normalizeKey(keyName);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _adapter.delete(normalized);
    } else {
      await _writeSecure(normalized, trimmed);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyName);
      await prefs.remove(normalized);
    } catch (_) {}
  }

  Future<void> deleteKey(String keyName) async {
    final normalized = _normalizeKey(keyName);
    await _adapter.delete(normalized);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyName);
      await prefs.remove(normalized);
    } catch (_) {}
  }

  String _normalizeKey(String key) {
    if (key == 'api_key_siliconflow' || key == 'siliconflow_api_key')
      return keySiliconFlow;
    if (key == 'groq_api_key') return keyGroq;
    if (key == 'gemini_api_key') return keyGemini;
    if (key == 'openai_api_key') return keyOpenAI;
    if (key == 'openrouter_api_key') return keyOpenRouter;
    return key;
  }

  /// Returns "[REDACTED]" strictly avoiding key leakage in log files.
  static String redact(String? value) {
    if (value == null || value.isEmpty) return '[EMPTY]';
    return '[REDACTED]';
  }
}
