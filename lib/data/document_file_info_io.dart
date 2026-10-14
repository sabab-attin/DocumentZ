import 'dart:io';

import '../domain/book.dart';
import 'document_file_info.dart';

Future<Map<String, DocumentFileInfo>> documentFileInfo(List<Book> books) async {
  final result = <String, DocumentFileInfo>{};
  for (final book in books) {
    final location = book.localPath;
    if (location == null) continue;
    try {
      final stat = await File(location).stat();
      if (stat.type == FileSystemEntityType.file) {
        result[book.id] = DocumentFileInfo(
          size: stat.size,
          modified: stat.modified.millisecondsSinceEpoch,
        );
      }
    } on FileSystemException {
      /* Some providers do not expose file metadata. */
    }
  }
  return result;
}
