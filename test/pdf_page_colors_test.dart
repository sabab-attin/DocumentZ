import 'dart:io';

import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/data/pdf_page_colors.dart';
import 'package:documentz/data/pdf_editing.dart';

import 'fixtures/pdf_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'dark PDF keeps image pixels, darkens paper, and leaves source untouched',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'documentz_pdf_colors_',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => temporary.path,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await temporary.delete(recursive: true);
      });
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openData(
        imageAndTextPdf(),
        sourceName: 'color-fixture',
      );
      try {
        final original = document.pages.single;
        final normal = (await original.render(width: 200, height: 200))!;
        final darkDocument = applyPdfPageColors(document);
        expect(identical(document.pages.single, original), isTrue);
        expect(
          identical(darkDocument.pages.single.document, darkDocument),
          isTrue,
        );
        final dark = (await darkDocument.pages.single.render(
          width: 200,
          height: 200,
        ))!;
        final restored = (await original.render(width: 200, height: 200))!;
        try {
          for (final point in [(75, 105), (125, 105), (75, 155), (125, 155)]) {
            final offset = (point.$2 * 200 + point.$1) * 4;
            expect(
              dark.pixels.sublist(offset, offset + 4),
              normal.pixels.sublist(offset, offset + 4),
            );
          }
          expect(normal.pixels[0], 255);
          expect(dark.pixels[0], 0);
          expect(restored.pixels, normal.pixels);
          int whiteLetters = 0;
          for (int y = 20; y < 50; y++) {
            for (int x = 15; x < 150; x++) {
              final offset = (y * 200 + x) * 4;
              if (normal.pixels[offset] < 30 && dark.pixels[offset] > 220) {
                whiteLetters++;
              }
            }
          }
          expect(whiteLetters, greaterThan(20));
          final text = await darkDocument.pages.single.loadStructuredText();
          expect(text.fullText, contains('Hello PDF'));
        } finally {
          normal.dispose();
          dark.dispose();
          restored.dispose();
        }
      } finally {
        await document.dispose();
      }
    },
    skip: !supportsPdfPageColors,
  );

  test(
    'dark mode preserves redacted raster pages and their black masks',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'documentz_redaction_colors_',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => temporary.path,
      );
      addTearDown(() async {
        messenger.setMockMethodCallHandler(channel, null);
        await temporary.delete(recursive: true);
      });
      await pdfrxFlutterInitialize();
      final pixels = Uint8List(100 * 100 * 4)..fillRange(0, 100 * 100 * 4, 255);
      // Color artwork outside the redaction also has to survive unchanged.
      for (int y = 5; y < 15; y++) {
        for (int x = 5; x < 15; x++) {
          final offset = (y * 100 + x) * 4;
          pixels[offset] = 230;
          pixels[offset + 1] = 40;
          pixels[offset + 2] = 20;
        }
      }
      final bytes = await PdfEditing.redact(
        imageAndTextPdf(),
        0,
        const Rect.fromLTRB(.3, .3, .7, .7),
        rasters: Stream.value(PdfRaster(100, 100, pixels)),
      );
      final originalBytes = Uint8List.fromList(bytes);
      final document = await PdfDocument.openData(
        bytes,
        sourceName: 'redacted-color-fixture',
      );
      try {
        expect(
          (await document.pages.single.loadText())?.fullText.trim() ?? '',
          isEmpty,
        );
        final normal = (await document.pages.single.render(
          width: 100,
          height: 100,
          fullWidth: 100,
          fullHeight: 100,
        ))!;
        final dark = (await applyPdfPageColors(document).pages.single
            .render(width: 100, height: 100, fullWidth: 100, fullHeight: 100))!;
        try {
          expect(dark.pixels, normal.pixels);
          expect(dark.pixels[0], greaterThan(240));
          expect(dark.pixels[(50 * 100 + 50) * 4], lessThan(10));
          expect(bytes, originalBytes);
        } finally {
          normal.dispose();
          dark.dispose();
        }
      } finally {
        await document.dispose();
      }
    },
    skip: !supportsPdfPageColors,
  );
}
