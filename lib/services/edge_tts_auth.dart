import 'dart:convert';
import 'package:crypto/crypto.dart';

/// [Phase 4: Edge TTS Compatibility Module]
/// Sec-MS-GEC token computation using exact integer math for Windows FileTime ticks.
class EdgeTtsAuth {
  static const String defaultTrustedClientToken = "6A5AA1D4EAFF4E9FB37E23D68491D6F4";
  static const String defaultSecMsGecVersion = "1-143.0.3650.75";

  /// 1601 to 1970 epoch difference in seconds.
  static const int epochDifferenceSeconds = 11644473600;
  static const int ticksPerSecond = 10000000;
  static const int fiveMinuteWindowTicks = 3000000000; // 300s * 10,000,000

  /// Converts a UTC DateTime to 100-nanosecond Windows FileTime ticks using exact integer math.
  static int windowsFileTimeTicks(DateTime utcNow) {
    final utc = utcNow.toUtc();
    final unixMs = utc.millisecondsSinceEpoch;
    final unixSeconds = unixMs ~/ 1000;
    final remainingMs = unixMs % 1000;

    final fileTimeSeconds = unixSeconds + epochDifferenceSeconds;
    final fileTimeTicks = (fileTimeSeconds * ticksPerSecond) + (remainingMs * 10000);
    return fileTimeTicks;
  }

  /// Downward aligns (floor alignment) FileTime ticks to 5-minute boundaries (3,000,000,000 ticks).
  static int alignToFiveMinuteWindow(int fileTimeTicks) {
    return fileTimeTicks - (fileTimeTicks % fiveMinuteWindowTicks);
  }

  /// Generates the uppercase hex SHA-256 Sec-MS-GEC token.
  static String generateSecMsGec({
    required DateTime utcNow,
    String trustedClientToken = defaultTrustedClientToken,
  }) {
    final ticks = windowsFileTimeTicks(utcNow);
    final aligned = alignToFiveMinuteWindow(ticks);
    final strToHash = "$aligned$trustedClientToken";
    final digest = sha256.convert(utf8.encode(strToHash));
    return digest.toString().toUpperCase();
  }

  /// Builds Edge TTS WebSocket URL with query parameters.
  static String buildWebSocketUrl({
    required DateTime utcNow,
    String trustedClientToken = defaultTrustedClientToken,
    String secMsGecVersion = defaultSecMsGecVersion,
  }) {
    final gec = generateSecMsGec(utcNow: utcNow, trustedClientToken: trustedClientToken);
    return "wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1"
        "?TrustedClientToken=$trustedClientToken"
        "&Sec-MS-GEC=$gec"
        "&Sec-MS-GEC-Version=$secMsGecVersion";
  }
}
