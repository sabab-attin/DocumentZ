import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/local_library_io.dart';

void main() {
  test('disk import streams beyond the former 100 MB cap', () async {
    final directory = await Directory.systemTemp.createTemp(
      'documentz_large_import_',
    );
    try {
      final library = LocalLibrary(directory: directory);
      final header = utf8.encode('%PDF-1.7\n');
      final chunk = Uint8List(1024 * 1024);
      Stream<List<int>> contents() async* {
        yield header;
        for (var i = 0; i < 101; i++) {
          yield chunk;
        }
      }

      final book = await library.importDocument('large.pdf', contents());
      expect(
        await File(book.localPath!).length(),
        header.length + 101 * chunk.length,
      );
      expect((await library.listBooks()).single.id, book.id);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
