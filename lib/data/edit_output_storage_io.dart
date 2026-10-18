import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'edit_output.dart';

String _safeName(String name) {
  final safe = path
      .basename(name.replaceAll('\\', '/'))
      .replaceAll(RegExp(r'[\x00-\x1f<>:"/\\|?*]'), '_')
      .trim();
  if (safe.isEmpty || safe == '.' || safe == '..') {
    throw const FormatException('Invalid output filename.');
  }
  return safe;
}

Future<List<String>> saveEditedOutputs(List<EditedOutput> outputs) async {
  if (Platform.isAndroid) {
    final temporary = await Directory(
      path.join((await getTemporaryDirectory()).path, 'documentz-exports'),
    ).create(recursive: true);
    final batch = await temporary.createTemp('save-');
    try {
      final entries = <Map<String, String>>[];
      for (var i = 0; i < outputs.length; i++) {
        final file = File(path.join(batch.path, '$i.part'));
        await file.writeAsBytes(outputs[i].bytes, flush: true);
        entries.add({'path': file.path, 'name': _safeName(outputs[i].name)});
      }
      final locations = await const MethodChannel('documentz/edit_outputs')
          .invokeListMethod<String>('save', {'files': entries});
      if (locations == null || locations.length != outputs.length) {
        throw const FileSystemException('The edited files could not be saved.');
      }
      return locations;
    } finally {
      // This directory was created above specifically for this save operation.
      try {
        await batch.delete(recursive: true);
      } on FileSystemException {
        // A cleanup failure must not turn a completed public save into a retry.
      }
    }
  }
  final downloads = await getDownloadsDirectory();
  if (downloads == null) {
    throw const FileSystemException('The Downloads folder is unavailable.');
  }
  return saveEditedOutputsToDirectory(outputs, downloads);
}

/// Shared disk writer; tests supply a temporary Downloads root.
Future<List<String>> saveEditedOutputsToDirectory(
  List<EditedOutput> outputs,
  Directory downloads,
) async {
  final folder = await Directory(path.join(downloads.path, 'DocumentZ'))
      .create(recursive: true);
  final saved = <File>[];
  try {
    for (final output in outputs) {
      final name = _safeName(output.name);
      var candidate = File(path.join(folder.path, name));
      var suffix = 1;
      while (await candidate.exists()) {
        candidate = File(
          path.join(
            folder.path,
            '${path.basenameWithoutExtension(name)} (${suffix++})${path.extension(name)}',
          ),
        );
      }
      await candidate.create(exclusive: true);
      saved.add(candidate);
      await candidate.writeAsBytes(output.bytes, flush: true);
    }
    return saved.map((file) => file.path).toList();
  } catch (_) {
    for (final file in saved) {
      try {
        await file.delete();
      } on FileSystemException {
        /* Keep original error. */
      }
    }
    rethrow;
  }
}
