import 'dart:typed_data';

import 'book.dart';

/// Implement with SQLite without coupling screens to database queries.
abstract interface class LibraryRepository {
  Future<List<Book>> listBooks();
  Future<void> savePosition(ReadingPosition position);
  Future<ReadingPosition?> positionFor(String bookId);
}

abstract interface class ImportableLibrary implements LibraryRepository {
  bool get persistsFiles;
  Future<Book> importDocument(String name, Stream<List<int>> contents);
  Future<Uint8List> readDocument(Book book);
}

abstract interface class MutableLibrary implements ImportableLibrary {
  Future<void> renameDocument(Book book, String title);
  Future<void> deleteDocument(Book book);
}

/// Future Supabase implementation owns authentication and conflict handling.
abstract interface class SyncService {
  Future<void> synchronize();
}

class DocumentAnswer {
  const DocumentAnswer(this.text, this.sourceLocators);
  final String text;
  final List<String> sourceLocators;
}

/// Future retrieval implementation returns cited document locations.
abstract interface class RetrievalService {
  Future<DocumentAnswer> ask(Book book, String question);
}

class MemoryLibrary implements LibraryRepository {
  final Map<String, ReadingPosition> _positions = {};
  @override
  Future<List<Book>> listBooks() async => const [];
  @override
  Future<void> savePosition(ReadingPosition position) async {
    _positions[position.bookId] = position;
  }

  @override
  Future<ReadingPosition?> positionFor(String bookId) async =>
      _positions[bookId];
}
