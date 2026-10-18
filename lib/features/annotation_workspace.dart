import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/preferences.dart';
import '../data/external_document_import.dart';
import '../data/import_validation.dart';
import '../data/recent_documents.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'reader.dart';

Future<bool> openAnnotationWorkspace(
  BuildContext context,
  LibraryRepository repository, {
  Book? book,
  List<Book> books = const [],
}) async {
  if (repository is! ImportableLibrary) return false;
  try {
    final selected = <Book>[...books];
    if (book != null && selected.isEmpty) selected.add(book);
    if (selected.isEmpty) {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: documentExtensions,
      );
      for (final file in files) {
        final path = file.path;
        selected.add(
          path == null
              ? await repository.importDocument(
                  file.name,
                  file.readAsByteStream(),
                )
              : await importExternalDocument(repository, file.name, path),
        );
      }
    }
    if (selected.isEmpty || !context.mounted) return false;
    final preferences = await ReaderPreferences.load();
    try {
      for (final document in selected) {
        if (!context.mounted) return false;
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => ReaderScreen(
              book: document,
              repository: repository,
              preferences: preferences,
              annotationMode: true,
            ),
          ),
        );
        await RecentDocuments.instance.record(document.id);
      }
      return true;
    } finally {
      preferences.dispose();
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the annotation workspace.'),
        ),
      );
    }
    return false;
  }
}
