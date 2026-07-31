import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/edge_tts_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EdgeTtsAuth Sec-MS-GEC Unit Tests', () {
    test('1. Unix Epoch (1970-01-01 00:00:00 UTC) matches 116444736000000000 ticks', () {
      final unixEpoch = DateTime.utc(1970, 1, 1);
      final ticks = EdgeTtsAuth.windowsFileTimeTicks(unixEpoch);
      expect(ticks, 116444736000000000);
    });

    test('2. Known Fixed UTC Time FileTime ticks calculation', () {
      // 2026-01-01 00:00:00 UTC
      final date = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final ticks = EdgeTtsAuth.windowsFileTimeTicks(date);
      // Expected = (1767216000 + 11644473600) * 10,000,000 = 134116992000000000
      expect(ticks, 134116992000000000);
    });

    test('3. Five Minute Window Downward Floor Alignment', () {
      const ticks1 = 134116992000000000;
      final aligned1 = EdgeTtsAuth.alignToFiveMinuteWindow(ticks1);
      expect(aligned1 % 3000000000, 0);

      // Add 2 minutes (120 seconds = 1,200,000,000 ticks)
      final ticks2 = ticks1 + 1200000000;
      final aligned2 = EdgeTtsAuth.alignToFiveMinuteWindow(ticks2);
      expect(aligned2, aligned1);

      // Boundary tests: 1 tick before 5-minute boundary
      final ticks3 = ticks1 + 2999999999;
      final aligned3 = EdgeTtsAuth.alignToFiveMinuteWindow(ticks3);
      expect(aligned3, aligned1);
    });

    test('4. Sec-MS-GEC generates 64-character uppercase hex SHA-256 string', () {
      final date = DateTime.utc(2026, 7, 31, 12, 0, 0);
      final gec = EdgeTtsAuth.generateSecMsGec(utcNow: date);

      expect(gec.length, 64);
      expect(gec, matches(RegExp(r'^[0-9A-F]{64}$')));
    });

    test('5. Sec-MS-GEC result is deterministic for any time in the same 5-minute window', () {
      final t1 = DateTime.utc(2026, 7, 31, 12, 1, 15);
      final t2 = DateTime.utc(2026, 7, 31, 12, 4, 59);

      final gec1 = EdgeTtsAuth.generateSecMsGec(utcNow: t1);
      final gec2 = EdgeTtsAuth.generateSecMsGec(utcNow: t2);

      expect(gec1, gec2);
    });

    test('6. Sec-MS-GEC changes across 5-minute window boundary', () {
      final t1 = DateTime.utc(2026, 7, 31, 12, 4, 59);
      final t2 = DateTime.utc(2026, 7, 31, 12, 5, 01);

      final gec1 = EdgeTtsAuth.generateSecMsGec(utcNow: t1);
      final gec2 = EdgeTtsAuth.generateSecMsGec(utcNow: t2);

      expect(gec1, isNot(equals(gec2)));
    });

    test('7. WebSocket URL contains valid TrustedClientToken and Sec-MS-GEC parameters', () {
      final date = DateTime.utc(2026, 7, 31, 12, 0, 0);
      final url = EdgeTtsAuth.buildWebSocketUrl(utcNow: date);

      expect(url, contains('wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1'));
      expect(url, contains('TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4'));
      expect(url, contains('Sec-MS-GEC='));
      expect(url, contains('Sec-MS-GEC-Version=1-143.0.3650.75'));
    });
  });
}
