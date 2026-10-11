import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../domain/services.dart';
import '../domain/book.dart';

class EditInput {
  EditInput(this.title, this.read);
  final String title;
  final Future<Uint8List> Function() read;
}

Future<List<EditInput>> chooseEditSources(BuildContext context, LibraryRepository repository, String action) async {
  final source = await showModalBottomSheet<String>(context: context, builder: (context) => SafeArea(child: Column(
    mainAxisSize: MainAxisSize.min, children: [
      ListTile(title: Text(action, style: Theme.of(context).textTheme.titleLarge)),
      ListTile(leading: const Icon(Icons.local_library_outlined), title: const Text('Select from library'), onTap: () => Navigator.pop(context, 'library')),
      ListTile(leading: const Icon(Icons.folder_open), title: const Text('Local storage'), onTap: () => Navigator.pop(context, 'local')),
    ])));
  if (source == null || !context.mounted) return [];
  List<EditInput> inputs;
  if (source == 'local') {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    inputs = files.map((file) => EditInput(file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''), () async {
      final size = await file.length();
      if (size != null && size > 100 * 1024 * 1024) throw const FormatException('Choose PDFs smaller than 100 MB each.');
      return file.readAsBytes();
    })).toList();
  } else {
    if (repository is! ImportableLibrary) return [];
    final books = (await repository.listBooks()).where((book) => book.format == BookFormat.pdf).toList();
    if (!context.mounted) return [];
    final selection = <Book>[];
    final accepted = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
      builder: (context) => StatefulBuilder(builder: (context, update) => SafeArea(child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7, child: Column(children: [
          ListTile(title: const Text('Select documents')),
          Expanded(
            child: books.isEmpty
                ? const Center(child: Text('Your library has no PDFs.'))
                : ListView(children: [
                    for (final book in books)
                      CheckboxListTile(
                        title: Text(book.title),
                        value: selection.contains(book),
                        onChanged: (value) => update(() {
                          if (value == true) {
                            selection.add(book);
                          } else {
                            selection.remove(book);
                          }
                        }),
                      ),
                  ]),
          ),
          FilledButton(onPressed: selection.isEmpty ? null : () => Navigator.pop(context, true), child: Text('Continue (${selection.length})')),
          const SizedBox(height: 16),
        ])))));
    if (accepted != true) return [];
    inputs = selection.map((book) => EditInput(book.title, () => repository.readDocument(book))).toList();
  }
  if (inputs.isEmpty || !context.mounted) return [];
  if (action != 'Merge') return inputs;
  final ordered = List<EditInput>.of(inputs);
  final accepted = await showModalBottomSheet<bool>(context: context, isScrollControlled: true,
    builder: (context) => StatefulBuilder(builder: (context, update) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .7, child: Column(children: [
        const ListTile(title: Text('Merge order')),
        Expanded(child: ReorderableListView(onReorderItem: (oldIndex, newIndex) => update(() {
          ordered.insert(newIndex, ordered.removeAt(oldIndex));
        }), children: [for (int i = 0; i < ordered.length; i++) ListTile(key: ObjectKey(ordered[i]),
          leading: Text('${i + 1}'), title: Text(ordered[i].title), trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Move up', onPressed: i == 0 ? null : () => update(() => ordered.insert(i - 1, ordered.removeAt(i))), icon: const Icon(Icons.arrow_upward)),
            IconButton(tooltip: 'Remove', onPressed: () => update(() => ordered.removeAt(i)), icon: const Icon(Icons.close)),
          ]))])),
        FilledButton(onPressed: ordered.length < 2 ? null : () => Navigator.pop(context, true), child: const Text('Merge')),
        const SizedBox(height: 16),
      ])))));
  return accepted == true ? ordered : [];
}
