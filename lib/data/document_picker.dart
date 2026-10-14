import 'package:file_picker/file_picker.dart';

import 'import_validation.dart';

class PickedDocument {
  const PickedDocument(this.name, this.openStream);
  final String name;
  final Stream<List<int>> Function() openStream;
}

typedef DocumentPicker = Future<PickedDocument?> Function();

Future<PickedDocument?> pickDocument() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: documentExtensions,
  );
  if (file == null) return null;
  final length = file.lengthSync() ?? await file.length();
  if (length != null && length > 100 * 1024 * 1024) {
    throw const FormatException('Choose a file smaller than 100 MB.');
  }
  return PickedDocument(file.name, file.readAsByteStream);
}
