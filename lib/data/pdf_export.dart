import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

String _xml(String value) => value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '')
  .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
void _part(Archive archive, String name, String xml) {
  final bytes = utf8.encode(xml);
  archive.addFile(ArchiveFile(name, bytes.length, bytes));
}

List<String> _extract(Uint8List bytes) {
  final document = sf.PdfDocument(inputBytes: bytes);
  try {
    final extractor = sf.PdfTextExtractor(document);
    return [for (int i = 0; i < document.pages.count; i++) extractor.extractText(startPageIndex: i, endPageIndex: i, layoutText: true)];
  } finally { document.dispose(); }
}

class PdfExport {
  static Future<Uint8List> word(Uint8List bytes) async => wordText(await compute(_extract, bytes));
  static Future<Uint8List> excel(Uint8List bytes) async => excelText(await compute(_extract, bytes));
  static Uint8List wordText(List<String> pages) {
    if (pages.every((p) => p.trim().isEmpty)) throw const FormatException('No searchable text. Run OCR first.');
    final archive = Archive();
    _part(archive, '[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>');
    _part(archive, '_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>');
    final body = StringBuffer();
    for (int i = 0; i < pages.length; i++) {
      if (i > 0) body.write('<w:p><w:r><w:br w:type="page"/></w:r></w:p>');
      for (final line in pages[i].split(RegExp(r'\r?\n'))) {
        body.write('<w:p><w:r><w:t xml:space="preserve">${_xml(line)}</w:t></w:r></w:p>');
      }
    }
    _part(archive, 'word/document.xml', '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>$body<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:bottom="1440" w:left="1440" w:right="1440"/></w:sectPr></w:body></w:document>');
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
  static Uint8List excelText(List<String> pages) {
    if (pages.every((p) => p.trim().isEmpty)) throw const FormatException('No searchable text. Run OCR first.');
    final archive = Archive();
    _part(archive, '[Content_Types].xml', '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>');
    _part(archive, '_rels/.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>');
    _part(archive, 'xl/workbook.xml', '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Document text" sheetId="1" r:id="rId1"/></sheets></workbook>');
    _part(archive, 'xl/_rels/workbook.xml.rels', '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>');
    final rows = StringBuffer();
    int row = 1;
    void add(List<String> cells) {
      rows.write('<row r="$row">');
      for (int c = 0; c < cells.length; c++) {
        rows.write('<c r="${String.fromCharCode(65 + c)}$row" t="inlineStr"><is><t xml:space="preserve">${_xml(cells[c])}</t></is></c>');
      }
      rows.write('</row>'); row++;
    }
    add(['Page', 'Line', 'Text']);
    for (int p = 0; p < pages.length; p++) {
      final lines = pages[p].split(RegExp(r'\r?\n'));
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trim().isEmpty) continue;
        if (row > 1048576 || lines[i].length > 32767) throw const FormatException('Document exceeds Excel row or cell limits.');
        add(['${p + 1}', '${i + 1}', lines[i]]);
      }
    }
    _part(archive, 'xl/worksheets/sheet1.xml', '<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><cols><col min="1" max="2" width="10" customWidth="1"/><col min="3" max="3" width="100" customWidth="1"/></cols><sheetData>$rows</sheetData></worksheet>');
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
  static Future<Uint8List> images(Uint8List bytes, ValueChanged<int> progress) async {
    final archive = Archive();
    int page = 0, total = 0;
    await for (final raster in Printing.raster(bytes, dpi: 144)) {
      final png = await raster.toPng();
      total += png.length;
      if (total > 200 * 1024 * 1024) throw const FormatException('Export is larger than 200 MB. Extract fewer pages first.');
      page++;
      archive.addFile(ArchiveFile('page_${page.toString().padLeft(4, '0')}.png', png.length, png));
      progress(page);
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
