import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/selection_panel.dart';

void main() {
  for (final size in [
    const Size(240, 480),
    const Size(320, 568),
    const Size(640, 240),
    const Size(1200, 800),
  ]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('selection panel fits $size at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var closed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: SelectionPanel(
                        readText: () async => 'Selected text',
                        onMark: (_, _) async {},
                        onClose: () => closed = true,
                        onAnnotate: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final card = tester.getRect(
          find
              .descendant(
                of: find.byType(SelectionPanel),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(card.left, greaterThanOrEqualTo(0));
        expect(card.right, lessThanOrEqualTo(size.width));
        expect(card.top, greaterThanOrEqualTo(0));
        expect(card.bottom, lessThanOrEqualTo(size.height));
        await tester.ensureVisible(find.byTooltip('Close'));
        await tester.tap(find.byTooltip('Close'));
        expect(closed, isTrue);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
