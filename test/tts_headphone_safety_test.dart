import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/route_detector.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RouteDetector Unit Tests', () {
    test(
      '1. FakeRouteDetector returns allowed bluetoothA2dp decision as safe',
      () async {
        final detector = FakeRouteDetector(
          const AudioRouteDecision(
            isSafe: true,
            reason: 'Bluetooth A2DP Active',
            outputTypes: ['bluetoothA2dp'],
          ),
        );

        final decision = await detector.inspectCurrentOutput();
        expect(decision.isSafe, isTrue);
        expect(decision.outputTypes, contains('bluetoothA2dp'));
      },
    );

    test(
      '2. FakeRouteDetector returns builtInSpeaker decision as unsafe/blocked',
      () async {
        final detector = FakeRouteDetector(
          const AudioRouteDecision(
            isSafe: false,
            reason: 'BLOCKED: Built-in speaker',
            outputTypes: ['builtInSpeaker'],
          ),
        );

        final decision = await detector.inspectCurrentOutput();
        expect(decision.isSafe, isFalse);
        expect(decision.reason, contains('BLOCKED'));
      },
    );

    test(
      '3. FakeRouteDetector returns builtInReceiver decision as unsafe/blocked',
      () async {
        final detector = FakeRouteDetector(
          const AudioRouteDecision(
            isSafe: false,
            reason: 'BLOCKED: Built-in receiver',
            outputTypes: ['builtInReceiver'],
          ),
        );

        final decision = await detector.inspectCurrentOutput();
        expect(decision.isSafe, isFalse);
      },
    );

    test(
      '4. FakeRouteDetector returns empty outputs decision as unsafe',
      () async {
        final detector = FakeRouteDetector(
          const AudioRouteDecision(
            isSafe: false,
            reason: 'Outputs list empty',
            outputTypes: [],
          ),
        );

        final decision = await detector.inspectCurrentOutput();
        expect(decision.isSafe, isFalse);
      },
    );

    test('5. FakeRouteDetector returns headphones decision as safe', () async {
      final detector = FakeRouteDetector(
        const AudioRouteDecision(
          isSafe: true,
          reason: 'Headphones active',
          outputTypes: ['headphones'],
        ),
      );

      final decision = await detector.inspectCurrentOutput();
      expect(decision.isSafe, isTrue);
    });

    test('6. FakeRouteDetector returns airPlay decision as safe', () async {
      final detector = FakeRouteDetector(
        const AudioRouteDecision(
          isSafe: true,
          reason: 'AirPlay active',
          outputTypes: ['airPlay'],
        ),
      );

      final decision = await detector.inspectCurrentOutput();
      expect(decision.isSafe, isTrue);
    });

    test('7. FakeRouteDetector decision toString formatting', () {
      const decision = AudioRouteDecision(
        isSafe: true,
        reason: 'Test reason',
        outputTypes: ['bluetoothA2dp'],
      );
      expect(decision.toString(), contains('isSafe: true'));
      expect(decision.toString(), contains('Test reason'));
    });

    test('8. Production policy blocks mixed Bluetooth and speaker route', () {
      final decision = SystemRouteDetector.classifyAppleOutputTypes([
        'bluetoothA2dp',
        'builtInSpeaker',
      ]);
      expect(decision.isSafe, isFalse);
    });

    test('9. Production policy fails closed for empty and unknown routes', () {
      expect(SystemRouteDetector.classifyAppleOutputTypes([]).isSafe, isFalse);
      expect(
        SystemRouteDetector.classifyAppleOutputTypes(['unknown']).isSafe,
        isFalse,
      );
    });

    test('10. Production policy allows active Bluetooth routes', () {
      for (final type in ['bluetoothA2dp', 'bluetoothLe', 'bluetoothHfp']) {
        expect(
          SystemRouteDetector.classifyAppleOutputTypes([type]).isSafe,
          isTrue,
        );
      }
    });
  });
}
