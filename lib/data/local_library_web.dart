import 'dart:typed_data';
import 'dart:math';
import '../domain/book.dart';
import '../domain/services.dart';
import 'import_validation.dart';

ImportableLibrary createLibrary() => BrowserLibrary();

/// Browser preview imports last for this session; mobile/desktop use disk storage.
class BrowserLibrary implements ImportableLibrary {
  final MemoryLibrary _positions = MemoryLibrary();
  final Map<String, Uint8List> _data = {};
  final List<Book> _books = [];
  @override
  bool get persistsFiles => false;
  @override
  Future<List<Book>> listBooks() async => [..._books.reversed];
  @override
  Future<Book> importDocument(String name, Stream<List<int>> contents) async {
    final format = importFormat(name);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in contents) {
      if (builder.length + chunk.length > maxImportBytes) throw const FormatException('Choose a file smaller than 100 MB.');
      builder.add(chunk);
    }
    final data = builder.takeBytes();
    validateDocumentHeader(format, data.take(1024).toList(), data.length);
    final id = 'import-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final book = Book(id: id, title: documentTitle(name), format: format);
    _books.add(book);
    _data[id] = data;
    return book;
  }
  @override
  Future<Uint8List> readDocument(Book book) async => _data[book.id]!;
  @override
  Future<void> savePosition(ReadingPosition position) => _positions.savePosition(position);
  @override
  Future<ReadingPosition?> positionFor(String bookId) => _positions.positionFor(bookId);
}
