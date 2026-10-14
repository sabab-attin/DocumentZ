import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:image/image.dart' as image;
import 'package:documentz/data/pdf_compression.dart';

import 'fixtures/pdf_fixture.dart';

void main() {
  test('lossless optimization preserves text, forms, bookmarks and source without increasing size', () async {
    final doc = sf.PdfDocument();
    doc.compressionLevel = sf.PdfCompressionLevel.none;
    doc.pageSettings.size = const Size(300, 400);
    doc.pageSettings.margins.all = 0;
    final page = doc.pages.add();
    for (var i = 0; i < 200; i++) {
      page.graphics.drawString(
        'Compression preserves searchable text',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(10, 10, 270, 30),
      );
    }
    page.graphics.drawRectangle(
      brush: sf.PdfBrushes.red,
      bounds: const Rect.fromLTWH(40, 70, 50, 50),
    );
    final field = sf.PdfTextBoxField(
      page,
      'name',
      const Rect.fromLTWH(10, 200, 200, 30),
    );
    field.text = 'Ada';
    doc.form.fields.add(field);
    doc.bookmarks.add('Start').destination = sf.PdfDestination(
      page,
      const Offset(0, 0),
    );
    final bytes = Uint8List.fromList(await doc.save());
    doc.dispose();
    final before = Uint8List.fromList(bytes);
    final result = await optimizePdf(bytes);
    expect(result.bytes.length, lessThanOrEqualTo(bytes.length));
    expect(result.imageOnly, isFalse);
    expect(result.pages, 1);
    if (result.bytes.length == bytes.length) {
      // An unsuccessful optimization must return the untouched original.
      expect(result.bytes, orderedEquals(before));
    }
    expect(bytes, orderedEquals(before));
    final checked = sf.PdfDocument(inputBytes: result.bytes);
    try {
      expect(checked.pages.count, 1);
      expect(checked.bookmarks.count, 1);
      expect((checked.form.fields[0] as sf.PdfTextBoxField).text, 'Ada');
      expect(
        sf.PdfTextExtractor(checked).extractText(),
        contains('Compression preserves searchable text'),
      );
      expect(checked.pages[0].getClientSize(), const Size(300, 400));
    } finally {
      checked.dispose();
    }
  });
  test('compression never produces a larger copy', () async {
    final bytes = imageAndTextPdf();
    final result = await optimizePdf(bytes);
    expect(result.bytes.length, lessThanOrEqualTo(bytes.length));
    final checked = sf.PdfDocument(inputBytes: result.bytes);
    try {
      expect(sf.PdfTextExtractor(checked).extractText(), contains('Hello PDF'));
    } finally {
      checked.dispose();
    }
  });
  test('signed and protected files are refused without modification', () {
    for (final marker in ['/ByteRange', '/Encrypt']) {
      final bytes = Uint8List.fromList(marker.codeUnits),
          before = Uint8List.fromList(marker.codeUnits);
      expect(() => checkPdfCompressionInput(bytes), throwsFormatException);
      expect(bytes, orderedEquals(before));
    }
  });
  test(
    'page image compression reduces noisy PNG data and retains dimensions',
    () async {
      final pixels = image.Image(width: 256, height: 256);
      var seed = 12345;
      int nextChannel() {
        seed = (1664525 * seed + 1013904223) & 0xffffffff;
        return seed >> 24;
      }

      for (var y = 0; y < pixels.height; y++) {
        for (var x = 0; x < pixels.width; x++) {
          pixels.setPixelRgb(x, y, nextChannel(), nextChannel(), nextChannel());
        }
      }
      final png = Uint8List.fromList(image.encodePng(pixels));
      final before = Uint8List.fromList(png);
      final jpeg = await compressPageImage(png, 65);
      expect(jpeg.length, lessThan(png.length));
      expect(png, orderedEquals(before));
      final decoded = image.decodeJpg(jpeg);
      expect(decoded, isNotNull);
      expect(decoded!.width, 256);
      expect(decoded.height, 256);
    },
  );
  test('image-only PDF keeps page sizes and page count', () async {
    final jpeg = Uint8List.fromList(
      image.encodeJpg(image.Image(width: 8, height: 8)),
    );
    final result = await assembleImagePdf([
      CompressedPdfPage(jpeg, 200, 300),
      CompressedPdfPage(jpeg, 400, 200),
    ]);
    expect(result.imageOnly, isTrue);
    final doc = sf.PdfDocument(inputBytes: result.bytes);
    try {
      expect(doc.pages.count, 2);
      expect(doc.pages[0].getClientSize(), const Size(200, 300));
      expect(doc.pages[1].getClientSize(), const Size(400, 200));
      expect(sf.PdfTextExtractor(doc).extractText().trim(), isEmpty);
    } finally {
      doc.dispose();
    }
  });
}
