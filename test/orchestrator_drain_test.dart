import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/api_scheduler.dart';

/// [Phase 3] Tests for ApiScheduler.drain() and session isolation.
void main() {
  // Use a fresh scheduler instance per test to avoid cross-test state pollution.
  // We can't reset the singleton, so we test the public API contracts directly.

  group('ApiScheduler.drain() — Phase 3 Session Drain', () {
    test(
      '1. drain() returns immediately when no tasks are registered for sessionId',
      () async {
        final s = ApiScheduler();
        // Session 'unknown_session' was never used — drain should return instantly.
        final stopwatch = Stopwatch()..start();
        await s.drain('unknown_session', timeout: const Duration(seconds: 2));
        stopwatch.stop();
        // Should complete well under 200ms (no tasks to wait for)
        expect(stopwatch.elapsedMilliseconds, lessThan(500));
      },
    );

    test(
      '2. drain(sessionId) waits for all enqueued tasks for that session',
      () async {
        final s = ApiScheduler();
        const sid = 'drain_wait_test_session';
        final taskDoneCompleter = Completer<void>();

        // Enqueue a task that completes after a short delay
        final enqueueFuture = s.enqueue<String>(() async {
          await Future.delayed(const Duration(milliseconds: 100));
          return 'done';
        }, sessionId: sid);

        // drain() should wait until the task finishes
        final stopwatch = Stopwatch()..start();
        await s.drain(sid, timeout: const Duration(seconds: 5));
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(80));

        // Task should also have completed by now
        final result = await enqueueFuture;
        expect(result, 'done');
        if (!taskDoneCompleter.isCompleted) taskDoneCompleter.complete();
      },
    );

    test(
      '3. drain(sessionA) does not affect tasks running under sessionB',
      () async {
        final s = ApiScheduler();
        const sidA = 'session_a_drain_isolation';
        const sidB = 'session_b_drain_isolation';

        var bCompleted = false;

        // Enqueue a short task for A
        final futureA = s.enqueue<String>(() async {
          await Future.delayed(const Duration(milliseconds: 50));
          return 'A done';
        }, sessionId: sidA);

        // Enqueue a longer task for B
        final futureB = s.enqueue<String>(() async {
          await Future.delayed(const Duration(milliseconds: 200));
          bCompleted = true;
          return 'B done';
        }, sessionId: sidB);

        // Drain A — should not wait for B
        final stopwatch = Stopwatch()..start();
        await s.drain(sidA, timeout: const Duration(seconds: 5));
        stopwatch.stop();

        // A should be done
        final resultA = await futureA;
        expect(resultA, 'A done');

        // B should not be done yet (it needs 200ms, we only waited for A ~50ms)
        // Note: B might or might not be done depending on timing, but drain(A) should return fast.
        expect(stopwatch.elapsedMilliseconds, lessThan(180));

        // Ensure B eventually completes
        await futureB;
        expect(bCompleted, isTrue);
      },
    );

    test(
      '4. After drain() returns, sessionFutures for that session are cleared',
      () async {
        final s = ApiScheduler();
        const sid = 'drain_cleanup_test';

        await s.enqueue<int>(() async => 42, sessionId: sid);

        // First drain completes the session
        await s.drain(sid);

        // Second drain should return immediately (nothing registered)
        final stopwatch = Stopwatch()..start();
        await s.drain(sid, timeout: const Duration(seconds: 1));
        stopwatch.stop();

        expect(stopwatch.elapsedMilliseconds, lessThan(200));
      },
    );

    test('5. Multiple tasks in same session — drain waits for all', () async {
      final s = ApiScheduler();
      const sid = 'multi_task_drain_test';
      final results = <int>[];

      final futures = [
        s.enqueue<int>(() async {
          await Future.delayed(const Duration(milliseconds: 30));
          results.add(1);
          return 1;
        }, sessionId: sid),
        s.enqueue<int>(() async {
          await Future.delayed(const Duration(milliseconds: 60));
          results.add(2);
          return 2;
        }, sessionId: sid),
        s.enqueue<int>(() async {
          await Future.delayed(const Duration(milliseconds: 20));
          results.add(3);
          return 3;
        }, sessionId: sid),
      ];

      await s.drain(sid, timeout: const Duration(seconds: 10));

      // All tasks should be complete after drain
      for (final f in futures) await f;
      expect(results.length, 3);
      expect(results, containsAll([1, 2, 3]));
    });

    test(
      '6. drain keeps a completed session sealed against late work',
      () async {
        final scheduler = ApiScheduler();
        const sessionId = 'late_enqueue_rejected';
        await scheduler.drain(sessionId);

        await expectLater(
          scheduler.enqueue<void>(() async {}, sessionId: sessionId),
          throwsStateError,
        );
        scheduler.cancelSession(sessionId);
      },
    );
  });

  group('ApiScheduler — backwards compatibility', () {
    test('7. untilIdle() still works when no tasks are active', () async {
      final s = ApiScheduler();
      // Should return immediately
      await s.untilIdle();
    });

    test(
      '8. enqueue() without sessionId still works (no session tracking)',
      () async {
        final s = ApiScheduler();
        final result = await s.enqueue<String>(
          () async => 'no_session_result',
          // no sessionId
        );
        expect(result, 'no_session_result');
      },
    );
  });
}
