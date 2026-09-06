import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';

class UploadCache {
  static const String _key = 'uploaded_hashes';
  static final Map<String, Future<bool>> _inFlight = {};
  static final Map<String, Future<void>> _sessionTails = {};
  static Future<void> _writeTail = Future<void>.value();

  /// Runs one upload for a user-scoped content hash at a time in this process.
  ///
  /// The operation must return true only after the remote write succeeds.
  /// Failed operations are not cached, so a later scan can retry them.
  static Future<bool> runSingleFlight(
    String hash, {
    required String userId,
    String? sessionId,
    required Future<bool> Function() operation,
  }) {
    final key = _entryKey(userId, hash);
    final existing = _inFlight[key];
    if (existing != null) return existing;

    final sessionKey = sessionId == null || sessionId.isEmpty
        ? null
        : _entryKey(userId, sessionId);
    final previous = sessionKey == null
        ? Future<void>.value()
        : (_sessionTails[sessionKey] ?? Future<void>.value());
    final future = previous.then(
      (_) => _runSingleFlight(hash, userId, operation),
    );
    _inFlight[key] = future;
    if (sessionKey != null) {
      final tail = future.then<void>(
        (_) {},
        onError: (error, stackTrace) {},
      );
      _sessionTails[sessionKey] = tail;
      unawaited(tail.then((_) {
        if (identical(_sessionTails[sessionKey], tail)) {
          _sessionTails.remove(sessionKey);
        }
      }));
    }
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        },
        onError: (error, stackTrace) {
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        },
      ),
    );
    return future;
  }

  static Future<bool> _runSingleFlight(
    String hash,
    String userId,
    Future<bool> Function() operation,
  ) async {
    if (await exists(hash, userId: userId)) return true;
    final success = await operation();
    if (success) await mark(hash, userId: userId);
    return success;
  }

  static String _entryKey(String userId, String hash) => '$userId::$hash';

  static Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _writeTail.then((_) => action());
    _writeTail = result.then<void>((_) {}, onError: (error, stackTrace) {});
    return result;
  }

  static Future<Set<String>> load({String? userId}) async {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_key);
      if (raw == null) return <String>{};
      if (userId == null || userId.isEmpty) {
        // Legacy callers can still inspect old unscoped entries. Scoped
        // callers must always provide userId and never inherit these marks.
        return raw.where((entry) => !entry.contains('::')).toSet();
      }
      final prefix = '$userId::';
      return raw
          .where((entry) => entry.startsWith(prefix))
          .map((entry) => entry.substring(prefix.length))
          .toSet();
    });
  }

  static Future<void> mark(String hash, {String? userId}) async {
    await _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];
      final entry = userId == null || userId.isEmpty
          ? hash
          : _entryKey(userId, hash);
      if (!list.contains(entry)) {
        list.add(entry);
        await prefs.setStringList(_key, list);
      }
    });
  }

  static Future<bool> exists(String hash, {String? userId}) async {
    return _serialized(() async {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_key) ?? <String>[];
      final entry = userId == null || userId.isEmpty
          ? hash
          : _entryKey(userId, hash);
      return list.contains(entry);
    });
  }
}
