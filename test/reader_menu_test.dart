import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:documentz/features/selection_panel.dart';

void main() {
  testWidgets('each marking tool applies any of the six colors immediately', (
    tester,
  ) async {
    for (final kind in const {
      'Highlight': MarkTool.highlight,
      'Underline': MarkTool.underline,
      'Strikethrough': MarkTool.strikethrough,
    }.entries) {
      for (final color in selectionColors.entries) {
        MarkTool? appliedTool;
        int? appliedColor;
        var dismissed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectionPanel(
                key: ValueKey(kind.key + color.key),
                readText: () async => 'Selected text',
                onMark: (tool, value) async {
                  appliedTool = tool;
                  appliedColor = value;
                },
                onClose: () => dismissed = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(kind.key));
        await tester.pump();
        expect(appliedTool, isNull);
        expect(dismissed, isFalse);
        expect(find.textContaining('Apply '), findsNothing);
        await tester.tap(find.byTooltip(color.key));
        await tester.pumpAndSettle();
        expect(appliedTool, kind.value);
        expect(appliedColor, color.value);
        expect(dismissed, isTrue);
      }
    }
  });

  testWidgets('selection panel fits a 360 pixel phone', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionPanel(
            readText: () async => 'Text',
            onMark: (_, color) async {},
            onClose: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byTooltip('Copy')).width,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets('expanded menu keeps page geometry and dismisses outside', (
    tester,
  ) async {
    final open = ValueNotifier<bool>(false);
    addTearDown(open.dispose);
    const page = ValueKey('reader-page');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderControlsScope(
            expanded: open,
            child: ReaderControlsOverlay(
              controls: ReaderMenuGrid(
                children: [
                  ReaderMenuAction(
                    label: 'Bookmark page',
                    icon: Icons.bookmark_border,
                    onTap: () {},
                  ),
                ],
              ),
              child: const ColoredBox(key: page, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byKey(page));
    expect(find.text('Bookmark page'), findsNothing);
    open.value = true;
    await tester.pumpAndSettle();
    expect(find.text('Bookmark page'), findsOneWidget);
    expect(tester.getRect(find.byKey(page)), bounds);
    await tester.tapAt(const Offset(5, 550));
    await tester.pumpAndSettle();
    expect(open.value, isFalse);
  });
}
