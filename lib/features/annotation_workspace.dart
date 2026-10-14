import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../core/preferences.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'reader.dart';

Future<void> openAnnotationWorkspace(
  BuildContext context,
  LibraryRepository repository, {
  Book? book,
}) async {
  if (repository is! ImportableLibrary) return;
  try {
    Book? selected = book;
    if (selected == null) {
      final source = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Annotate document')),
              ListTile(
                leading: const Icon(Icons.local_library_outlined),
                title: const Text('Select from library'),
                onTap: () => Navigator.pop(sheet, 'library'),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Local storage'),
                onTap: () => Navigator.pop(sheet, 'local'),
              ),
            ],
          ),
        ),
      );
      if (!context.mounted || source == null) return;
      if (source == 'local') {
        final file = await FilePicker.pickFile();
        if (file == null) return;
        selected = await repository.importDocument(
          file.name,
          file.readAsByteStream(),
        );
      } else {
        final books = await repository.listBooks();
        if (!context.mounted) return;
        selected = await showModalBottomSheet<Book>(
          context: context,
          isScrollControlled: true,
          builder: (sheet) => SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheet).height * .7,
              child: Column(
                children: [
                  const ListTile(title: Text('Annotate document')),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final item in books)
                          ListTile(
                            title: Text(item.title),
                            subtitle: Text(item.format.name.toUpperCase()),
                            onTap: () => Navigator.pop(sheet, item),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    if (selected == null || !context.mounted) return;
    final preferences = await ReaderPreferences.load();
    if (!context.mounted) {
      preferences.dispose();
      return;
    }
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: selected!,
            repository: repository,
            preferences: preferences,
            annotationMode: true,
          ),
        ),
      );
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
  }
}
