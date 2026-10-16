import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_documents_model.dart';
import 'browse_formats.dart';
export 'device_documents_model.dart';

const _channel = MethodChannel('documentz/device_documents');
const _foldersKey = 'documentz.deviceFolders.v1';
Future<bool> hasDeviceStorageAccess() async =>
    Platform.isAndroid &&
    (await _channel.invokeMethod<bool>('storageAccess') ?? false);
Future<bool> requestDeviceStorageAccess() async =>
    Platform.isAndroid &&
    (await _channel.invokeMethod<bool>('requestStorageAccess') ?? false);
bool get supportsDeviceStorageAccess => Platform.isAndroid;
Future<bool> addDeviceFolder() async {
  if (Platform.isAndroid) {
    return await _channel.invokeMethod<bool>('addFolder') ?? false;
  }
  final folder = await FilePicker.getDirectoryPath();
  if (folder == null) return false;
  final prefs = await SharedPreferences.getInstance();
  final roots = prefs.getStringList(_foldersKey) ?? [];
  if (!roots.contains(folder)) {
    await prefs.setStringList(_foldersKey, [...roots, folder]);
  }
  return true;
}

Future<void> removeDeviceFolder(String folder) async {
  if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('removeFolder', {'folder': folder});
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    _foldersKey,
    (prefs.getStringList(_foldersKey) ?? []).where((p) => p != folder).toList(),
  );
}

Future<DeviceScan> scanDeviceDocuments() async {
  if (Platform.isAndroid) {
    final raw = await _channel.invokeMapMethod<String, dynamic>('scan', {
      'extensions': browseDocumentExtensions,
    });
    final documents = (raw?['files'] as List? ?? [])
        .map(
          (e) => DeviceDocument(
            location: e['uri'] as String,
            name: e['name'] as String,
            folder: e['folder'] as String,
            size: (e['size'] as num?)?.toInt() ?? 0,
            modified: (e['modified'] as num?)?.toInt() ?? 0,
          ),
        )
        .where((doc) => isBrowseDocumentName(doc.name))
        .toList();
    return DeviceScan(
      documents,
      (raw?['folders'] as List? ?? []).cast<String>(),
      (raw?['errors'] as List? ?? []).cast<String>(),
    );
  }
  final prefs = await SharedPreferences.getInstance();
  final roots = prefs.getStringList(_foldersKey) ?? [];
  final found = <String, DeviceDocument>{}, errors = <String>[];
  final visited = <String>{};
  String canonical(String value) => path.normalize(path.absolute(value));
  String identity(String value) {
    final normalized = canonical(value);
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<void> walk(Directory directory, String root) async {
    if (!visited.add(identity(directory.path))) return;
    try {
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is Directory) {
          await walk(entry, root);
        }
        if (entry is File) {
          final name = entry.path.replaceAll('\\', '/').split('/').last;
          if (!isBrowseDocumentName(name)) {
            continue;
          }
          try {
            final stat = await entry.stat();
            found[identity(entry.path)] = DeviceDocument(
              location: canonical(entry.path),
              name: name,
              folder: root,
              size: stat.size,
              modified: stat.modified.millisecondsSinceEpoch,
            );
          } on FileSystemException {
            errors.add(entry.path);
          }
        }
      }
    } on FileSystemException {
      errors.add(directory.path);
    }
  }

  for (final root in roots) {
    await walk(Directory(root), root);
  }
  return DeviceScan(found.values.toList(), roots, errors);
}

Stream<List<int>> openDeviceDocument(DeviceDocument document) async* {
  if (Platform.isAndroid) {
    final bytes = await _channel.invokeMethod<List<int>>('read', {
      'uri': document.location,
    });
    if (bytes == null) throw const FileSystemException('Cannot read document');
    yield bytes;
  } else {
    yield* File(document.location).openRead();
  }
}

Future<void> _checkDeviceFile(DeviceDocument document) async {
  final realFile = await File(document.location).resolveSymbolicLinks();
  final prefs = await SharedPreferences.getInstance();
  final roots = prefs.getStringList(_foldersKey) ?? [];
  for (final root in roots) {
    final resolved = await Directory(root).resolveSymbolicLinks();
    if (path.isWithin(resolved, realFile)) return;
  }
  throw const FormatException('This file is outside the connected folders.');
}

Future<DeviceDocument> renameDeviceDocument(
  DeviceDocument document,
  String name,
) async {
  if (name.trim().isEmpty ||
      name.contains('/') ||
      name.contains('\\') ||
      name == '.' ||
      name == '..') {
    throw const FormatException('Enter a valid file name.');
  }
  if (path.extension(name).toLowerCase() !=
      path.extension(document.name).toLowerCase()) {
    throw const FormatException('Keep the original file extension.');
  }
  String location;
  if (Platform.isAndroid) {
    location =
        await _channel.invokeMethod<String>('rename', {
          'uri': document.location,
          'name': name,
        }) ??
        document.location;
    final scan = await scanDeviceDocuments();
    for (final file in scan.documents) {
      if (file.location == location) return file;
    }
    throw const FormatException(
      'The file was renamed, but could not be rescanned. Refresh the library.',
    );
  }
  await _checkDeviceFile(document);
  final destination = path.join(path.dirname(document.location), name);
  if (await File(destination).exists()) {
    throw const FormatException('A file with that name already exists.');
  }
  final file = await File(document.location).rename(destination);
  final stat = await file.stat();
  return DeviceDocument(
    location: file.path,
    name: name,
    folder: document.folder,
    size: stat.size,
    modified: stat.modified.millisecondsSinceEpoch,
  );
}

Future<void> deleteDeviceDocument(DeviceDocument document) async {
  if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('delete', {'uri': document.location});
    return;
  }
  await _checkDeviceFile(document);
  await File(document.location).delete();
}
