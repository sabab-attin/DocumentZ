import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/data/document_links.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/data/word_lookup.dart';

void main() {
  const book = EpubDocumentData('Book', [
    EpubSection('OEBPS/one.xhtml', 'One', ''),
    EpubSection('OEBPS/notes.xhtml', 'Notes', ''),
  ], {});
  test(
    'ebook links resolve same-chapter, relative and encoded destinations',
    () {
      expect(resolveEbookLink(book, 'OEBPS/one.xhtml', '#fig-1'), (
        section: 0,
        fragment: 'fig-1',
      ));
      expect(
        resolveEbookLink(book, 'OEBPS/one.xhtml', 'notes.xhtml#note%201'),
        (section: 1, fragment: 'note 1'),
      );
      expect(
        resolveEbookLink(book, 'OEBPS/one.xhtml', '../OEBPS/notes.xhtml#ref'),
        (section: 1, fragment: 'ref'),
      );
      expect(
        resolveEbookLink(book, 'OEBPS/one.xhtml', 'missing.xhtml#ref'),
        isNull,
      );
      expect(
        resolveEbookLink(book, 'OEBPS/one.xhtml', 'javascript:alert(1)'),
        isNull,
      );
    },
  );
  test('PDF citation destinations retain exact coordinates', () async {
    const destination = PdfDest(7, PdfDestCommand.xyz, [12, 144, null]);
    PdfDest? received;
    var external = false;
    final opened = await followPdfLink(
      const PdfLink([], dest: destination),
      goToDestination: (dest) async {
        received = dest;
        return true;
      },
      openExternal: (_) async {
        external = true;
        return true;
      },
    );
    expect(opened, isTrue);
    expect(received, destination);
    expect(external, isFalse);
  });
  test('PDF web links and page fragments take the correct route', () async {
    Uri? received;
    await followPdfLink(
      PdfLink(const [], url: Uri.parse('https://example.com/paper#section')),
      goToDestination: (_) async => false,
      openExternal: (url) async {
        received = url;
        return true;
      },
    );
    expect(received.toString(), 'https://example.com/paper#section');
    PdfDest? page;
    expect(
      await followPdfLink(
        PdfLink(const [], url: Uri.parse('#page=4')),
        goToDestination: (dest) async {
          page = dest;
          return true;
        },
      ),
      isTrue,
    );
    expect(page!.pageNumber, 4);
  });
  test(
    'an invalid PDF destination fails without throwing into the reader',
    () async {
      expect(
        await followPdfLink(
          const PdfLink([], dest: PdfDest(999, PdfDestCommand.fit, null)),
          goToDestination: (_) async => throw StateError('Missing page'),
        ),
        isFalse,
      );
    },
  );
  test('unsafe document links do not launch an application', () async {
    var called = false;
    expect(
      await followPdfLink(
        PdfLink(const [], url: Uri.parse('file:///private/path')),
        goToDestination: (_) async => false,
        openExternal: (_) async {
          called = true;
          return true;
        },
      ),
      isFalse,
    );
    expect(called, isFalse);
  });
  test('word lookup encodes only the deliberately selected phrase', () {
    final url = wordLookupUri('  déjà vu & meaning  ');
    expect(url.scheme, 'https');
    expect(url.host, 'www.google.com');
    expect(url.queryParameters['q'], 'define déjà vu & meaning');
  });
  test(
    'empty and long lookup selections require no browser or connection',
    () async {
      expect(await lookupSelectedWord(''), isFalse);
      expect(await lookupSelectedWord(List.filled(200, 'x').join()), isFalse);
    },
  );
}
