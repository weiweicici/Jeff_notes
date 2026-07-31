import 'dart:async';
import 'package:flutter/foundation.dart';

class _WaitingTask {
  final Completer<void> completer;
  final int priority;
  final String? sessionId;
  _WaitingTask(this.completer, this.priority, {this.sessionId});
}

/// [Architect: Concurrency & Resilience & Session Isolation]
/// 高并发调度器：支持 Session 状态机 (active -> sealed -> draining -> completed)
class ApiScheduler {
  static final ApiScheduler _instance = ApiScheduler._internal();
  factory ApiScheduler() => _instance;
  ApiScheduler._internal();

  static const int maxConcurrentRequests = 4;
  int _activeRequests = 0;
  final List<_WaitingTask> _waitingQueue = [];

  Completer<void>? _idleCompleter;

  // [Phase 3 Fix 1 & 9] Session 状态机与队列即时追踪
  final Set<String> _sealedSessions = {};
  final Map<String, int> _sessionQueuedCount = {};
  final Map<String, Set<Future<void>>> _sessionFutures = {};
  final Map<String, int> _activeCountBySession = {};
  final Map<String, Completer<void>> _sessionIdleCompleters = {};

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
    if (_activeRequests >= maxConcurrentRequests) {
      final completer = Completer<void>();
      final insertIndex = _waitingQueue.indexWhere(
        (t) => t.priority > priority,
      );
      final waitingTask = _WaitingTask(
        completer,
        priority,
        sessionId: sessionId,
      );
      if (insertIndex == -1) {
        _waitingQueue.add(waitingTask);
      } else {
        _waitingQueue.insert(insertIndex, waitingTask);
      }

      try {
        await completer.future.timeout(const Duration(seconds: 90));
      } on TimeoutException {
        _waitingQueue.removeWhere((t) => t.completer == completer);
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

    final rawFuture = _executeWithRetry(task).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw TimeoutException("Execution Timeout"),
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

      if (_waitingQueue.isNotEmpty) {
        _waitingQueue.removeAt(0).completer.complete();
      } else if (_activeRequests == 0) {
        _idleCompleter?.complete();
      }
    }
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

  Future<T> _executeWithRetry<T>(Future<T> Function() task) async {
    int attempt = 0;
    const int maxAttempts = 3;
    while (true) {
      try {
        return await task();
      } catch (e) {
        attempt++;
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains("429") ||
            errorStr.contains("too many requests")) {
          if (attempt >= maxAttempts) rethrow;
          final waitTime = 10 * attempt;
          debugPrint("Rate limit hit, waiting ${waitTime}s before retry...");
          await Future.delayed(Duration(seconds: waitTime));
          continue;
        }
        if (errorStr.contains("500") || errorStr.contains("503")) {
          if (attempt >= maxAttempts) rethrow;
          await Future.delayed(Duration(seconds: 2 * attempt));
          continue;
        }
        rethrow;
      }
    }
  }
}
