import 'dart:async';
import 'package:flutter/foundation.dart';

/// [Architect: Concurrency & Resilience]
/// 高并发调度器：支持空闲状态感知
class ApiScheduler {
  static final ApiScheduler _instance = ApiScheduler._internal();
  factory ApiScheduler() => _instance;
  ApiScheduler._internal();

  static const int maxConcurrentRequests = 4;
  int _activeRequests = 0;
  final List<Completer<void>> _waitingQueue = [];
  
  // 用于追踪所有任务完成的 Completer
  Completer<void>? _idleCompleter;

  Future<T> enqueue<T>(Future<T> Function() task, {int priority = 1}) async {
    if (_activeRequests >= maxConcurrentRequests) {
      final completer = Completer<void>();
      _waitingQueue.add(completer);
      await completer.future.timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          _waitingQueue.remove(completer);
        }
      );
    }

    _activeRequests++;
    // 如果当前正在等待空闲，且这是新任务，则需要重置 idleCompleter
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
      if (_waitingQueue.isNotEmpty) {
        _waitingQueue.removeAt(0).complete();
      } else if (_activeRequests == 0) {
        // [Architect] 所有任务清空，触发空闲信号
        _idleCompleter?.complete();
      }
    }
  }

  /// [Architect: Critical for Export]
  /// 等待所有任务完成
  Future<void> untilIdle() async {
    if (_activeRequests == 0 && _waitingQueue.isEmpty) return;
    _idleCompleter ??= Completer<void>();
    return _idleCompleter!.future;
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
