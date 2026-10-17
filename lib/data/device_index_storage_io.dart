import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'app_storage_io.dart';
import 'device_document_index.dart';
import 'device_documents_model.dart';

File? _cacheFile;
Future<File> _file() async {
  final cached = _cacheFile;
  if (cached != null) return cached;
  final root = await applicationLibraryDirectory();
  await root.create(recursive: true);
  // Cache only successful resolution; transient failures remain retryable.
  return _cacheFile = File('${root.path}/.device-index-v1.json');
}

Future<DeviceIndexSnapshot?> readDeviceIndex() async {
  final file = await _file();
  return Isolate.run(() async {
    try {
      if (!await file.exists()) return null;
      final raw = jsonDecode(await file.readAsString()) as Map;
      if (raw['schema'] != 1) return null;
      final scan = DeviceScan(
        (raw['files'] as List)
            .map(
              (entry) => DeviceDocument(
                location: entry['uri'] as String,
                name: entry['name'] as String,
                folder: entry['folder'] as String,
                size: entry['size'] as int,
                modified: entry['modified'] as int,
              ),
            )
            .toList(),
        (raw['folders'] as List).cast<String>(),
        (raw['errors'] as List).cast<String>(),
      );
      return DeviceIndexSnapshot(
        raw['scope'] as String,
        scan,
        complete: raw['complete'] == true,
      );
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  });
}

Future<void> writeDeviceIndex(DeviceIndexSnapshot snapshot) async {
  final file = await _file();
  await Isolate.run(() async {
    final pending = File('${file.path}.pending');
    await pending.writeAsString(
      jsonEncode({
        'schema': 1,
        'scope': snapshot.scope,
        'complete': snapshot.complete,
        'files': [
          for (final doc in snapshot.scan.documents)
            {
              'uri': doc.location,
              'name': doc.name,
              'folder': doc.folder,
              'size': doc.size,
              'modified': doc.modified,
            },
        ],
        'folders': snapshot.scan.folders,
        'errors': snapshot.scan.errors,
      }),
      flush: true,
    );
    await pending.rename(file.path);
  });
}
