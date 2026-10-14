import '../domain/book.dart';
import 'document_file_info_stub.dart'
    if (dart.library.io) 'document_file_info_io.dart'
    as platform;

class DocumentFileInfo {
  const DocumentFileInfo({this.size, this.modified});
  final int? size, modified;
}

Future<Map<String, DocumentFileInfo>> documentFileInfo(List<Book> books) =>
    platform.documentFileInfo(books);
