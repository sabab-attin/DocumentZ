import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/selection_panel.dart';

void main() {
  for (final annotate in [false, true]) {
    testWidgets(
      annotate
          ? 'Annotate closes selection and enters annotation mode'
          : 'Close clears selected text and dismisses the panel',
      (tester) async {
        var entered = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SelectableText(
                'Select this text',
                contextMenuBuilder: (context, editable) => SelectionPanel(
                  readText: () async => editable.textEditingValue.selection
                      .textInside(editable.textEditingValue.text),
                  onMark: (_, _) async {},
                  onClose: () => closeReaderTextSelection(editable),
                  onAnnotate: () => entered = true,
                ),
              ),
            ),
          ),
        );
        await tester.longPress(find.text('Select this text'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectionPanel), findsOneWidget);
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        expect(editable.textEditingValue.selection.isCollapsed, isFalse);
        await tester.tap(find.byTooltip(annotate ? 'Annotate' : 'Close'));
        await tester.pumpAndSettle();
        expect(find.byType(SelectionPanel), findsNothing);
        expect(editable.textEditingValue.selection.isCollapsed, isTrue);
        expect(entered, annotate);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
