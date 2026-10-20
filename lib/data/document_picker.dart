import 'package:file_picker/file_picker.dart';

import 'import_validation.dart';

class PickedDocument {
  const PickedDocument(this.name, this.openStream, {this.localPath});
  final String? localPath;
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
  return PickedDocument(file.name, file.readAsByteStream, localPath: file.path);
}

Future<List<PickedDocument>> pickDocuments() async {
  final files = await FilePicker.pickFiles(
    dialogTitle: 'Open documents',
    type: FileType.custom,
    allowedExtensions: documentExtensions,
  );
  return [
    for (final file in files)
      PickedDocument(file.name, file.readAsByteStream, localPath: file.path),
  ];
}
