import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../domain/book.dart';
import '../domain/services.dart';
import 'import_validation.dart';

Future<String> _hash(String path) => Isolate.run(
  () async => (await sha256.bind(File(path).openRead()).first).toString(),
);

/// Reuse an identical imported copy so opening from Files retains saved marks.
Future<Book> importExternalDocument(
  ImportableLibrary library,
  String name,
  String path,
) async {
  final format = importFormat(name);
  final incoming = File(path);
  final length = await incoming.length();
  String? hash;
  for (final book in await library.listBooks()) {
    final localPath = book.localPath;
    if (book.format != format || localPath == null) continue;
    final existing = File(localPath);
    if (!await existing.exists() || await existing.length() != length) continue;
    hash ??= await _hash(path);
    if (await _hash(localPath) == hash) return book;
  }
  return library.importDocument(name, incoming.openRead());
}
