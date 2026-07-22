import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class LiveActivityService {
  static const _channel = MethodChannel('com.zhenfeng.jeffnotes/liveactivity');

  static Future<bool> start({
    required String activeSentence,
    required String nextSentence,
    required int currentIndex,
    required int totalCount,
    required String docTitle,
    bool isPlaying = true,
  }) async {
    try {
      await _channel.invokeMethod('startActivity', {
        'activeSentence': activeSentence,
        'nextSentence': nextSentence,
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'docTitle': docTitle,
        'isPlaying': isPlaying,
      });
      return true;
    } catch (e) {
      debugPrint('[LiveActivity] start failed: $e');
      return false;
    }
  }

  static Future<bool> update({
    required String activeSentence,
    required String nextSentence,
    required int currentIndex,
    required int totalCount,
    required String docTitle,
    bool isPlaying = true,
  }) async {
    try {
      await _channel.invokeMethod('updateActivity', {
        'activeSentence': activeSentence,
        'nextSentence': nextSentence,
        'currentIndex': currentIndex,
        'totalCount': totalCount,
        'docTitle': docTitle,
        'isPlaying': isPlaying,
      });
      return true;
    } catch (e) {
      debugPrint('[LiveActivity] update failed: $e');
      return false;
    }
  }

  static Future<void> end() async {
    try {
      await _channel.invokeMethod('endActivity');
    } catch (e) {
      debugPrint('[LiveActivity] end failed: $e');
    }
  }
}
