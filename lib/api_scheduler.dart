import 'dart:async';
import 'package:flutter/foundation.dart';
import 'services/api_rate_limit_service.dart';

class _WaitingTask {
  final Completer<void> completer;
  final int priority;
  final String? sessionId;
  final ApiTaskLane lane;
  _WaitingTask(
    this.completer,
    this.priority, {
    this.sessionId,
    this.lane = ApiTaskLane.general,
  });
}

/// Independent lanes prevent slow translation work from consuming the
/// capacity needed by five-second speech-to-text slices.
enum ApiTaskLane { general, realtime, translation }

/// [Architect: Concurrency & Resilience & Session Isolation]
/// 高并发调度器：支持 Session 状态机 (active -> sealed -> draining -> completed)
class ApiScheduler {
  static final ApiScheduler _instance = ApiScheduler._internal();
  factory ApiScheduler() => _instance;
  ApiScheduler._internal();

  static const int maxConcurrentRequests = 4;
  int _activeRequests = 0;
  final List<_WaitingTask> _waitingQueue = [];
  final Map<ApiTaskLane, int> _laneActiveRequests = {
    ApiTaskLane.realtime: 0,
    ApiTaskLane.translation: 0,
  };
  final Map<ApiTaskLane, List<_WaitingTask>> _laneWaitingQueues = {
    ApiTaskLane.realtime: [],
    ApiTaskLane.translation: [],
  };
  static const int _laneConcurrentRequests = 2;
  bool _lastGrantedRealtime = false;

  Completer<void>? _idleCompleter;

  // [Phase 3 Fix 1 & 9] Session 状态机与队列即时追踪
  final Set<String> _sealedSessions = {};
  final Map<String, int> _sessionQueuedCount = {};
  final Map<String, Set<Future<void>>> _sessionFutures = {};
  final Map<String, int> _activeCountBySession = {};
  final Map<String, Completer<void>> _sessionIdleCompleters = {};

  @visibleForTesting
  int get activeRequestCount => _activeRequests;

  @visibleForTesting
  int activeRequestCountForSession(String sessionId) =>
      _activeCountBySession[sessionId] ?? 0;

  /// 封锁 Session：防止新任务在 handover 后被误注入
  void sealSession(String sessionId) {
    _sealedSessions.add(sessionId);
  }

  /// 取消并强制清理 Session 跟踪状态（仅在 Socket 终结或会话彻底结束时调用）
  void cancelSession(String sessionId) {
    _sealedSessions.remove(sessionId);
    _sessionQueuedCount.remove(sessionId);
    _sessionFutures.remove(sessionId);
    _activeCountBySession.remove(sessionId);
    _sessionIdleCompleters[sessionId]?.complete();
    _sessionIdleCompleters.remove(sessionId);
  }

  Future<T> enqueue<T>(
    Future<T> Function() task, {
    int priority = 1,
    String? sessionId,
    ApiTaskLane lane = ApiTaskLane.general,
    int maxAttempts = 3,
    Duration retryBaseDelay = const Duration(seconds: 10),
  }) async {
    // [FIX 9] 拒绝在 sealed 会话上添加新任务
    if (sessionId != null && _sealedSessions.contains(sessionId)) {
      throw StateError(
        "Session $sessionId is sealed. Cannot enqueue new tasks.",
      );
    }

    // [FIX 1] 从 enqueue 第一行起（等待队列前）即刻登记排队计数
    if (sessionId != null) {
      _sessionQueuedCount[sessionId] =
          (_sessionQueuedCount[sessionId] ?? 0) + 1;
    }

    bool isExpired = false;
    final laneQueue = _laneWaitingQueues[lane];
    final realtimeActive = _laneActiveRequests[ApiTaskLane.realtime] ?? 0;
    final nonRealtimeActive = _activeRequests - realtimeActive;
    final laneIsFull = lane == ApiTaskLane.realtime
        ? realtimeActive >= _laneConcurrentRequests
        : nonRealtimeActive >= _laneConcurrentRequests;
    if (laneIsFull || _activeRequests >= maxConcurrentRequests) {
      final completer = Completer<void>();
      final waitingTask = _WaitingTask(
        completer,
        priority,
        sessionId: sessionId,
        lane: lane,
      );
      final queue = lane == ApiTaskLane.general ? _waitingQueue : laneQueue!;
      final insertIndex = queue.indexWhere((t) => t.priority > priority);
      if (insertIndex == -1) {
        queue.add(waitingTask);
      } else {
        queue.insert(insertIndex, waitingTask);
      }

      try {
        await completer.future.timeout(const Duration(seconds: 90));
      } on TimeoutException {
        queue.removeWhere((t) => t.completer == completer);
        isExpired = true;
      }
    }

    // 从排队计数扣除，转入运行状态
    if (sessionId != null) {
      final currentQueued = (_sessionQueuedCount[sessionId] ?? 1) - 1;
      if (currentQueued <= 0) {
        _sessionQueuedCount.remove(sessionId);
      } else {
        _sessionQueuedCount[sessionId] = currentQueued;
      }
    }

    if (isExpired) {
      throw TimeoutException("Task expired in scheduler queue after 90s");
    }

    _activeRequests++;
    if (lane != ApiTaskLane.general) {
      _laneActiveRequests[lane] = (_laneActiveRequests[lane] ?? 0) + 1;
    }
    _lastGrantedRealtime = lane == ApiTaskLane.realtime;
    if (sessionId != null) {
      _activeCountBySession[sessionId] =
          (_activeCountBySession[sessionId] ?? 0) + 1;
      _sessionIdleCompleters.remove(sessionId);
    }

    if (_idleCompleter != null && _idleCompleter!.isCompleted) {
      _idleCompleter = null;
    }

    final innerCompleter = Completer<T>();
    late Future<void> trackedFuture;

    void removeTracked() {
      if (sessionId != null) {
        _sessionFutures[sessionId]?.remove(trackedFuture);
        if (_sessionFutures[sessionId]?.isEmpty ?? false) {
          _sessionFutures.remove(sessionId);
        }
      }
    }

    // Do not put a second, detached timeout around [task].  Future.timeout
    // only stops waiting; it does not cancel the underlying socket request.
    // Releasing this slot at 60 seconds used to make the counters say idle
    // while the HTTP request was still in flight.  Network callers own an
    // abortable timeout, so this future now represents the real request.
    final rawFuture = _executeWithRetry(
      task,
      maxAttempts: maxAttempts,
      retryBaseDelay: retryBaseDelay,
    );

    trackedFuture = rawFuture.then(
      (v) {
        if (!innerCompleter.isCompleted) innerCompleter.complete(v);
      },
      onError: (Object e, StackTrace st) {
        if (!innerCompleter.isCompleted) innerCompleter.completeError(e, st);
      },
    );

    if (sessionId != null) {
      _sessionFutures.putIfAbsent(sessionId, () => {}).add(trackedFuture);
    }

    try {
      return await innerCompleter.future;
    } finally {
      _activeRequests--;
      if (lane != ApiTaskLane.general) {
        _laneActiveRequests[lane] = (_laneActiveRequests[lane] ?? 1) - 1;
      }

      if (sessionId != null) {
        removeTracked();

        final count = (_activeCountBySession[sessionId] ?? 1) - 1;
        if (count <= 0) {
          _activeCountBySession.remove(sessionId);
          _sessionIdleCompleters[sessionId]?.complete();
          _sessionIdleCompleters.remove(sessionId);
        } else {
          _activeCountBySession[sessionId] = count;
        }
      }

      _wakeNextWaiting();
      if (_activeRequests == 0 &&
          _waitingQueue.isEmpty &&
          _laneWaitingQueues.values.every((queue) => queue.isEmpty)) {
        _idleCompleter?.complete();
      }
    }
  }

  void _wakeNextWaiting() {
    if (_activeRequests >= maxConcurrentRequests) return;
    final realtimeActive = _laneActiveRequests[ApiTaskLane.realtime] ?? 0;
    final nonRealtimeActive = _activeRequests - realtimeActive;
    final realtimeQueue = _laneWaitingQueues[ApiTaskLane.realtime]!;
    final translationQueue = _laneWaitingQueues[ApiTaskLane.translation]!;
    final hasRealtime = realtimeQueue.isNotEmpty && realtimeActive < 2;
    final hasNonRealtime =
        (translationQueue.isNotEmpty || _waitingQueue.isNotEmpty) &&
        nonRealtimeActive < 2;

    ApiTaskLane? selected;
    if (hasRealtime && hasNonRealtime) {
      selected = _lastGrantedRealtime
          ? (_waitingQueue.isNotEmpty
                ? ApiTaskLane.general
                : ApiTaskLane.translation)
          : ApiTaskLane.realtime;
    } else if (hasRealtime) {
      selected = ApiTaskLane.realtime;
    } else if (hasNonRealtime) {
      if (_waitingQueue.isEmpty) {
        selected = ApiTaskLane.translation;
      } else if (translationQueue.isEmpty) {
        selected = ApiTaskLane.general;
      } else {
        selected =
            _waitingQueue.first.priority <= translationQueue.first.priority
            ? ApiTaskLane.general
            : ApiTaskLane.translation;
      }
    }
    if (selected == null) return;
    final queue = selected == ApiTaskLane.general
        ? _waitingQueue
        : _laneWaitingQueues[selected]!;
    queue.removeAt(0).completer.complete();
  }

  /// [Phase 3 Fix 8 & 9: Closed-Loop Session Drain]
  /// 闭环等待指定 session 的所有排队任务、活跃 Future 与派生任务全部归零。
  /// drain() 会先 sealSession()，防止新任务入队。
  /// 若超时，抛出 TimeoutException，保留 session 状态（供上层关闭 Client 终止连接）。
  Future<void> drain(
    String sessionId, {
    Duration timeout = const Duration(seconds: 90),
  }) async {
    sealSession(sessionId);
    final stopwatch = Stopwatch()..start();

    while (true) {
      final futures = _sessionFutures[sessionId];
      final queued = _sessionQueuedCount[sessionId] ?? 0;

      // 排队与活跃任务全部归零，判定为真正 quiescence
      if ((futures == null || futures.isEmpty) && queued == 0) {
        return;
      }

      final remaining = timeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException(
          'Session $sessionId drain timed out after ${timeout.inSeconds}s',
        );
      }

      if (futures != null && futures.isNotEmpty) {
        final snapshot = futures
            .map(
              (future) => future.catchError((Object _) {
                // The enqueue caller owns task errors. drain only waits for
                // settlement and must not turn a handled API failure into a
                // false session-finalization failure.
              }),
            )
            .toList();
        try {
          await Future.wait(snapshot, eagerError: false).timeout(remaining);
        } on TimeoutException {
          throw TimeoutException(
            'Session $sessionId drain timed out during in-flight requests',
          );
        }
      } else {
        // 如果只有排队任务在等并发槽，短暂停顿等待排队任务被拉入运行
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// [Session-Aware Sync] 等待特定会话的任务完成（委托给 drain）
  Future<void> untilSessionIdle(String sessionId) => drain(sessionId);

  /// [Critical for Export] 等待所有任务完成（全局）
  Future<void> untilIdle() async {
    if (_activeRequests == 0 && _waitingQueue.isEmpty) return;
    if (_idleCompleter != null && _idleCompleter!.isCompleted) {
      _idleCompleter = null;
    }
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future.timeout(
      const Duration(seconds: 120),
      onTimeout: () {},
    );
  }

  Future<T> _executeWithRetry<T>(
    Future<T> Function() task, {
    int maxAttempts = 3,
    Duration retryBaseDelay = const Duration(seconds: 10),
  }) async {
    int attempt = 0;
    if (maxAttempts < 1) {
      throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be >= 1');
    }
    while (true) {
      try {
        return await task();
      } catch (e) {
        attempt++;
        // Provider cooldown is persisted and owned by the provider service.
        // Release this scheduler slot immediately; retrying here would only
        // create another request during the shared cooldown window.
        if (e is ApiRateLimitException) rethrow;
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains("429") ||
            errorStr.contains("too many requests")) {
          if (attempt >= maxAttempts) rethrow;
          final waitTime = retryBaseDelay * attempt;
          debugPrint(
            "Rate limit hit, waiting ${waitTime.inMilliseconds}ms before retry...",
          );
          await Future.delayed(waitTime);
          continue;
        }
        if (errorStr.contains("500") || errorStr.contains("503")) {
          if (attempt >= maxAttempts) rethrow;
          await Future.delayed(retryBaseDelay * attempt);
          continue;
        }
        rethrow;
      }
    }
  }
}
