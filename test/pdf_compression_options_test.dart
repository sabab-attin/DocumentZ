import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/pdf_compression_screen.dart';
import 'package:documentz/data/local_library_web.dart';

import 'fixtures/pdf_fixture.dart';

void main() {
  testWidgets('compression shows measured sizes and disables larger copies', (
    tester,
  ) async {
    final input = imageAndTextPdf();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfCompressionScreen(
          bytes: input,
          title: 'Example',
          repository: BrowserLibrary(),
          onSaved: () {},
          measure: (bytes, {required cancelled, required onProgress}) async => [
            PdfCompressionChoice(
              PdfCompressionMode.balanced,
              320,
              Uint8List(320),
            ),
            const PdfCompressionChoice(PdfCompressionMode.small, 1500, null),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0.3 KB'), findsOneWidget);
    expect(find.text('1.5 KB · Not smaller'), findsOneWidget);
    expect(find.text('No size reduction'), findsNothing);
    final preview = find.byWidgetPredicate((w) => w is FilledButton);
    await tester.ensureVisible(preview);
    expect(tester.widget<FilledButton>(preview).onPressed, isNotNull);
    final larger = tester.widget<ListTile>(
      find.ancestor(of: find.text('Small'), matching: find.byType(ListTile)),
    );
    expect(larger.onTap, isNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('no smaller result cannot be saved or trigger a popup', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PdfCompressionScreen(
          bytes: imageAndTextPdf(),
          title: 'Compact',
          repository: BrowserLibrary(),
          onSaved: () {},
          measure: (bytes, {required cancelled, required onProgress}) async => [
            PdfCompressionChoice(
              PdfCompressionMode.balanced,
              bytes.length + 500,
              null,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final preview = find.byWidgetPredicate((w) => w is FilledButton);
    expect(tester.widget<FilledButton>(preview).onPressed, isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
