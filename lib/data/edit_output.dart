import 'package:flutter/foundation.dart';

import '../domain/book.dart';
import '../domain/services.dart';
import 'edit_output_storage_stub.dart'
    if (dart.library.io) 'edit_output_storage_io.dart'
    as storage;
import 'library_changes.dart';
import 'recent_documents.dart';

class EditedOutput {
  const EditedOutput(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Fired after the entire editing operation has finished saving.
final editWorkflowCompleted = ValueNotifier<int>(0);

typedef EditOutputWriter = Future<List<String>> Function(List<EditedOutput>);

/// A retry resumes the same save rather than writing duplicate public copies.
class EditOutputSaver {
  EditOutputSaver(this.repository, {EditOutputWriter? writer})
    : _writer = writer ?? storage.saveEditedOutputs;
  final ImportableLibrary repository;
  final EditOutputWriter _writer;
  List<EditedOutput>? _outputs;
  List<String>? _locations;
  final _books = <int, Book>{};
  Future<List<String>>? _saving;

  Future<List<String>> save(List<EditedOutput> outputs) {
    if (outputs.isEmpty) {
      throw const FormatException('No edited files to save.');
    }
    if (_outputs != null && !listEquals(_outputs, outputs)) {
      throw StateError('Use a separate saver for a different result.');
    }
    _outputs ??= List.unmodifiable(outputs);
    return _saving ??= _save().whenComplete(() => _saving = null);
  }

  Future<List<String>> _save() async {
    final outputs = _outputs!;
    // Never report a private library copy as a successful public-storage save.
    _locations ??= await _writer(outputs);
    if (_locations!.length != outputs.length) {
      throw StateError('Not all edited files were saved.');
    }
    for (var i = 0; i < outputs.length; i++) {
      final book = _books[i] ??= await repository.importDocument(
        outputs[i].name,
        Stream.value(outputs[i].bytes),
      );
      await RecentDocuments.instance.record(book.id);
      if (RecentDocuments.instance.saveFailed) {
        throw StateError(
          'Files were saved, but Recent could not be updated. Retry.',
        );
      }
    }
    LibraryChanges.instance.changed();
    return _locations!;
  }
}
