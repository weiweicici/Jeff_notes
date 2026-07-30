import 'dart:async';
import 'package:flutter/foundation.dart';

class _WaitingTask {
  final Completer<void> completer;
  final int priority;
  _WaitingTask(this.completer, this.priority);
}

/// [Architect: Concurrency & Resilience]
/// 高并发调度器：支持空闲状态感知
class ApiScheduler {
  static final ApiScheduler _instance = ApiScheduler._internal();
  factory ApiScheduler() => _instance;
  ApiScheduler._internal();

  static const int maxConcurrentRequests = 4;
  int _activeRequests = 0;
  final List<_WaitingTask> _waitingQueue = [];
  
  // 用于追踪所有任务完成的 Completer
  Completer<void>? _idleCompleter;

  // [Architect: Session Isolation] 追踪每个会话的活动请求数
  final Map<String, int> _activeCountBySession = {};
  final Map<String, Completer<void>> _sessionIdleCompleters = {};

  Future<T> enqueue<T>(Future<T> Function() task, {int priority = 1, String? sessionId}) async {
    bool isExpired = false;
    if (_activeRequests >= maxConcurrentRequests) {
      final completer = Completer<void>();
      // 按优先级插入（priority 越小越靠前）
      final insertIndex = _waitingQueue.indexWhere((t) => t.priority > priority);
      if (insertIndex == -1) {
        _waitingQueue.add(_WaitingTask(completer, priority));
      } else {
        _waitingQueue.insert(insertIndex, _WaitingTask(completer, priority));
      }

      try {
        await completer.future.timeout(const Duration(seconds: 90));
      } on TimeoutException {
        _waitingQueue.removeWhere((t) => t.completer == completer);
        isExpired = true;
      }
    }

    if (isExpired) {
      throw TimeoutException("Task expired in scheduler queue after 90s");
    }

    _activeRequests++;
    if (sessionId != null) {
      _activeCountBySession[sessionId] = (_activeCountBySession[sessionId] ?? 0) + 1;
      // 重置该 session 的 idle completer
      _sessionIdleCompleters.remove(sessionId);
    }

    // 如果当前 idleCompleter 已经完成（上次 session 遗留），重置它以便本次任务能正确等待
    if (_idleCompleter != null && _idleCompleter!.isCompleted) {
      _idleCompleter = null;
    }

    try {
      return await _executeWithRetry(task).timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException("Execution Timeout")
      );
    } finally {
      _activeRequests--;
      
      if (sessionId != null) {
        final count = (_activeCountBySession[sessionId] ?? 1) - 1;
        if (count <= 0) {
          _activeCountBySession.remove(sessionId);
          // complete() 后立即从 Map 中移除，防止 Map 无限增长（跨 session 积累）
          _sessionIdleCompleters[sessionId]?.complete();
          _sessionIdleCompleters.remove(sessionId);
        } else {
          _activeCountBySession[sessionId] = count;
        }
      }

      if (_waitingQueue.isNotEmpty) {
        _waitingQueue.removeAt(0).completer.complete();
      } else if (_activeRequests == 0) {
        // [Architect] 所有任务清空，触发全局空闲信号
        _idleCompleter?.complete();
      }
    }
  }

  /// [Architect: Session-Aware Sync]
  /// 只等待特定会话的任务完成
  Future<void> untilSessionIdle(String sessionId) async {
    if ((_activeCountBySession[sessionId] ?? 0) == 0) return;
    _sessionIdleCompleters[sessionId] ??= Completer<void>();
    return _sessionIdleCompleters[sessionId]!.future;
  }

  /// [Architect: Critical for Export]
  /// 等待所有任务完成（全局）
  Future<void> untilIdle() async {
    if (_activeRequests == 0 && _waitingQueue.isEmpty) return;
    // [BUG-01 Fix] 如果上次 session 遗留了已完成的 Completer，必须先重置，
    // 否则 ??= 会复用它，导致 await 立即返回而跳过真正的等待。
    if (_idleCompleter != null && _idleCompleter!.isCompleted) {
      _idleCompleter = null;
    }
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future.timeout(const Duration(seconds: 120), onTimeout: () {});
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
        if (errorStr.contains("429") || errorStr.contains("too many requests")) {
          if (attempt >= maxAttempts) rethrow;
          // [Architect: Aggressive Back-off] 对于 429 错误，大幅拉长等待时间
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
