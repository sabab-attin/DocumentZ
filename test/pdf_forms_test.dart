import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:documentz/features/pdf_forms.dart';

void main() {
  testWidgets('form edits are saved into a copy and read-only fields remain locked', (tester) async {
    final source = sf.PdfDocument();
    final page = source.pages.add();
    source.form.fields.add(sf.PdfTextBoxField(page, 'Name', const Rect.fromLTWH(10, 10, 150, 30), text: 'Before'));
    source.form.fields.add(sf.PdfTextBoxField(page, 'Locked', const Rect.fromLTWH(10, 50, 150, 30), text: 'Keep')..readOnly = true);
    source.form.fields.add(sf.PdfCheckBoxField(page, 'Agree', const Rect.fromLTWH(10, 90, 20, 20)));
    final bytes = (await tester.runAsync(() async => Uint8List.fromList(
      await source.save().timeout(const Duration(seconds: 30)))))!;
    source.dispose();
    Uint8List? result;
    final closed = Completer<void>();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async {
        result = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => PdfFormScreen(bytes: bytes)));
        closed.complete();
      },
      child: const Text('Open form'))))));
    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(tester.widget<TextField>(fields.at(1)).readOnly, isTrue);
    await tester.enterText(fields.first, 'After');
    await tester.tap(find.text('Agree'));
    await tester.tap(find.text('Continue'));
    // Saving may mix real work with callbacks created in the simulated zone.
    // Drain both clocks instead of awaiting the navigation future while the
    // simulated clock (and its microtasks) is suspended inside runAsync.
    final savingTime = Stopwatch()..start();
    while (!closed.isCompleted && savingTime.elapsed < const Duration(seconds: 30)) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('Could not save form values.'), findsNothing);
    }
    expect(closed.isCompleted, isTrue, reason: 'Form saving did not finish within 30 seconds.');
    await tester.pumpAndSettle();
    expect(result, isNotNull);
    final changed = sf.PdfDocument(inputBytes: result!);
    final original = sf.PdfDocument(inputBytes: bytes);
    try {
      expect((changed.form.fields[0] as sf.PdfTextBoxField).text, 'After');
      expect((changed.form.fields[1] as sf.PdfTextBoxField).text, 'Keep');
      expect((changed.form.fields[2] as sf.PdfCheckBoxField).isChecked, isTrue);
      expect((original.form.fields[0] as sf.PdfTextBoxField).text, 'Before');
    } finally { changed.dispose(); original.dispose(); }
  });
}
