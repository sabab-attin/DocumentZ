import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:documentz/domain/book.dart';
import 'package:documentz/data/import_validation.dart';
import 'package:documentz/data/readable_document.dart';
import 'package:documentz/data/image_document.dart';
import 'package:documentz/data/local_library_web.dart';

Uint8List zipped(Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
// Two uncompressed grayscale IFDs linked by their next-IFD pointers. Construct
// the fixture directly: the image package's encoder emitted only its first frame.
Uint8List twoPageTiff() {
  const ifdSize = 2 + 9 * 12 + 4;
  const pixelStart = 8 + 2 * ifdSize;
  final data = ByteData(pixelStart + 12);
  data.setUint8(0, 73); data.setUint8(1, 73);
  data.setUint16(2, 42, Endian.little);
  data.setUint32(4, 8, Endian.little);
  for (int page = 0; page < 2; page++) {
    final offset = 8 + page * ifdSize;
    final width = page == 0 ? 2 : 3;
    final height = page == 0 ? 3 : 2;
    final fields = <(int, int, int)>[
      (256, 4, width), (257, 4, height), (258, 3, 8), (259, 3, 1),
      (262, 3, 1), (273, 4, pixelStart + page * 6), (277, 3, 1), (278, 4, height), (279, 4, 6),
    ];
    data.setUint16(offset, fields.length, Endian.little);
    for (int i = 0; i < fields.length; i++) {
      final field = offset + 2 + i * 12;
      data.setUint16(field, fields[i].$1, Endian.little);
      data.setUint16(field + 2, fields[i].$2, Endian.little);
      data.setUint32(field + 4, 1, Endian.little);
      data.setUint32(field + 8, fields[i].$3, Endian.little);
    }
    data.setUint32(offset + 2 + fields.length * 12, page == 0 ? 8 + ifdSize : 0, Endian.little);
    for (int i = 0; i < 6; i++) { data.setUint8(pixelStart + page * 6 + i, page == 0 ? 90 : 180); }
  }
  return data.buffer.asUint8List();
}
void main() {
  test('every requested extension has an import route and case-insensitive lookup', () {
    for (final extension in documentExtensions) { expect(() => importFormat('Document.${extension.toUpperCase()}'), returnsNormally); }
    expect(() => importFormat('script.exe'), throwsFormatException);
    expect(() => validateDocumentHeader(BookFormat.docx, [1, 2, 3, 4], 4), throwsFormatException);
  });
  test('new formats import and share their original bytes rather than becoming renamed PDFs', () async {
    final library = BrowserLibrary();
    for (final name in ['notes.txt', 'page.html', 'drawing.svg', 'scan.tif']) {
      final bytes = Uint8List.fromList(utf8.encode('Original data for $name'));
      final book = await library.importDocument(name, Stream.value(bytes));
      expect(await library.readDocument(book), bytes);
      expect(book.format, importFormat(name));
    }
  });
  test('plain text escapes markup and Markdown retains headings, lists, and emphasis', () {
    final text = parseReadableDocument((BookFormat.txt, Uint8List.fromList(utf8.encode('<not html>'))));
    expect(text.sections.single.html, contains('&lt;not html&gt;'));
    final markdown = parseReadableDocument((BookFormat.markdown, Uint8List.fromList(utf8.encode('# Title\n\n* **Bold**'))));
    expect(markdown.sections.single.html, contains('<h1>Title</h1>'));
    expect(markdown.sections.single.html, contains('<strong>Bold</strong>'));
    expect(decodeDocumentText(Uint8List.fromList([255, 254, 65, 0, 66, 0])), 'AB');
  });
  test('RTF Unicode, escaped characters and destination skipping preserve readable text', () {
    expect(rtfText(r'{\rtf1\ansi{\fonttbl{\f0 Hidden;}}Hello \u945?\par World \{ok\}}'), 'Hello α\nWorld {ok}');
    expect(() => rtfText('not rtf'), throwsFormatException);
  });
  test('DOCX preserves paragraphs, basic styles and table content', () {
    final bytes = zipped({'word/document.xml': '''<w:document xmlns:w="urn:word"><w:body>
      <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>Bold text</w:t></w:r></w:p>
      <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
      </w:body></w:document>'''});
    final book = parseReadableDocument((BookFormat.docx, bytes));
    expect(book.sections.single.html, contains('<b>Bold text</b>'));
    expect(book.sections.single.html, contains('<td><p>Cell</p></td>'));
  });
  test('XLSX resolves shared strings and keeps sparse cell columns', () {
    final bytes = zipped({
      'xl/workbook.xml': '<workbook xmlns:r="urn:rels"><sheets><sheet name="Budget" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<Relationships><Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/sharedStrings.xml': '<sst><si><t>Income</t></si></sst>',
      'xl/worksheets/sheet1.xml': '<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1"><v>120</v></c></row></sheetData></worksheet>',
    });
    final book = parseReadableDocument((BookFormat.xlsx, bytes));
    expect(book.sections.single.title, 'Budget');
    expect(book.sections.single.html, contains('<td>Income</td><td></td><td>120</td>'));
  });
  test('PPTX uses relationship IDs rather than numeric slide IDs and preserves deck order', () {
    final bytes = zipped({
      'ppt/presentation.xml': '<presentation xmlns:r="urn:rels"><sldIdLst><sldId id="256" r:id="rId2"/><sldId id="257" r:id="rId1"/></sldIdLst></presentation>',
      'ppt/_rels/presentation.xml.rels': '<Relationships><Relationship Id="rId1" Target="slides/slide1.xml"/><Relationship Id="rId2" Target="slides/slide2.xml"/></Relationships>',
      'ppt/slides/slide1.xml': '<slide><p><r><t>First file</t></r></p></slide>',
      'ppt/slides/slide2.xml': '<slide><p><r><t>First in deck</t></r></p></slide>',
    });
    final book = parseReadableDocument((BookFormat.pptx, bytes));
    expect(book.sections, hasLength(2));
    expect(book.sections.first.html, contains('First in deck'));
  });
  test('ODT, ODS and ODP expose text, sheets and slides respectively', () {
    final odt = parseReadableDocument((BookFormat.odt, zipped({'content.xml': '<document><body><text><h>Title</h><p>Words</p></text></body></document>'})));
    expect(odt.sections.single.html, contains('<p>Words</p>'));
    final ods = parseReadableDocument((BookFormat.ods, zipped({'content.xml': '<document><table name="Sheet"><table-row><table-cell number-columns-repeated="2"><p>Value</p></table-cell></table-row></table></document>'})));
    expect(ods.sections.single.html, contains('<td><p>Value</p></td><td><p>Value</p></td>'));
    final odp = parseReadableDocument((BookFormat.odp, zipped({'content.xml': '<document><page name="Slide"><p>Slide text</p></page></document>'})));
    expect(odp.sections.single.title, 'Slide');
  });
  test('MHTML resolves bundled image bytes and HTML strips active embedded content', () {
    const source = '''Content-Type: multipart/related; boundary="test"

--test
Content-Type: text/html
Content-Location: https://example.test/page.html

<p>Saved page</p><img src="photo.png"><script>unwanted</script>
--test
Content-Type: image/png
Content-Location: https://example.test/photo.png
Content-Transfer-Encoding: base64

AQID
--test--
''';
    final book = parseReadableDocument((BookFormat.mhtml, Uint8List.fromList(utf8.encode(source))));
    expect(book.sections.single.html, contains('src="mhtml-0"'));
    expect(book.sections.single.html, isNot(contains('unwanted')));
    expect(book.resources['mhtml-0'], [1, 2, 3]);
  });
  test('multi-page TIFF preserves every page and BMP becomes readable PNG', () {
    final image = img.Image(width: 2, height: 3);
    image.setPixelRgb(0, 0, 255, 0, 0);
    final pages = tiffPages(twoPageTiff());
    expect(pages, hasLength(2));
    expect(img.decodePng(pages.first)!.height, 3);
    expect(img.decodePng(pages.last)!.width, 3);
    expect(img.decodePng(pages.first)!.getPixel(0, 0).r, 90);
    expect(img.decodePng(pages.last)!.getPixel(0, 0).r, 180);
    expect(img.decodePng(bmpPage(img.encodeBmp(image)))!.width, 2);
  });
}
