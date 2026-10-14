import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/local_library_io.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/data/document_picker.dart';
import 'package:documentz/features/library.dart';

void main() {
  late Directory root;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('documentz_test_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test(
    'imports stream into owned storage and survive repository recreation',
    () async {
      final repository = LocalLibrary(directory: root);
      final bytes = utf8.encode('%PDF-1.7\nfixture');
      final book = await repository.importDocument(
        'My book.PDF',
        Stream.value(bytes),
      );
      expect(book.title, 'My book');
      expect(await File(book.localPath!).readAsBytes(), bytes);
      final reloaded = await LocalLibrary(directory: root).listBooks();
      expect(reloaded.first.id, book.id);
      expect(reloaded.first.localPath, book.localPath);
      final duplicate = await repository.importDocument(
        'My book.PDF',
        Stream.value(bytes),
      );
      expect(duplicate.localPath, isNot(book.localPath));
    },
  );

  test(
    'failed stream and invalid file do not become library entries',
    () async {
      final repository = LocalLibrary(directory: root);
      Stream<List<int>> interrupted() async* {
        yield utf8.encode('%PDF-1.7');
        throw const FileSystemException('Read interrupted');
      }

      await expectLater(
        repository.importDocument('broken.pdf', interrupted()),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        repository.importDocument('wrong.pdf', Stream.value([1, 2, 3])),
        throwsFormatException,
      );
      expect(await root.list().toList(), isEmpty);
      expect(
        (await repository.listBooks()).every((b) => b.localPath == null),
        isTrue,
      );
    },
  );

  test(
    'EPUB remains readable after import and repository recreation',
    () async {
      final repository = LocalLibrary(directory: root);
      final imported = await repository.importDocument(
        'A first chapter.epub',
        File('test/fixtures/sample.epub').openRead(),
      );
      final restored = (await LocalLibrary(directory: root).listBooks()).first;
      expect(restored.id, imported.id);
      final document = parseEpub(await repository.readDocument(restored));
      expect(document.title, 'Quiet Reader test book');
      expect(document.sections, isNotEmpty);
      expect(document.sections.first.html, contains('This EPUB opens locally'));
    },
  );

  test(
    'EPUB resource paths resolve relative folders and encoded filenames',
    () {
      expect(
        epubResourcePath(
          'OEBPS/Text/chapter.xhtml',
          '../Images/cover%20art.png',
        ),
        'OEBPS/Images/cover art.png',
      );
      expect(
        epubResourcePath('OEBPS/Text/chapter.xhtml', 'second.xhtml#heading'),
        'OEBPS/Text/second.xhtml',
      );
      expect(
        epubResourcePath(
          'OEBPS/Text/chapter.xhtml',
          'https://example.com/image.png',
        ),
        '',
      );
    },
  );

  test('EPUB images resolve encoded paths, archive-root references, case variants and embedded data', () {
    final book = EpubDocumentData('Images', [], {
      'OPS/Images/cover art.png': Uint8List.fromList([1, 2, 3]),
    });
    for (final reference in [
      '../Images/cover%20art.png',
      '/OPS/Images/cover%20art.png',
      '../images/COVER%20ART.PNG',
      r'..\Images\cover%20art.png',
    ]) {
      expect(
        epubImageResource(book, 'OPS/Text/chapter.xhtml', reference)?.bytes,
        [1, 2, 3],
      );
    }
    expect(
      epubImageResource(
        book,
        'OPS/Text/chapter.xhtml',
        'data:image/png;base64,AQID',
      )?.bytes,
      [1, 2, 3],
    );
    expect(
      epubImageResource(
        book,
        'OPS/Text/chapter.xhtml',
        'https://example.com/image.png',
      ),
      isNull,
    );
    expect(
      epubImageResource(
        book,
        'OPS/Text/chapter.xhtml',
        '../Images/missing.png',
      ),
      isNull,
    );
    final markup = epubSvgMarkup(
      book,
      'OPS/Text/cover.xhtml',
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><image href="../Images/cover%20art.png" width="100" height="100"/></svg>',
    );
    expect(markup, contains('data:image/png;base64,AQID'));
    expect(markup, contains('viewBox="0 0 100 100"'));
  });

  testWidgets(
    'picker cancellation is harmless; successful import refreshes library',
    (tester) async {
      final repository = BrowserLibrary();
      var cancelled = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryScreen(
              repository: repository,
              preferences: ReaderPreferences(),
              coverLoader: (_, _) async => null,
              picker: () async => cancelled
                  ? null
                  : PickedDocument(
                      'Phone book.pdf',
                      () => Stream.value(utf8.encode('%PDF-1.7\nfixture')),
                    ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Add document'));
      await tester.pumpAndSettle();
      expect(find.text('Phone book'), findsNothing);
      cancelled = false;
      await tester.tap(find.text('Add document'));
      await tester.pumpAndSettle();
      expect(find.text('Phone book'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
