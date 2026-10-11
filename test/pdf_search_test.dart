import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/features/pdf_navigation.dart';
import 'package:documentz/features/epub_reader.dart';

class _TextPage implements PdfPage {
  _TextPage(this.pageNumber, this.text);
  @override
  final int pageNumber;
  final String text;
  int loads = 0;
  @override
  Future<PdfPageRawText?> loadText() async { loads++; return PdfPageRawText(text, []); }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('PDF search streams all matches, keeps page offsets, and reuses its text cache', () async {
    final pages = [_TextPage(1, 'Find word, WORD again'), _TextPage(2, 'Another word')];
    final index = PdfTextIndex();
    final hits = await index.search(pages, 'word', () => false).toList();
    expect(hits.map((h) => h.page), [1, 1, 2]);
    expect(hits.first.start, 5);
    expect(hits.first.end, 9);
    expect((await index.search(pages, 'another', () => false).toList()).single.page, 2);
    expect(pages.map((p) => p.loads), [1, 1]);
  });
  test('PDF search stops loading pages when canceled', () async {
    final pages = [_TextPage(1, 'word'), _TextPage(2, 'word')];
    final index = PdfTextIndex();
    bool canceled = false;
    final hits = <PdfSearchHit>[];
    await for (final hit in index.search(pages, 'word', () => canceled)) { hits.add(hit); canceled = true; }
    expect(hits, hasLength(1));
    expect(pages.last.loads, 0);
  });
  test('EPUB search indexes rendered chapter text without HTML attributes', () {
    final text = indexEpubText(['<p>Hello <strong>world</strong></p><img src="secret-file.jpg">', '<p>Next chapter</p>']);
    expect(text, ['Hello world', 'Next chapter']);
    expect(text.first, isNot(contains('secret-file')));
  });
}
