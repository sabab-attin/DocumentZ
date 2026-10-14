import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:documentz/features/page_turn.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'text drag applies the active tool without a hold or second action',
    (tester) async {
      final store = AnnotationStore('direct-text');
      await store.load();
      for (final tool in [
        MarkTool.highlight,
        MarkTool.underline,
        MarkTool.strikethrough,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 300,
                child: AnnotatedParagraph(
                  element: html
                      .parseFragment(
                        '<p>First line of text and a second line of text to mark.</p>',
                      )
                      .children
                      .single,
                  block: 'body',
                  anchor: 'chapter:1',
                  store: store,
                  style: const TextStyle(fontSize: 20, height: 1.6),
                  activeTool: tool,
                  onLink: (_) {},
                  onSelection: (_) {},
                ),
              ),
            ),
          ),
        );
        final start =
            tester.getTopLeft(find.byType(SelectableText)) +
            const Offset(1, 12);
        final touch = await tester.startGesture(start);
        await touch.moveTo(start + const Offset(200, 32));
        await touch.up();
        await tester.pumpAndSettle();
        expect(store.marks.last.tool, tool);
        expect(store.marks.last.end, greaterThan(store.marks.last.start));
        expect(store.marks.last.quote, startsWith('First'));
      }
    },
  );
  testWidgets('opening controls preserves the full document viewport', (
    tester,
  ) async {
    final expanded = ValueNotifier<bool>(false);
    addTearDown(expanded.dispose);
    const pageKey = ValueKey('page');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderControlsScope(
            expanded: expanded,
            child: const ReaderControlsOverlay(
              controls: SizedBox(height: 150, child: Text('Tools')),
              child: ColoredBox(key: pageKey, color: Colors.white),
            ),
          ),
        ),
      ),
    );
    final size = tester.getSize(find.byKey(pageKey));
    expect(find.text('Tools'), findsNothing);
    expanded.value = true;
    await tester.pump();
    expect(find.text('Tools'), findsOneWidget);
    expect(tester.getSize(find.byKey(pageKey)), size);
    expanded.value = false;
    await tester.pump();
    expect(tester.getSize(find.byKey(pageKey)), size);
  });
  testWidgets('reduced motion changes page immediately without a curl', (
    tester,
  ) async {
    final key = GlobalKey<PageTurnState>();
    int changed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SizedBox.expand(
            child: PageTurn(
              key: key,
              paper: Colors.white,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await key.currentState!.turn(1, () => changed++);
    expect(changed, 1);
    expect(key.currentState!.busy, false);
    expect(key.currentState!.snapshot, isNull);
  });
}
