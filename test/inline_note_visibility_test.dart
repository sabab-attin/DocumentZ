import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/features/annotations.dart';

void main() {
  testWidgets(
    'idle inline note has no badge and page notes remain accessible',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = AnnotationStore('inline-note-test');
      await store.load();
      await store.add(
        DocumentMark(
          anchor: 'page:1',
          tool: MarkTool.note,
          rects: [const Rect.fromLTRB(.1, .1, .6, .2)],
          text: 'Remember this passage',
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 300,
                  height: 300,
                  child: PageMarks(
                    store: store,
                    anchor: 'page:1',
                    tool: MarkTool.browse,
                    dark: false,
                    onTouched: () {},
                  ),
                ),
                PageNotesButton(store: store, anchor: 'page:1'),
              ],
            ),
          ),
        ),
      );
      expect(find.byTooltip('View note'), findsNothing);
      expect(find.text('Notes (1)'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Open note'));
      await tester.pumpAndSettle();
      expect(find.text('Remember this passage'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
