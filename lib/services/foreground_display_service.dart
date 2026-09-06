import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Keeps the screen awake while Jeff Notes is the active foreground app.
///
/// Screen brightness remains fully controlled by iOS and the user.
class ForegroundDisplayService {
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/wakelock');
  static bool? _lastRequestedState;

  static Future<void> setActive(bool active) async {
    if (_lastRequestedState == active) return;
    _lastRequestedState = active;

    try {
      await _channel.invokeMethod('setForegroundDisplayMode', {
        'enable': active,
      });
      debugPrint(
        '[ForegroundDisplayService] ${active ? 'Enabled' : 'Released'}',
      );
    } catch (error) {
      // Allow the next lifecycle event to retry if the platform call failed.
      _lastRequestedState = null;
      debugPrint('[ForegroundDisplayService] Error: $error');
    }
  }
}
