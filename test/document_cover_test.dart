import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/document_cover.dart';

Uint8List _epub({required bool version3}) {
  final files = <String, List<int>>{
    'META-INF/container.xml': utf8.encode('<container><rootfiles><rootfile full-path="OPS/book.opf"/></rootfiles></container>'),
    'OPS/book.opf': utf8.encode('''<package><metadata><title>Cover test</title>${version3 ? '' : '<meta name="cover" content="cover"/>'}</metadata>
      <manifest><item id="chapter" href="Text/chapter.xhtml"/>
      <item id="cover" href="Images/cover%20art.png" ${version3 ? 'properties="cover-image"' : ''}/></manifest>
      <spine><itemref idref="chapter"/></spine></package>'''),
    'OPS/Text/chapter.xhtml': utf8.encode('<html><body><h1>Chapter</h1><img src="../Images/logo.png"/></body></html>'),
    'OPS/Images/cover art.png': [1, 2, 3, 4],
    'OPS/Images/logo.png': [9, 8, 7],
  };
  final archive = Archive();
  for (final entry in files.entries) { archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value)); }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('EPUB 2 and EPUB 3 library covers use the declared cover instead of chapter artwork', () {
    expect(epubCover(_epub(version3: true)), [1, 2, 3, 4]);
    expect(epubCover(_epub(version3: false)), [1, 2, 3, 4]);
  });
}
