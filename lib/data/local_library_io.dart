import 'library_changes.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'app_storage_io.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'import_validation.dart';

ImportableLibrary createLibrary() => LocalLibrary();

class LocalLibrary implements MutableLibrary {
  LocalLibrary({this.directory});
  final Directory? directory;
  Directory? _directory;
  final MemoryLibrary _positions = MemoryLibrary();
  @override
  bool get persistsFiles => true;

  Future<Directory> _root() async {
    _directory ??= directory ?? await applicationLibraryDirectory();
    await _directory!.create(recursive: true);
    return _directory!;
  }

  @override
  Future<List<Book>> listBooks() async {
    final root = await _root();
    final books = <Book>[];
    await for (final entry in root.list()) {
      if (entry is! Directory || p.basename(entry.path).startsWith('.')) {
        continue;
      }
      final meta = File(p.join(entry.path, 'book.json'));
      if (!await meta.exists()) continue;
      // Fail visibly rather than silently hiding a damaged library index.
      final json =
          jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final format = BookFormat.values.byName(json['format'] as String);
      if (!await File(p.join(entry.path, 'document.${format.name}')).exists()) {
        continue;
      }
      books.add(
        Book(
          id: p.basename(entry.path),
          title: json['title'] as String,
          format: format,
          localPath: p.join(entry.path, 'document.${format.name}'),
        ),
      );
    }
    books.sort((a, b) => b.id.compareTo(a.id));
    return books;
  }

  @override
  Future<Book> importDocument(String name, Stream<List<int>> contents) async {
    final format = importFormat(name);
    final root = await _root();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final temporary = Directory(p.join(root.path, '.importing-$id'));
    await temporary.create();
    final payload = File(p.join(temporary.path, 'document.${format.name}'));
    final sink = payload.openWrite();
    final header = <int>[];
    int size = 0;
    try {
      // addStream honors backpressure and propagates disk errors to this future.
      await sink.addStream(
        contents.map((chunk) {
          size += chunk.length;
          if (header.length < 1024) {
            header.addAll(chunk.take(1024 - header.length));
          }
          return chunk;
        }),
      );
      await sink.flush();
      await sink.close();
      validateDocumentHeader(format, header, size);
      await File(p.join(temporary.path, 'book.json')).writeAsString(
        jsonEncode({'title': documentTitle(name), 'format': format.name}),
        flush: true,
      );
      final finalDirectory = await temporary.rename(p.join(root.path, id));
      return Book(
        id: id,
        title: documentTitle(name),
        format: format,
        localPath: p.join(finalDirectory.path, 'document.${format.name}'),
      );
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        /* Preserve original error. */
      }
      try {
        await temporary.delete(recursive: true);
      } catch (_) {
        /* Incomplete imports are hidden. */
      }
      rethrow;
    }
  }

  Future<Directory> _checkedBookDirectory(Book book) async {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(book.id)) {
      throw const FormatException('Invalid document identity.');
    }
    final root = await _root();
    final realRoot = await root.resolveSymbolicLinks();
    final directory = Directory(p.join(realRoot, book.id));
    final resolved = await directory.resolveSymbolicLinks();
    if (!p.isWithin(realRoot, resolved)) {
      throw const FormatException('Document is outside the library.');
    }
    return Directory(resolved);
  }

  @override
  Future<void> renameDocument(Book book, String title) async {
    if (title.trim().isEmpty) {
      throw const FormatException('Enter a document name.');
    }
    final folder = await _checkedBookDirectory(book);
    final meta = File(p.join(folder.path, 'book.json'));
    final data = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
    data['title'] = title.trim();
    final temporary = File(p.join(folder.path, 'book-renaming.json'));
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(meta.path);
    LibraryChanges.instance.changed();
  }

  @override
  Future<void> deleteDocument(Book book) async {
    final folder = await _checkedBookDirectory(book);
    // Delete the payload first, so an in-use file cannot leave a broken index.
    await File(p.join(folder.path, 'document.${book.format.name}')).delete();
    try {
      await folder.delete(recursive: true);
    } on FileSystemException {
      // An empty metadata folder is ignored by listBooks and can be cleaned later.
    }
    LibraryChanges.instance.changed();
  }

  @override
  Future<Uint8List> readDocument(Book book) =>
      File(book.localPath!).readAsBytes();
  @override
  Future<void> savePosition(ReadingPosition position) =>
      _positions.savePosition(position);
  @override
  Future<ReadingPosition?> positionFor(String bookId) =>
      _positions.positionFor(bookId);
}
