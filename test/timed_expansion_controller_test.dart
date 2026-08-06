import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/widgets/timed_expansion_controller.dart';

void main() {
  testWidgets('player panel auto-hides 30 seconds after every expansion', (
    tester,
  ) async {
    final controller = TimedExpansionController(
      initialAutoHideDelay: const Duration(seconds: 30),
    );
    addTearDown(controller.dispose);

    expect(controller.isExpanded, isTrue);
    await tester.pump(const Duration(seconds: 29));
    expect(controller.isExpanded, isTrue);

    await tester.pump(const Duration(seconds: 1));
    expect(controller.isExpanded, isFalse);

    controller.toggleManually();
    expect(controller.isExpanded, isTrue);
    await tester.pump(const Duration(seconds: 29));
    expect(controller.isExpanded, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(controller.isExpanded, isFalse);
  });

  testWidgets('manual collapse cancels the pending auto-hide timer', (
    tester,
  ) async {
    final controller = TimedExpansionController(
      initialAutoHideDelay: const Duration(seconds: 30),
    );
    addTearDown(controller.dispose);

    controller.toggleManually();
    expect(controller.isExpanded, isFalse);

    await tester.pump(const Duration(seconds: 31));
    expect(controller.isExpanded, isFalse);
  });
}
