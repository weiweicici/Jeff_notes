import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/recovery_retry_scheduler.dart';

class _FakeTimer implements Timer {
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;

  _FakeTimer(this.delay, this.callback);

  void fire() {
    if (!cancelled) callback();
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

void main() {
  test('fires recovery at the scheduled virtual time', () async {
    final now = DateTime.utc(2026, 8, 30);
    final timers = <_FakeTimer>[];
    var recoveries = 0;
    final scheduler = RecoveryRetryScheduler(
      clock: () => now,
      timerFactory: (delay, callback) =>
          _FakeTimer(delay, callback)..also(timers.add),
      isBusy: () => false,
      recover: () async => recoveries++,
      onError: (_, __) {},
    );

    scheduler.schedule(now.add(const Duration(minutes: 2)));
    expect(timers.single.delay, const Duration(minutes: 2));
    timers.single.fire();
    await Future<void>.delayed(Duration.zero);
    expect(recoveries, 1);
  });

  test('busy recovery is postponed by thirty virtual seconds', () {
    final now = DateTime.utc(2026, 8, 30);
    final timers = <_FakeTimer>[];
    var busy = true;
    var recoveries = 0;
    final scheduler = RecoveryRetryScheduler(
      clock: () => now,
      timerFactory: (delay, callback) =>
          _FakeTimer(delay, callback)..also(timers.add),
      isBusy: () => busy,
      recover: () async => recoveries++,
      onError: (_, __) {},
    );

    scheduler.schedule(now);
    timers[0].fire();
    expect(timers[1].delay, const Duration(seconds: 30));
    busy = false;
    timers[1].fire();
    expect(recoveries, 1);
  });

  test(
    'dispose cancels callback and recover errors are observed once',
    () async {
      final timers = <_FakeTimer>[];
      final errors = <Object>[];
      final scheduler = RecoveryRetryScheduler(
        clock: () => DateTime.utc(2026, 8, 30),
        timerFactory: (delay, callback) =>
            _FakeTimer(delay, callback)..also(timers.add),
        isBusy: () => false,
        recover: () async => throw StateError('boom'),
        onError: (error, _) => errors.add(error),
      );
      scheduler.schedule(DateTime.utc(2026, 8, 30));
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      scheduler.schedule(DateTime.utc(2026, 8, 30));
      scheduler.dispose();
      timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
    },
  );

  test(
    'does not start a second recovery while the first is in flight',
    () async {
      final timers = <_FakeTimer>[];
      final gate = Completer<void>();
      var recoveries = 0;
      final scheduler = RecoveryRetryScheduler(
        clock: () => DateTime.utc(2026, 8, 30),
        timerFactory: (delay, callback) =>
            _FakeTimer(delay, callback)..also(timers.add),
        isBusy: () => false,
        recover: () async {
          recoveries++;
          await gate.future;
        },
        onError: (_, __) {},
      );
      scheduler.schedule(DateTime.utc(2026, 8, 30));
      timers.single.fire();
      await Future<void>.delayed(Duration.zero);
      expect(recoveries, 1);
      scheduler.schedule(DateTime.utc(2026, 8, 30));
      timers.last.fire();
      await Future<void>.delayed(Duration.zero);
      expect(recoveries, 1);
      gate.complete();
      await Future<void>.delayed(Duration.zero);
    },
  );
}

extension on _FakeTimer {
  _FakeTimer also(void Function(_FakeTimer) action) {
    action(this);
    return this;
  }
}
