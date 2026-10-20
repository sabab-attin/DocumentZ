import 'dart:io';

import 'package:documentz/data/pdf_compression.dart';
import 'package:documentz/data/pdf_compression_choices.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:pdfrx/pdfrx.dart' as rx;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

Future<Uint8List> _fixture({bool alpha = false, bool jpeg = false}) async {
  final pixels = image.Image(
    width: 800,
    height: 500,
    numChannels: alpha ? 4 : 3,
  );
  var seed = 42;
  for (var y = 0; y < pixels.height; y++) {
    for (var x = 0; x < pixels.width; x++) {
      seed = (1664525 * seed + 1013904223) & 0xffffffff;
      final n = seed >> 24;
      pixels.setPixelRgba(
        x,
        y,
        (x + n) & 255,
        (y + n) & 255,
        n,
        alpha ? x * 255 ~/ 800 : 255,
      );
    }
  }
  final encoded = jpeg
      ? image.encodeJpg(pixels, quality: 98)
      : image.encodePng(pixels);
  final doc = sf.PdfDocument();
  doc.pageSettings.size = const Size(400, 600);
  doc.pageSettings.margins.all = 0;
  final page = doc.pages.add();
  page.graphics.drawString(
    'Selectable research paper text',
    sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
    bounds: const Rect.fromLTWH(20, 20, 350, 30),
  );
  page.graphics.drawRectangle(
    brush: sf.PdfBrushes.lightBlue,
    bounds: const Rect.fromLTWH(20, 70, 350, 200),
  );
  page.graphics.drawImage(
    sf.PdfBitmap(encoded),
    const Rect.fromLTWH(20, 70, 350, 200),
  );
  page.annotations.add(
    sf.PdfUriAnnotation(
      bounds: const Rect.fromLTWH(20, 20, 250, 20),
      uri: 'https://example.org/paper',
    ),
  );
  final field = sf.PdfTextBoxField(
    page,
    'research-note',
    const Rect.fromLTWH(20, 320, 250, 30),
  )..text = 'Keep this answer';
  doc.form.fields.add(field);
  doc.bookmarks.add('Paper').destination = sf.PdfDestination(
    page,
    const Offset(0, 0),
  );
  final section = doc.sections!.add();
  section.pageSettings.size = const Size(600, 300);
  section.pageSettings.margins.all = 0;
  final wide = section.pages.add();
  wide.graphics.drawString(
    'Landscape page with internal link',
    sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14),
    bounds: const Rect.fromLTWH(20, 20, 500, 30),
  );
  wide.annotations.add(
    sf.PdfDocumentLinkAnnotation(
      const Rect.fromLTWH(20, 20, 300, 20),
      sf.PdfDestination(page, const Offset(0, 0)),
    ),
  );
  final bytes = Uint8List.fromList(await doc.save());
  doc.dispose();
  return bytes;
}

Future<void> _checkPdf(
  Uint8List original,
  Uint8List output, {
  bool identicalPixels = false,
}) async {
  final source = await rx.PdfDocument.openData(original);
  final result = await rx.PdfDocument.openData(output);
  try {
    expect(result.pages.length, source.pages.length);
    for (var i = 0; i < source.pages.length; i++) {
      final a = source.pages[i], b = result.pages[i];
      expect((b.width, b.height, b.rotation), (a.width, a.height, a.rotation));
      final originalText = await a.loadStructuredText(),
          text = await b.loadStructuredText();
      expect(text.fullText, originalText.fullText);
      expect(
        text.fragments,
        isNotEmpty,
      ); // Real selectable PDF text, not OCR or an image.
      final oldLinks = await a.loadLinks(enableAutoLinkDetection: false);
      final newLinks = await b.loadLinks(enableAutoLinkDetection: false);
      expect(newLinks.length, oldLinks.length);
      for (var j = 0; j < oldLinks.length; j++) {
        expect(newLinks[j].url, oldLinks[j].url);
        expect(newLinks[j].dest?.pageNumber, oldLinks[j].dest?.pageNumber);
        expect(newLinks[j].rects, oldLinks[j].rects);
      }
      if (identicalPixels) {
        final before = (await a.render(
          fullWidth: a.width,
          fullHeight: a.height,
        ))!;
        final after = (await b.render(
          fullWidth: b.width,
          fullHeight: b.height,
        ))!;
        try {
          expect(after.pixels, orderedEquals(before.pixels));
        } finally {
          before.dispose();
          after.dispose();
        }
      }
    }
  } finally {
    await source.dispose();
    await result.dispose();
  }
  final checked = sf.PdfDocument(inputBytes: output);
  try {
    expect(checked.bookmarks.count, 1);
    expect(checked.form.fields.count, 1);
    expect(
      (checked.form.fields[0] as sf.PdfTextBoxField).text,
      'Keep this answer',
    );
  } finally {
    checked.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  setUpAll(() async {
    temporary = await Directory.systemTemp.createTemp(
      'documentz_compression_preservation_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => temporary.path,
        );
    await rx.pdfrxFlutterInitialize();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await temporary.delete(recursive: true);
  });
  test('every compression preset reduces a small image PDF and retains real text, links, forms and mixed pages', () async {
    final input = await _fixture();
    expect(input.length, lessThan(2000000));
    final original = Uint8List.fromList(input);
    final progress = <double>[];
    final choices = await measurePdfCompression(
      input,
      cancelled: () => false,
      onProgress: progress.add,
    );
    expect(choices.length, 4);
    var previous = input.length;
    for (final choice in choices) {
      expect(choice.imageOnly, isFalse);
      expect(choice.size, lessThanOrEqualTo(previous));
      previous = choice.size;
      if (choice.bytes != null) {
        expect(choice.size, lessThan(input.length));
        await _checkPdf(
          input,
          choice.bytes!,
          identicalPixels: choice.mode == PdfCompressionMode.preserve,
        );
      }
    }
    expect(choices.last.bytes, isNotNull);
    expect(choices.last.size, lessThan(input.length ~/ 2));
    expect(input, orderedEquals(original));
    expect(progress.last, 1);
  }, timeout: const Timeout(Duration(seconds: 60)));
  test(
    'embedded Unicode font data and selectable text survive every preset',
    () async {
      final font = sf.PdfTrueTypeFont(
        await File('assets/fonts/Tinos-Regular.ttf').readAsBytes(),
        18,
      );
      final doc = sf.PdfDocument();
      final page = doc.pages.add();
      page.graphics.drawString(
        'Caf\u00e9 \u2014 na\u00efve \u03b1\u03b2\u03b3',
        font,
        bounds: const Rect.fromLTWH(10, 10, 400, 40),
      );
      final input = Uint8List.fromList(await doc.save());
      doc.dispose();
      final source = await rx.PdfDocument.openData(input);
      final originalText =
          (await source.pages.single.loadStructuredText()).fullText;
      final raster = (await source.pages.single.render(
        fullWidth: 400,
        fullHeight: 550,
      ))!;
      try {
        final choices = await measurePdfCompression(
          input,
          cancelled: () => false,
          onProgress: (_) {},
        );
        for (final choice in choices) {
          final result = await rx.PdfDocument.openData(choice.bytes ?? input);
          try {
            expect(
              (await result.pages.single.loadStructuredText()).fullText,
              originalText,
            );
            final after = (await result.pages.single.render(
              fullWidth: 400,
              fullHeight: 550,
            ))!;
            try {
              expect(after.pixels, orderedEquals(raster.pixels));
            } finally {
              after.dispose();
            }
          } finally {
            await result.dispose();
          }
        }
      } finally {
        raster.dispose();
        await source.dispose();
      }
    },
  );
  test(
    'existing JPEG images compress without rasterizing surrounding text',
    () async {
      final input = await _fixture(jpeg: true);
      final output = await optimizePdf(
        input,
        imageQuality: 45,
        maxImageDimension: 1024,
      );
      expect(output.bytes.length, lessThan(input.length * .8));
      await _checkPdf(input, output.bytes);
    },
  );
  test('soft-mask transparency remains pixel-identical even at the smallest setting', () async {
    final input = await _fixture(alpha: true);
    final output = await optimizePdf(
      input,
      imageQuality: 45,
      maxImageDimension: 1024,
    );
    await _checkPdf(input, output.bytes, identicalPixels: true);
  });
  test('cancelled compression does not start rewriting a document', () async {
    expect(
      () => measurePdfCompression(
        Uint8List(0),
        cancelled: () => true,
        onProgress: (_) {},
      ),
      throwsA(isA<PdfCompressionCancelled>()),
    );
  });
}
