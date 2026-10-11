import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:printing/printing.dart';
import 'package:documentz/data/pdf_editing.dart';

String extractedText(sf.PdfDocument document) =>
  sf.PdfTextExtractor(document).extractText().replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('explicit thumbnail order changes page order without changing source bytes', () async {
    final source = await PdfEditing.extract([
      await PdfEditing.create('First', 'First page'), await PdfEditing.create('Second', 'Second page'),
    ]);
    final snapshot = Uint8List.fromList(source);
    final reordered = sf.PdfDocument(inputBytes: await PdfEditing.extract([source], pageOrder: [1, 0]));
    try {
      final extractor = sf.PdfTextExtractor(reordered);
      expect(extractor.extractText(startPageIndex: 0, endPageIndex: 0).replaceAll(RegExp(r'\s+'), ' '), contains('Second page'));
      expect(extractor.extractText(startPageIndex: 1, endPageIndex: 1).replaceAll(RegExp(r'\s+'), ' '), contains('First page'));
      expect(source, snapshot);
    } finally { reordered.dispose(); }
    await expectLater(PdfEditing.extract([source], pageOrder: []), throwsFormatException);
  });
  test('area replacement removes chosen page text and retains other pages', () async {
    final source = await PdfEditing.extract([
      await PdfEditing.create('Original', 'OLD_SECRET'), await PdfEditing.create('Other', 'KEEP_TEXT'),
    ]);
    final pixels = Uint8List(100 * 100 * 4)..fillRange(0, 100 * 100 * 4, 255);
    final cleared = await PdfEditing.clearArea(source, 0, const Rect.fromLTRB(.1, .1, .8, .5), rasterOverride: PdfRaster(100, 100, pixels));
    final changed = await PdfEditing.addText(cleared, 0, const Rect.fromLTRB(.1, .1, .9, .9), 'New', fontSize: 8);
    final output = sf.PdfDocument(inputBytes: changed);
    try {
      final text = extractedText(output);
      expect(text, contains('New'));
      expect(text, contains('KEEP_TEXT'));
      expect(text, isNot(contains('OLD_SECRET')));
    } finally { output.dispose(); }
  });
  test('page ranges reject invalid values and preserve explicit order', () {
    expect(parsePageRange('3,1-2,3', 4), [2, 0, 1]);
    expect(parsePageRange('', 2), [0, 1]);
    for (final value in ['0', '5', '3-1', 'a', '1-2-3']) {
      expect(() => parsePageRange(value, 4), throwsFormatException);
    }
  });

  test('merge and split preserve selected page artwork and source bytes', () async {
    final first = await PdfEditing.create('First', 'First document');
    final second = await PdfEditing.create('Second', 'Second document');
    final snapshot = Uint8List.fromList(first);
    final merged = await PdfEditing.extract([first, second]);
    final document = sf.PdfDocument(inputBytes: merged);
    expect(document.pages.count, 2);
    expect(extractedText(document), contains('First document'));
    expect(extractedText(document), contains('Second document'));
    document.dispose();
    final split = sf.PdfDocument(inputBytes: await PdfEditing.extract([merged], pages: '2'));
    expect(split.pages.count, 1);
    expect(extractedText(split), contains('Second document'));
    expect(extractedText(split), isNot(contains('First')));
    split.dispose();
    expect(first, snapshot);
  });

  test('rotation changes only selected pages and encryption requires password', () async {
    final input = await PdfEditing.create('Test', 'Reader test');
    final rotated = sf.PdfDocument(inputBytes: await PdfEditing.rotate(input, '1', 90, ''));
    expect(rotated.pages[0].rotation, sf.PdfPageRotateAngle.rotateAngle90);
    rotated.dispose();
    final encrypted = await PdfEditing.encrypt(input, 'open-password', 'owner-password', '');
    expect(() => sf.PdfDocument(inputBytes: encrypted, password: 'wrong'), throwsA(anything));
    final unlocked = sf.PdfDocument(inputBytes: encrypted, password: 'open-password');
    expect(extractedText(unlocked), contains('Reader test'));
    unlocked.dispose();
    final clean = sf.PdfDocument(inputBytes: await PdfEditing.unprotect(encrypted, 'open-password'));
    expect(clean.pages.count, 1);
    clean.dispose();
  });

  test('redaction rebuilds pages without source searchable text', () async {
    final original = await PdfEditing.create('Private', 'SECRET_TOKEN');
    final pixels = Uint8List(100 * 100 * 4)..fillRange(0, 100 * 100 * 4, 255);
    final redacted = await PdfEditing.redact(original, 0, const Rect.fromLTRB(.2, .2, .8, .8),
      rasters: Stream.value(PdfRaster(100, 100, pixels)));
    final output = sf.PdfDocument(inputBytes: redacted);
    expect(output.pages.count, 1);
    expect(sf.PdfTextExtractor(output).extractText(), isNot(contains('SECRET_TOKEN')));
    expect(sf.PdfTextExtractor(output).extractText().trim(), isEmpty);
    output.dispose();
  });
}
