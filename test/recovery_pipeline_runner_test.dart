import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/api_rate_limit_service.dart';
import 'package:jeff_notes/services/recovery_pipeline_runner.dart';

void main() {
  test('limits recovery concurrency and reports every settled path', () async {
    var active = 0;
    var peak = 0;
    final progress = <String>[];
    final result = await const RecoveryPipelineRunner(concurrency: 2).run(
      List<String>.generate(6, (index) => 'slice-$index'),
      process: (path) async {
        active++;
        peak = active > peak ? active : peak;
        await Future<void>.delayed(const Duration(milliseconds: 2));
        active--;
        return true;
      },
      onProgress: (processed, total, failed) =>
          progress.add('$processed/$total/$failed'),
    );

    expect(peak, lessThanOrEqualTo(2));
    expect(result.processed, 6);
    expect(result.failed, 0);
    expect(result.remaining, isEmpty);
    expect(progress, hasLength(6));
  });

  test(
    'success resets consecutive failure circuit and keeps failures pending',
    () async {
      final result =
          await const RecoveryPipelineRunner(
            concurrency: 1,
            maxConsecutiveFailures: 3,
          ).run(
            ['a', 'b', 'c', 'd', 'e'],
            process: (path) async {
              return path == 'c' || path == 'e';
            },
            onProgress: (processed, total, failed) {},
          );

      expect(result.processed, 5);
      expect(result.failed, 3);
      // All paths were attempted; failed paths remain in the caller's durable
      // pending map, not in this list of paths that were never started.
      expect(result.remaining, isEmpty);
      expect(result.pausedAfterConsecutiveFailures, isFalse);
    },
  );

  test(
    'three consecutive failures pause without starting remaining paths',
    () async {
      final started = <String>[];
      final gate = Completer<void>();
      final resultFuture =
          const RecoveryPipelineRunner(
            concurrency: 1,
            maxConsecutiveFailures: 3,
          ).run(
            ['a', 'b', 'c', 'd'],
            process: (path) async {
              started.add(path);
              if (path == 'a') await gate.future;
              return false;
            },
            onProgress: (processed, total, failed) {},
          );
      await Future<void>.delayed(const Duration(milliseconds: 1));
      gate.complete();
      final result = await resultFuture;

      expect(started, ['a', 'b', 'c']);
      expect(result.remaining, ['d']);
      expect(result.pausedAfterConsecutiveFailures, isTrue);
    },
  );

  test(
    'pausing waits for both workers and retains failed and unstarted paths',
    () async {
      final gate = Completer<bool>();
      final paths = ['a', 'b', 'c', 'd', 'e', 'f'];
      final pending = paths.toSet();
      final started = <String>[];
      var finished = false;
      final future = const RecoveryPipelineRunner()
          .run(
            paths,
            process: (path) async {
              started.add(path);
              if (path == 'a') {
                final success = await gate.future;
                if (success) pending.remove(path);
                return success;
              }
              if (path == 'c') throw StateError('transport failed');
              return false;
            },
            onProgress: (processed, total, failed) {},
          )
          .then((result) {
            finished = true;
            return result;
          });

      await Future<void>.delayed(Duration.zero);
      expect(started, ['a', 'b', 'c', 'd']);
      expect(finished, isFalse);
      gate.complete(true);
      final result = await future;

      expect(result.processed, 4);
      expect(result.failed, 3);
      expect(result.pausedAfterConsecutiveFailures, isTrue);
      expect(result.remaining, ['e', 'f']);
      expect(pending, {'b', 'c', 'd', 'e', 'f'});
      expect(started, ['a', 'b', 'c', 'd']);
    },
  );

  test(
    'rate limit pauses assignment and waits for the other worker to settle',
    () async {
      final otherWorkerGate = Completer<void>();
      final started = <String>[];
      var otherWorkerSettled = false;
      final retryAt = DateTime.now().toUtc().add(const Duration(minutes: 2));

      final resultFuture = const RecoveryPipelineRunner(concurrency: 2).run(
        ['limited', 'in-flight', 'never-started'],
        process: (path) async {
          started.add(path);
          if (path == 'limited') {
            throw ApiRateLimitException(
              provider: 'groq',
              model: 'whisper-large-v3',
              retryAt: retryAt,
            );
          }
          await otherWorkerGate.future;
          otherWorkerSettled = true;
          return true;
        },
        onProgress: (_, __, ___) {},
      );

      await Future<void>.delayed(Duration.zero);
      // The runner cannot complete until the in-flight worker is released.
      expect(otherWorkerSettled, isFalse);
      otherWorkerGate.complete();
      final result = await resultFuture;
      // This assertion documents that no third path was assigned.
      expect(started, ['limited', 'in-flight']);
      expect(result.rateLimit?.retryAt, retryAt);
      expect(result.remaining, ['limited', 'never-started']);
    },
  );
  test(
    'external pause retains unstarted paths without counting failures',
    () async {
      var pause = false;
      final started = <String>[];
      final result = await const RecoveryPipelineRunner(concurrency: 1).run(
        ['a', 'b'],
        process: (path) async {
          started.add(path);
          pause = true;
          return true;
        },
        onProgress: (_, __, ___) {},
        shouldPause: () => pause,
      );
      expect(started, ['a']);
      expect(result.remaining, ['b']);
      expect(result.failed, 0);
      expect(result.pausedExternally, isTrue);
      expect(result.pausedAfterConsecutiveFailures, isFalse);
    },
  );
  test(
    'pause raised during pacing is external and keeps claimed path pending',
    () async {
      final result = await const RecoveryPipelineRunner(concurrency: 1).run(
        ['paced', 'later'],
        process: (_) async => throw const RecoveryPausedException(),
        onProgress: (_, __, ___) {},
      );
      expect(result.pausedExternally, isTrue);
      expect(result.pausedAfterConsecutiveFailures, isFalse);
      expect(result.remaining, ['paced', 'later']);
    },
  );
}
