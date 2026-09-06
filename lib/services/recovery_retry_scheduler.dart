import 'dart:async';

typedef RecoveryTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// Schedules one recovery flight after a provider cooldown without retaining
/// a microphone lease while sleeping. All timing and side effects are
/// injectable so cooldown behavior can be tested without waiting in realtime.
class RecoveryRetryScheduler {
  final DateTime Function() clock;
  final RecoveryTimerFactory timerFactory;
  final bool Function() isBusy;
  final Future<void> Function() recover;
  final void Function(Object error, StackTrace stackTrace) onError;
  final Duration busyRetryDelay;

  Timer? _timer;
  bool _disposed = false;
  bool _recovering = false;

  RecoveryRetryScheduler({
    required this.clock,
    required this.timerFactory,
    required this.isBusy,
    required this.recover,
    required this.onError,
    this.busyRetryDelay = const Duration(seconds: 30),
  });

  void schedule(DateTime retryAt) {
    if (_disposed) return;
    _timer?.cancel();
    final delay = retryAt.difference(clock());
    _timer = timerFactory(delay.isNegative ? Duration.zero : delay, _fire);
  }

  void _fire() {
    _timer = null;
    if (_disposed) return;
    if (isBusy() || _recovering) {
      schedule(clock().add(busyRetryDelay));
      return;
    }
    _recovering = true;
    unawaited(
      recover().catchError(onError).whenComplete(() {
        _recovering = false;
      }),
    );
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  /// Cancels only the pending wakeup while keeping the scheduler reusable.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
