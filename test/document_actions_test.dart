import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/local_library_io.dart';

void main() {
  test(
    'rename keeps identity and bytes; delete removes the imported copy',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'documentz-actions-',
      );
      try {
        final library = LocalLibrary(directory: temporary);
        final input = utf8.encode('Readable text with spaces.');
        final book = await library.importDocument(
          'original.txt',
          Stream.value(input),
        );
        await library.renameDocument(book, 'Renamed');
        final renamed = (await library.listBooks()).single;
        expect(renamed.id, book.id);
        expect(renamed.title, 'Renamed');
        expect(await library.readDocument(renamed), input);
        await library.deleteDocument(renamed);
        expect(await library.listBooks(), isEmpty);
      } finally {
        await temporary.delete(recursive: true);
      }
    },
  );
}
