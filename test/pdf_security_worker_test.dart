import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:documentz/data/pdf_editing.dart';
import 'package:documentz/data/pdf_security_worker.dart';

void main() {
  test('background encryption preserves source bytes and requires the opening password', () async {
    final source = await PdfEditing.create(
      'Security test',
      'Keep this document content',
    );
    final original = Uint8List.fromList(source);
    expect(await pdfPageCountInBackground(source), 1);
    final secured = await encryptPdfInBackground(
      source,
      'open-pass',
      'owner-pass',
      '',
    );
    expect(source, orderedEquals(original));
    expect(
      () => sf.PdfDocument(inputBytes: secured, password: 'incorrect'),
      throwsA(anything),
    );
    final document = sf.PdfDocument(inputBytes: secured, password: 'open-pass');
    try {
      expect(
        sf.PdfTextExtractor(document)
            .extractText()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim(),
        contains('Keep this document content'),
      );
    } finally {
      document.dispose();
    }
    final clean = await unlockPdfInBackground(secured, 'open-pass');
    expect(await pdfPageCountInBackground(clean), 1);
    expect(secured, isNot(orderedEquals(clean)));
  });
  test(
    'background encryption rejects invalid passwords without touching source',
    () async {
      final source = await PdfEditing.create(
        'Security test',
        'Original content',
      );
      final original = Uint8List.fromList(source);
      for (final pair in [('', 'owner'), ('open', ''), ('same', 'same')]) {
        await expectLater(
          encryptPdfInBackground(source, pair.$1, pair.$2, ''),
          throwsA(anything),
        );
      }
      expect(source, orderedEquals(original));
    },
  );
}
