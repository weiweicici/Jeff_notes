import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class WakelockService {
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/wakelock');

  static Future<void> enable() async {
    try {
      await _channel.invokeMethod('setWakelock', {'enable': true});
      debugPrint('[WakelockService] Screen Wakelock Enabled');
    } catch (e) {
      debugPrint('[WakelockService] Enable Error: $e');
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('setWakelock', {'enable': false});
      debugPrint('[WakelockService] Screen Wakelock Disabled');
    } catch (e) {
      debugPrint('[WakelockService] Disable Error: $e');
    }
  }
}
