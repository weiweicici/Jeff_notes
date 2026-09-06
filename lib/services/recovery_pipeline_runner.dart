import 'dart:async';

import 'api_rate_limit_service.dart';

class RecoveryPausedException implements Exception {
  const RecoveryPausedException();
}

class RecoveryPipelineResult {
  final int processed;
  final int failed;
  final List<String> remaining;
  final bool pausedAfterConsecutiveFailures;
  final ApiRateLimitException? rateLimit;
  final bool pausedExternally;

  const RecoveryPipelineResult({
    required this.processed,
    required this.failed,
    required this.remaining,
    required this.pausedAfterConsecutiveFailures,
    this.rateLimit,
    this.pausedExternally = false,
  });
}

/// Runs recoverable audio paths with bounded concurrency and a conservative
/// circuit breaker. A false result means the path must remain pending.
class RecoveryPipelineRunner {
  final int concurrency;
  final int maxConsecutiveFailures;

  const RecoveryPipelineRunner({
    this.concurrency = 2,
    this.maxConsecutiveFailures = 3,
  }) : assert(concurrency > 0),
       assert(maxConsecutiveFailures > 0);

  Future<RecoveryPipelineResult> run(
    List<String> paths, {
    required Future<bool> Function(String path) process,
    required void Function(int processed, int total, int failed) onProgress,
    bool Function()? shouldPause,
  }) async {
    if (paths.isEmpty) {
      return const RecoveryPipelineResult(
        processed: 0,
        failed: 0,
        remaining: <String>[],
        pausedAfterConsecutiveFailures: false,
        pausedExternally: false,
      );
    }

    var nextIndex = 0;
    var processed = 0;
    var failed = 0;
    var consecutiveFailures = 0;
    var paused = false;
    ApiRateLimitException? rateLimit;
    var pausedExternally = false;
    final completedPaths = <String>{};

    Future<void> worker() async {
      while (true) {
        final pauseRequested = shouldPause?.call() ?? false;
        if (paused || nextIndex >= paths.length || pauseRequested) {
          pausedExternally = pausedExternally || pauseRequested;
          paused = paused || pauseRequested;
          return;
        }
        final path = paths[nextIndex++];
        var success = false;
        try {
          success = await process(path);
        } on ApiRateLimitException catch (error) {
          // A rate-limited path was not completed. Stop assigning new work,
          // but let the other in-flight worker settle before returning.
          rateLimit ??= error;
          paused = true;
          return;
        } on RecoveryPausedException {
          // The path was claimed but never started; retain it for the next
          // flight after the foreground recording has finished.
          paused = true;
          pausedExternally = true;
          return;
        } catch (_) {
          success = false;
        }
        processed++;
        completedPaths.add(path);
        if (success) {
          consecutiveFailures = 0;
        } else {
          failed++;
          consecutiveFailures++;
        }
        onProgress(processed, paths.length, failed);
        if (consecutiveFailures >= maxConsecutiveFailures) {
          paused = true;
        }
      }
    }

    final workerCount = paths.length < concurrency ? paths.length : concurrency;
    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => worker()),
    );
    return RecoveryPipelineResult(
      processed: processed,
      failed: failed,
      remaining: paths.where((path) => !completedPaths.contains(path)).toList(),
      pausedAfterConsecutiveFailures:
          paused && !pausedExternally && rateLimit == null,
      rateLimit: rateLimit,
      pausedExternally: pausedExternally,
    );
  }
}
