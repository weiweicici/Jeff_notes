import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/widgets/tap_page_turn_region.dart';

void main() {
  testWidgets(
    'upper and lower taps page by 88 percent without stealing buttons',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var buttonTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TapPageTurnRegion(
              key: const Key('page-region'),
              controller: controller,
              child: ListView(
                controller: controller,
                children: [
                  SizedBox(
                    height: 60,
                    child: TapPageTurnIgnore(
                      child: ElevatedButton(
                        onPressed: () => buttonTaps++,
                        child: const Text('interactive control'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1800),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('interactive control'));
      await tester.pumpAndSettle();
      expect(buttonTaps, 1);
      expect(controller.offset, 0);

      final rect = tester.getRect(find.byKey(const Key('page-region')));
      await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.75));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(rect.height * 0.88, 1));

      await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.25));
      await tester.pumpAndSettle();
      expect(controller.offset, closeTo(0, 1));
    },
  );

  testWidgets('a normal tap on selectable document text still turns a page', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TapPageTurnRegion(
            key: const Key('selectable-region'),
            controller: controller,
            child: ListView(
              controller: controller,
              children: const [
                SizedBox(
                  height: 1800,
                  child: SelectableText(
                    'Selectable academic text',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final rect = tester.getRect(find.byKey(const Key('selectable-region')));
    await tester.tapAt(Offset(rect.center.dx, rect.top + rect.height * 0.75));
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(rect.height * 0.88, 1));
  });
}
