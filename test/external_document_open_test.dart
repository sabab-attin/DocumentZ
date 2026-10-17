import 'dart:io';

import 'package:documentz/data/external_document_import.dart';
import 'package:documentz/data/local_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late LocalLibrary library;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('documentz-open-test-');
    library = LocalLibrary(directory: Directory('${root.path}/library'));
  });
  tearDown(() async => root.delete(recursive: true));

  test(
    'opening an identical file under another name reuses its book identity',
    () async {
      final original = await library.importDocument(
        'first.txt',
        Stream.value('A saved document'.codeUnits),
      );
      final incoming = await File('${root.path}/incoming.txt')
          .writeAsString('A saved document');
      final opened = await importExternalDocument(
        library,
        'renamed.txt',
        incoming.path,
      );
      expect(
        opened.id,
        original.id,
        reason: 'Bookmarks, marks and position belong to the existing book ID.',
      );
      expect(await library.listBooks(), hasLength(1));
    },
  );

  test(
    'same filename and byte length cannot reuse different document content',
    () async {
      final original = await library.importDocument(
        'note.txt',
        Stream.value('first'.codeUnits),
      );
      final incoming = await File('${root.path}/incoming.txt')
          .writeAsString('other');
      final opened = await importExternalDocument(
        library,
        'note.txt',
        incoming.path,
      );
      expect(opened.id, isNot(original.id));
      expect(await library.readDocument(original), 'first'.codeUnits);
      expect(await library.listBooks(), hasLength(2));
    },
  );

  test('external opening retains existing malformed-file checks', () async {
    final incoming = await File('${root.path}/broken.pdf')
        .writeAsString('This is not a PDF');
    await expectLater(
      importExternalDocument(library, 'broken.pdf', incoming.path),
      throwsFormatException,
    );
    expect(await library.listBooks(), isEmpty);
  });
}
