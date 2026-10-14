import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:documentz/data/pdf_export.dart';

void main() {
  test(
    'Word export retains Unicode and page boundaries in valid XML parts',
    () {
      final archive = ZipDecoder().decodeBytes(
        PdfExport.wordText(['Hello & <world>\nবাংলা', 'Second page']),
      );
      for (final file in archive.files.where(
        (f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'),
      )) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content)),
          returnsNormally,
        );
      }
      final document = XmlDocument.parse(
        utf8.decode(archive.findFile('word/document.xml')!.content),
      );
      expect(
        document.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 't')
            .map((e) => e.innerText),
        ['Hello & <world>', 'বাংলা', 'Second page'],
      );
      final pageBreak = document.descendants
          .whereType<XmlElement>()
          .singleWhere((e) => e.name.local == 'br');
      expect(pageBreak.attributes.single.value, 'page');
      expect(archive.findFile('_rels/.rels'), isNotNull);
    },
  );
  test(
    'Excel export retains page and line columns and treats formulas as text',
    () {
      final archive = ZipDecoder().decodeBytes(
        PdfExport.excelText(['=SUM(A1)\nText & more', 'Third line']),
      );
      for (final file in archive.files.where(
        (f) => f.name.endsWith('.xml') || f.name.endsWith('.rels'),
      )) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content)),
          returnsNormally,
        );
      }
      final sheet = XmlDocument.parse(
        utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content),
      );
      expect(sheet.findAllElements('row'), hasLength(4));
      expect(sheet.findAllElements('t').map((e) => e.innerText), [
        'Page',
        'Line',
        'Text',
        '1',
        '1',
        '=SUM(A1)',
        '1',
        '2',
        'Text & more',
        '2',
        '1',
        'Third line',
      ]);
      expect(sheet.findAllElements('f'), isEmpty);
      expect(
        sheet
            .findAllElements('c')
            .every((e) => e.getAttribute('t') == 'inlineStr'),
        isTrue,
      );
    },
  );
  test('image-only documents require OCR before text conversion', () {
    expect(() => PdfExport.wordText(['']), throwsFormatException);
    expect(() => PdfExport.excelText([' ']), throwsFormatException);
  });
}
