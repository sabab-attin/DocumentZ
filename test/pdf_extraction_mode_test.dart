import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/pdf_extraction_mode.dart';

void main() {
  for (final mode in PdfExtractionMode.values) {
    testWidgets('selected pages can be saved as ${mode.name}', (tester) async {
      PdfExtractionMode? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await chooseExtractionMode(context, 3);
                },
                child: const Text('Pages selected'),
              ),
            ),
          ),
        ),
      );
      expect(find.text('Single file'), findsNothing);
      await tester.tap(find.text('Pages selected'));
      await tester.pumpAndSettle();
      expect(find.text('Extract 3 selected pages'), findsOneWidget);
      await tester.tap(
        find.text(
          mode == PdfExtractionMode.single ? 'Single file' : 'Separate files',
        ),
      );
      await tester.pumpAndSettle();
      expect(result, mode);
    });
  }
  testWidgets('cancelling output choice does not start extraction', (
    tester,
  ) async {
    PdfExtractionMode? result;
    var completed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await chooseExtractionMode(context, 2);
                completed = true;
              },
              child: const Text('Choose'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
  });
}
