import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/reader_controls.dart';

void main() {
  testWidgets(
    'zoom presets close the sheet without disposing its field early',
    (tester) async {
      double selected = 1;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showReaderZoom(
                  context,
                  current: 1,
                  onZoom: (value) => selected = value,
                  onBestFit: () {},
                ),
                child: const Text('Fit page'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Fit page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('59%'));
      await tester.pumpAndSettle();
      expect(selected, .59);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'placing text closes its dialog without disposing its field early',
    (tester) async {
      TextAnnotationDraft? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await composeAnnotationText(context);
                },
                child: const Text('Compose'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Compose'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'A placed annotation');
      await tester.tap(find.text('Place text'));
      await tester.pumpAndSettle();
      expect(result?.text, 'A placed annotation');
      expect(result?.size, 24);
      expect(find.byType(TextField), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
