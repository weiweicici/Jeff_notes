import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps Jeff Notes readable while it is the active foreground app.
///
/// The native side saves and restores the user's previous screen brightness.
class ForegroundDisplayService {
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/wakelock');
  static bool? _lastRequestedState;

  static Future<void> setActive(bool active) async {
    if (_lastRequestedState == active) return;
    _lastRequestedState = active;

    try {
      await _channel.invokeMethod('setForegroundDisplayMode', {
        'enable': active,
        'brightness': 0.05,
      });
      debugPrint(
        '[ForegroundDisplayService] ${active ? 'Enabled at 5%' : 'Released'}',
      );
    } catch (error) {
      // Allow the next lifecycle event to retry if the platform call failed.
      _lastRequestedState = null;
      debugPrint('[ForegroundDisplayService] Error: $error');
    }
  }
}
