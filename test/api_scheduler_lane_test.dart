import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/api_scheduler.dart';

void main() {
  test('realtime lane starts while translation lane is saturated', () async {
    final scheduler = ApiScheduler();
    final releaseTranslation = Completer<void>();
    final started = <String>[];

    final translation1 = scheduler.enqueue<void>(
      () async {
        started.add('translation-1');
        await releaseTranslation.future;
      },
      lane: ApiTaskLane.translation,
      sessionId: 'lane-test-1',
    );
    final translation2 = scheduler.enqueue<void>(
      () async {
        started.add('translation-2');
        await releaseTranslation.future;
      },
      lane: ApiTaskLane.translation,
      sessionId: 'lane-test-1',
    );

    // Let both translation tasks enter their independent lane.
    await Future<void>.delayed(Duration.zero);
    final realtime = scheduler.enqueue<void>(
      () async {
        started.add('realtime');
      },
      lane: ApiTaskLane.realtime,
      sessionId: 'lane-test-1',
    );

    await realtime;
    expect(started, contains('realtime'));

    releaseTranslation.complete();
    await Future.wait([translation1, translation2]);
    await scheduler.drain('lane-test-1');
  });

  test(
    'lane scheduler never exceeds four total requests and wakes both classes',
    () async {
      final scheduler = ApiScheduler();
      final releases = List.generate(4, (_) => Completer<void>());
      var active = 0;
      var peak = 0;
      Future<void> hold(int index, ApiTaskLane lane) => scheduler.enqueue<void>(
        () async {
          active++;
          if (active > peak) peak = active;
          await releases[index].future;
          active--;
        },
        lane: lane,
        sessionId: 'lane-test-2',
      );

      final first = [
        hold(0, ApiTaskLane.translation),
        hold(1, ApiTaskLane.general),
        hold(2, ApiTaskLane.realtime),
        hold(3, ApiTaskLane.realtime),
      ];
      await Future<void>.delayed(Duration.zero);
      expect(peak, 4);

      // A queued non-realtime task must run after a slot opens, even with
      // realtime work waiting, proving class-level fairness.
      var generalStarted = false;
      final queuedGeneral = scheduler.enqueue<void>(
        () async {
          generalStarted = true;
        },
        lane: ApiTaskLane.general,
        sessionId: 'lane-test-2',
      );
      releases[0].complete();
      await queuedGeneral;
      expect(generalStarted, isTrue);
      for (final release in releases.skip(1)) {
        release.complete();
      }
      await Future.wait(first);
      await scheduler.drain('lane-test-2');
    },
  );
}
