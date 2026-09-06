import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../models.dart';

/// Translation boundary used by the recording pipeline. Implementations must
/// keep transcript text on-device.
abstract interface class LocalTextTranslator {
  Future<String> translateEnglishToChinese(String text);
}

bool shouldUseOnDeviceTranslation(AppMode mode) =>
    mode == AppMode.lecture || mode == AppMode.freeTalk;

/// A single, serialized ML Kit translator shared by all recording sessions.
/// ML Kit language models are downloaded once and remain available offline.
class LocalTranslationService implements LocalTextTranslator {
  LocalTranslationService._({
    OnDeviceTranslator? translator,
    OnDeviceTranslatorModelManager? modelManager,
  }) : _translator =
           translator ??
           OnDeviceTranslator(
             sourceLanguage: TranslateLanguage.english,
             targetLanguage: TranslateLanguage.chinese,
           ),
       _modelManager = modelManager ?? OnDeviceTranslatorModelManager();

  static final LocalTranslationService instance = LocalTranslationService._();

  final OnDeviceTranslator _translator;
  final OnDeviceTranslatorModelManager _modelManager;
  Future<void> _tail = Future<void>.value();
  bool _modelsReady = false;

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    _tail = _tail.catchError((Object _) {}).then((_) async {
      try {
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<void> _ensureModelsReady({required bool isWifiRequired}) async {
    if (_modelsReady) return;
    for (final language in const [
      TranslateLanguage.english,
      TranslateLanguage.chinese,
    ]) {
      final code = language.bcpCode;
      if (await _modelManager.isModelDownloaded(code)) continue;
      final downloaded = await _modelManager.downloadModel(
        code,
        isWifiRequired: isWifiRequired,
      );
      if (!downloaded) {
        throw StateError('On-device translation model unavailable: $code');
      }
    }
    _modelsReady = true;
  }

  /// Preloads the language packs without blocking app launch. Wi-Fi is used
  /// for first-time downloads; already downloaded models work fully offline.
  Future<void> prepareModels({bool isWifiRequired = true}) =>
      _serialized(() => _ensureModelsReady(isWifiRequired: isWifiRequired));

  @override
  Future<String> translateEnglishToChinese(String text) {
    final input = text.trim();
    if (input.isEmpty) return Future<String>.value('');
    return _serialized(() async {
      await _ensureModelsReady(isWifiRequired: true);
      final translated = (await _translator.translateText(input)).trim();
      if (translated.isEmpty) {
        throw StateError('On-device translation returned empty text');
      }
      return translated;
    });
  }

  @visibleForTesting
  bool get modelsReady => _modelsReady;
}
