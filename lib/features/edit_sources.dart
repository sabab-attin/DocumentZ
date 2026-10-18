import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../domain/services.dart';

class EditInput {
  EditInput(this.title, this.read);
  final String title;
  final Future<Uint8List> Function() read;
}

Future<List<EditInput>> chooseEditSources(
  BuildContext context,
  LibraryRepository repository,
  String action,
) async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['pdf'],
  );
  final inputs = files
      .map(
        (file) => EditInput(
          file.name.replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''),
          file.readAsBytes,
        ),
      )
      .toList();
  if (inputs.isEmpty || !context.mounted) return [];
  if (action != 'Merge') return inputs;
  return await orderMergeInputs(context, inputs) ?? [];
}

Future<List<EditInput>?> orderMergeInputs(
  BuildContext context,
  List<EditInput> inputs,
) async {
  final ordered = List<EditInput>.of(inputs);
  final accepted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .7,
          child: Column(
            children: [
              const ListTile(title: Text('Merge order')),
              Expanded(
                child: ReorderableListView(
                  onReorderItem: (oldIndex, newIndex) => update(() {
                    ordered.insert(newIndex, ordered.removeAt(oldIndex));
                  }),
                  children: [
                    for (int i = 0; i < ordered.length; i++)
                      ListTile(
                        key: ObjectKey(ordered[i]),
                        leading: Text('${i + 1}'),
                        title: Text(ordered[i].title),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Move up',
                              onPressed: i == 0
                                  ? null
                                  : () => update(
                                      () => ordered.insert(
                                        i - 1,
                                        ordered.removeAt(i),
                                      ),
                                    ),
                              icon: const Icon(Icons.arrow_upward),
                            ),
                            IconButton(
                              tooltip: 'Remove',
                              onPressed: () =>
                                  update(() => ordered.removeAt(i)),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: ordered.length < 2
                    ? null
                    : () => Navigator.pop(context, true),
                child: const Text('Merge'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ),
  );
  return accepted == true ? ordered : null;
}
