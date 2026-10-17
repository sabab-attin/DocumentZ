import '../domain/book.dart';
import '../domain/services.dart';

Future<Book> importExternalDocument(
  ImportableLibrary library,
  String name,
  String path,
) => throw UnsupportedError('External document opening is not available here.');
