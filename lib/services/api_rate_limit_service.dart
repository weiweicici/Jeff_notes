import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A provider rejected a request because its quota/rate limit is exhausted.
/// The retry time is deliberately exposed without retaining response bodies.
class ApiRateLimitException implements Exception {
  final String provider;
  final String model;
  final DateTime retryAt;
  final String source;

  const ApiRateLimitException({
    required this.provider,
    required this.model,
    required this.retryAt,
    this.source = 'http_429',
  });

  Duration get retryAfter {
    final remaining = retryAt.difference(DateTime.now().toUtc());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  @override
  String toString() =>
      'ApiRateLimitException(provider=$provider, model=$model, retryAt=${retryAt.toIso8601String()})';
}

/// Shared, persisted provider/model cooldown state. It is intentionally
/// independent of API credentials and response bodies.
class ApiRateLimitService {
  static final ApiRateLimitService instance = ApiRateLimitService._();

  final Future<SharedPreferences> Function() _prefsLoader;
  final DateTime Function() _clock;
  final Map<String, DateTime> _cooldowns = {};
  final Map<String, int> _strikes = {};
  final Map<String, DateTime> _lastRequest = {};
  Future<void> _tail = Future<void>.value();

  ApiRateLimitService._({
    Future<SharedPreferences> Function()? prefsLoader,
    DateTime Function()? clock,
  }) : _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
       _clock = clock ?? (() => DateTime.now().toUtc());

  /// Constructor for behavior tests; production callers should use [instance].
  ApiRateLimitService.forTesting({
    required Future<SharedPreferences> Function() prefsLoader,
    required DateTime Function() clock,
  }) : _prefsLoader = prefsLoader,
       _clock = clock;

  String _key(String provider, String model) =>
      'api_rate_limit_${provider.trim().toLowerCase()}_${model.trim()}';

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (error, stackTrace) {});
    return result;
  }

  Future<void> ensureAvailable(String provider, String model) async {
    final key = _key(provider, model);
    final blocked = await _serialized(() async {
      var until = _cooldowns[key];
      if (until == null) {
        try {
          final prefs = await _prefsLoader();
          final stored = prefs.getInt('$key.until');
          if (stored != null) {
            until = DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
            _cooldowns[key] = until;
          }
        } catch (_) {
          // Flutter bindings may not exist in pure unit tests or early startup.
        }
      }
      return until != null && until.isAfter(_clock()) ? until : null;
    });
    if (blocked != null) {
      throw ApiRateLimitException(
        provider: provider,
        model: model,
        retryAt: blocked,
        source: 'cooldown',
      );
    }
  }

  /// Returns the earliest time any of the supplied provider/model pairs can
  /// be tried. Recovery uses this to pause before opening the next old slice.
  Future<DateTime?> earliestAvailable(
    Iterable<({String provider, String model})> candidates,
  ) async {
    DateTime? earliest;
    var candidateCount = 0;
    for (final candidate in candidates) {
      candidateCount++;
      final key = _key(candidate.provider, candidate.model);
      final value = await _serialized(() async {
        var until = _cooldowns[key];
        if (until == null) {
          try {
            final prefs = await _prefsLoader();
            final stored = prefs.getInt('$key.until');
            if (stored != null) {
              until = DateTime.fromMillisecondsSinceEpoch(stored, isUtc: true);
              _cooldowns[key] = until;
            }
          } catch (_) {}
        }
        return until;
      });
      if (value == null || !value.isAfter(_clock())) return null;
      if (earliest == null || value.isBefore(earliest)) {
        earliest = value;
      }
    }
    return candidateCount == 0 ? null : earliest;
  }

  /// Conservative pacing hook for background recovery. Live recording paths
  /// do not call this, so ordinary foreground recognition is unaffected.
  Future<void> waitForRecoveryRequest({
    required String provider,
    required String model,
    Duration minimumInterval = const Duration(milliseconds: 3200),
  }) async {
    final key = _key(provider, model);
    final wait = await _serialized(() async {
      final now = _clock();
      final next = _lastRequest[key]?.add(minimumInterval);
      _lastRequest[key] = (next != null && next.isAfter(now)) ? next : now;
      return next != null && next.isAfter(now)
          ? next.difference(now)
          : Duration.zero;
    });
    if (wait > Duration.zero) await Future<void>.delayed(wait);
  }

  Future<DateTime> register429({
    required String provider,
    required String model,
    Duration? serverDelay,
  }) async {
    return _serialized(() async {
      final key = _key(provider, model);
      final now = _clock();
      SharedPreferences? prefs;
      try {
        prefs = await _prefsLoader();
      } catch (_) {}
      final oldUntil =
          _cooldowns[key] ??
          (prefs?.getInt('$key.until') == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  prefs!.getInt('$key.until')!,
                  isUtc: true,
                ));
      final strike = (_strikes[key] ?? prefs?.getInt('$key.strikes') ?? 0) + 1;
      _strikes[key] = strike;
      final exponential = Duration(
        seconds: (60 * (1 << (strike - 1).clamp(0, 4))).clamp(60, 900),
      );
      final requested = serverDelay ?? exponential;
      final candidate = now.add(
        requested > exponential ? requested : exponential,
      );
      final until = oldUntil != null && oldUntil.isAfter(candidate)
          ? oldUntil
          : candidate;
      _cooldowns[key] = until;
      if (prefs != null) {
        try {
          await prefs.setInt('$key.until', until.millisecondsSinceEpoch);
          await prefs.setInt('$key.strikes', strike);
        } catch (_) {
          // Keep the in-memory cooldown and still propagate the typed 429.
        }
      }
      return until;
    });
  }

  static Duration? parseRetryAfter(String? value, {DateTime? now}) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = num.tryParse(value.trim());
    if (seconds != null &&
        seconds.isFinite &&
        seconds >= 0 &&
        seconds <= 3153600000) {
      return Duration(milliseconds: (seconds * 1000).ceil());
    }
    DateTime? date;
    try {
      date = HttpDate.parse(value.trim());
    } catch (_) {
      date = DateTime.tryParse(value.trim());
    }
    if (date == null) return null;
    final base = (now ?? DateTime.now().toUtc()).toUtc();
    final delay = date.toUtc().difference(base);
    return delay.isNegative ? Duration.zero : delay;
  }

  /// Extracts Google's RetryInfo.retryDelay without logging the response.
  static Duration? parseGeminiRetryDelay(Object? body) {
    if (body is! Map) return null;
    final error = body['error'];
    if (error is! Map || error['details'] is! List) return null;
    for (final detail in error['details'] as List) {
      if (detail is! Map) continue;
      final type = detail['@type']?.toString() ?? '';
      final raw = detail['retryDelay']?.toString();
      if (!type.contains('RetryInfo') || raw == null) continue;
      final match = RegExp(r'^([0-9]+(?:\.[0-9]+)?)s$').firstMatch(raw.trim());
      if (match == null) continue;
      final seconds = double.parse(match.group(1)!);
      if (!seconds.isFinite || seconds < 0 || seconds > 3153600000) continue;
      return Duration(milliseconds: (seconds * 1000).ceil());
    }
    return null;
  }
}
