import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

import 'package:documentz/data/edit_output.dart';
import 'package:documentz/data/edit_output_storage_io.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/data/recent_documents.dart';
import 'package:documentz/domain/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class _RetryLibrary extends BrowserLibrary {
  bool fail = true;
  @override
  Future<Book> importDocument(String name, Stream<List<int>> contents) async {
    if (fail) {
      fail = false;
      throw StateError('Library temporarily unavailable');
    }
    return super.importDocument(name, contents);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List bytes;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    RecentDocuments.instance.resetForTests();
    final pdf = sf.PdfDocument();
    pdf.pages.add();
    bytes = Uint8List.fromList(await pdf.save());
    pdf.dispose();
  });

  test(
    'public storage must finish before files enter Library and Recent',
    () async {
      final library = BrowserLibrary();
      final written = Completer<List<String>>();
      var writes = 0;
      final saver = EditOutputSaver(
        library,
        writer: (outputs) {
          writes++;
          return written.future;
        },
      );
      final outputs = [
        EditedOutput('Page 1.pdf', bytes),
        EditedOutput('Page 3.pdf', bytes),
      ];
      final first = saver.save(outputs);
      final second = saver.save(outputs);
      expect(await library.listBooks(), isEmpty);
      expect(RecentDocuments.instance.accessed, isEmpty);
      written.complete(['/downloads/Page 1.pdf', '/downloads/Page 3.pdf']);
      await Future.wait([first, second]);
      expect(writes, 1);
      final books = await library.listBooks();
      expect(books, hasLength(2));
      expect(
        RecentDocuments.instance.accessed.keys,
        unorderedEquals(books.map((book) => book.id)),
      );
      final persisted = RecentDocuments();
      await persisted.load();
      expect(
        persisted.accessed.keys,
        unorderedEquals(books.map((book) => book.id)),
      );
      persisted.dispose();
    },
  );

  test(
    'a failed public save does not claim success or create Recent entries',
    () async {
      final library = BrowserLibrary();
      var writes = 0;
      final saver = EditOutputSaver(
        library,
        writer: (_) async {
          if (++writes == 1) {
            throw const FileSystemException('Disk full');
          }
          return ['/downloads/Edited.pdf'];
        },
      );
      final outputs = [EditedOutput('Edited.pdf', bytes)];
      await expectLater(
        saver.save(outputs),
        throwsA(isA<FileSystemException>()),
      );
      expect(await library.listBooks(), isEmpty);
      expect(RecentDocuments.instance.accessed, isEmpty);
      await saver.save(outputs);
      expect(writes, 2);
      expect(RecentDocuments.instance.accessed, hasLength(1));
    },
  );

  test('retry after a library error reuses the public file instead of duplicating it', () async {
    final library = _RetryLibrary();
    var writes = 0;
    final saver = EditOutputSaver(
      library,
      writer: (_) async {
        writes++;
        return ['/downloads/Edited.pdf'];
      },
    );
    final outputs = [EditedOutput('Edited.pdf', bytes)];
    await expectLater(saver.save(outputs), throwsStateError);
    await saver.save(outputs);
    expect(writes, 1);
    expect(await library.listBooks(), hasLength(1));
    expect(RecentDocuments.instance.accessed, hasLength(1));
  });

  test(
    'public copies never overwrite an existing file with the same name',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'documentz-output-test-',
      );
      addTearDown(() async {
        await root.delete(recursive: true);
      });
      final first = await saveEditedOutputsToDirectory([
        EditedOutput('Paper.pdf', bytes),
      ], root);
      final next = await saveEditedOutputsToDirectory([
        EditedOutput('Paper.pdf', bytes),
      ], root);
      expect(next.single, isNot(first.single));
      expect(await File(first.single).readAsBytes(), bytes);
      expect(await File(next.single).readAsBytes(), bytes);
      final before = await Directory('${root.path}/DocumentZ').list().length;
      await expectLater(
        saveEditedOutputsToDirectory([
          EditedOutput('Temporary.pdf', bytes),
          EditedOutput('..', bytes),
        ], root),
        throwsFormatException,
      );
      expect(
        await Directory('${root.path}/DocumentZ').list().length,
        before,
        reason:
            'Only this failed batch is removed; previous public files survive.',
      );
    },
  );
}
