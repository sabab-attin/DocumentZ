import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/annotation_color_picker.dart';
import 'package:documentz/features/selection_panel.dart';

void main() {
  testWidgets('black is available and custom colors can be selected', (
    tester,
  ) async {
    expect(selectionColors['Black'], 0xff000000);
    Color? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await pickAnnotationColor(
                  context,
                  initial: Colors.black,
                );
              },
              child: const Text('Pick'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pick'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Use color'));
    await tester.tap(find.text('Use color'));
    await tester.pumpAndSettle();
    expect(selected, Colors.black);
  });
}
