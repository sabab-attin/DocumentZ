import 'dart:typed_data';
import 'dart:ui';

import 'package:documentz/data/pdf_editing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'single and separate extraction preserve research-paper URL links',
    () async {
      final document = sf.PdfDocument();
      for (var i = 0; i < 3; i++) {
        final page = document.pages.add();
        page.annotations.add(
          sf.PdfUriAnnotation(
            bounds: const Rect.fromLTWH(20, 30, 180, 24),
            uri: 'https://doi.org/10.1000/page-$i',
          ),
        );
      }
      final source = Uint8List.fromList(await document.save());
      document.dispose();
      for (final selection in [
        [0, 2],
        [0],
        [2],
      ]) {
        final result = sf.PdfDocument(
          inputBytes: await PdfEditing.extract([source], pageOrder: selection),
        );
        try {
          expect(result.pages.count, selection.length);
          for (var i = 0; i < selection.length; i++) {
            expect(result.pages[i].annotations.count, 1);
            expect(
              (result.pages[i].annotations[0] as sf.PdfUriAnnotation).uri,
              'https://doi.org/10.1000/page-${selection[i]}',
            );
          }
        } finally {
          result.dispose();
        }
      }
    },
  );
  test(
    'internal citations still reach a retained page after extraction',
    () async {
      final document = sf.PdfDocument();
      final first = document.pages.add();
      document.pages.add();
      final references = document.pages.add();
      first.annotations.add(
        sf.PdfDocumentLinkAnnotation(
          const Rect.fromLTWH(20, 30, 100, 24),
          sf.PdfDestination(references),
        ),
      );
      final source = Uint8List.fromList(await document.save());
      document.dispose();
      final result = sf.PdfDocument(
        inputBytes: await PdfEditing.extract([source], pageOrder: [0, 2]),
      );
      try {
        final link =
            result.pages[0].annotations[0] as sf.PdfDocumentLinkAnnotation;
        expect(link.destination, isNotNull);
        expect(link.destination!.page, same(result.pages[1]));
      } finally {
        result.dispose();
      }
    },
  );
}
