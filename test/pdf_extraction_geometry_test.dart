import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:documentz/data/pdf_editing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'extraction retains wide, tall, square, rotated and mixed page geometry',
    () async {
      final source = sf.PdfDocument();
      const dimensions = [
        Size(1600, 400),
        Size(250, 1300),
        Size(500, 500),
        Size(720, 405),
      ];
      for (var i = 0; i < dimensions.length; i++) {
        final size = dimensions[i];
        final section = source.sections!.add();
        section.pageSettings.orientation = size.width > size.height
            ? sf.PdfPageOrientation.landscape
            : sf.PdfPageOrientation.portrait;
        section.pageSettings.size = size;
        section.pageSettings.margins.all = 0;
        final page = section.pages.add();
        page.graphics.drawString(
          'LEFT-$i',
          sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
          bounds: const Rect.fromLTWH(8, 8, 100, 30),
        );
        page.graphics.drawString(
          'RIGHT-$i',
          sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
          bounds: Rect.fromLTWH(size.width - 100, size.height - 40, 95, 30),
        );
      }
      final unrotated = Uint8List.fromList(await source.save());
      source.dispose();
      final rotatedSource = sf.PdfDocument(inputBytes: unrotated);
      rotatedSource.pages[3].rotation = sf.PdfPageRotateAngle.rotateAngle90;
      final bytes = Uint8List.fromList(await rotatedSource.save());
      rotatedSource.dispose();
      // Verify the serialized fixture, rather than assuming a new-page setter
      // produced a rotated PDF. Keep the extraction rotation assertion below.
      final baseline = sf.PdfDocument(inputBytes: bytes);
      try {
        expect(baseline.pages[3].rotation, sf.PdfPageRotateAngle.rotateAngle90);
      } finally {
        baseline.dispose();
      }
      final snapshot = Uint8List.fromList(bytes);
      for (final selection in [
        [0],
        [1],
        [2],
        [3],
        [0, 2, 3],
        [3, 0], // Reordering also exercises the template-copy fallback.
      ]) {
        final output = sf.PdfDocument(
          inputBytes: await PdfEditing.extract([bytes], pageOrder: selection),
        );
        try {
          expect(output.pages.count, selection.length);
          for (var i = 0; i < selection.length; i++) {
            final original = selection[i];
            expect(
              output.pages[i].size.width,
              closeTo(dimensions[original].width, .01),
            );
            expect(
              output.pages[i].size.height,
              closeTo(dimensions[original].height, .01),
            );
            expect(
              output.pages[i].rotation,
              original == 3
                  ? sf.PdfPageRotateAngle.rotateAngle90
                  : sf.PdfPageRotateAngle.rotateAngle0,
            );
            final lines = sf.PdfTextExtractor(output)
                .extractTextLines(startPageIndex: i, endPageIndex: i);
            expect(
              lines.map((line) => line.text).join(),
              contains('RIGHT-$original'),
            );
            final right = lines.firstWhere(
              (line) => line.text.contains('RIGHT-$original'),
            );
            expect(
              right.bounds.right,
              lessThanOrEqualTo(output.pages[i].size.width + 1),
            );
          }
        } finally {
          output.dispose();
        }
      }
      expect(bytes, snapshot);
    },
  );
}
