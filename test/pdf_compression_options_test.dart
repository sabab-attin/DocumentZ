import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/pdf_compression_screen.dart';
import 'package:documentz/data/local_library_web.dart';

import 'fixtures/pdf_fixture.dart';

void main() {
  testWidgets('image compression requires explicit consent before processing', (
    tester,
  ) async {
    // Keep all consent controls mounted as the image-only explanation appears.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 1400);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PdfCompressionScreen(
          bytes: imageAndTextPdf(),
          title: 'Example',
          repository: BrowserLibrary(),
          onSaved: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = find.byWidgetPredicate((widget) => widget is FilledButton);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(find.text('Balanced image copy'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.ensureVisible(find.byType(CheckboxListTile));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(find.text('Smaller image copy'));
    await tester.tap(find.text('Smaller image copy'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });
}
