import 'dart:async';

import 'automatic_device_changes.dart';

import 'dart:convert';

import 'device_document_index.dart';
import 'device_index_storage_io.dart';
import 'library_changes.dart';

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

final _deviceIndex = DeviceDocumentIndex(
  read: readDeviceIndex,
  write: writeDeviceIndex,
  quickScan: _quickDeviceDocuments,
  fullScan: _scanDeviceDocumentsUncached,
  onChanged: LibraryChanges.instance.changed,
);
bool get deviceDocumentIndexing => _deviceIndex.indexing;
Future<DeviceScan> scanDeviceDocuments({bool refresh = false}) async {
  final prefs = await SharedPreferences.getInstance();
  // Without connected desktop folders there is no device index to load.
  // Keep imported documents available without touching native disk storage.
  if (!Platform.isAndroid && (prefs.getStringList(_foldersKey) ?? []).isEmpty) {
    return const DeviceScan([], [], []);
  }
  final scope = Platform.isAndroid
      ? await _channel.invokeMethod<String>('scanScope') ?? 'android'
      : jsonEncode((prefs.getStringList(_foldersKey) ?? []).toList()..sort());
  final scan = await _deviceIndex.load('browse-v1:$scope', refresh: refresh);
  if (Platform.isAndroid) {
    AutomaticDeviceChanges.start(_applyAutomaticChanges);
    unawaited(AutomaticDeviceChanges.requestRefresh());
  }
  return scan;
}

Future<void> _applyAutomaticChanges(Map<String, dynamic> raw) async {
  final scope = await _channel.invokeMethod<String>('scanScope');
  if (scope != raw['scope']) {
    throw const FormatException('Storage permissions changed.');
  }
  await _deviceIndex.load('browse-v1:$scope');
  final documents = (raw['files'] as List? ?? [])
      .map(
        (entry) => DeviceDocument(
          location: entry['uri'] as String,
          name: entry['name'] as String,
          folder: entry['folder'] as String,
          size: (entry['size'] as num).toInt(),
          modified: (entry['modified'] as num).toInt(),
        ),
      )
      .where((doc) => isBrowseDocumentName(doc.name))
      .toList();
  await _deviceIndex.applyChanges(
    DeviceScan(documents, [], []),
    (raw['removed'] as List? ?? []).cast<String>().toSet(),
  );
}

Future<DeviceScan> _quickDeviceDocuments() async {
  if (Platform.isAndroid) {
    final raw = await _channel.invokeMapMethod<String, dynamic>('quickScan', {
      'extensions': browseDocumentExtensions,
    });
    return DeviceScan(
      (raw?['files'] as List? ?? [])
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
          .toList(),
      (raw?['folders'] as List? ?? []).cast<String>(),
      (raw?['errors'] as List? ?? []).cast<String>(),
    );
  }
  return DeviceScan(
    [],
    (await SharedPreferences.getInstance()).getStringList(_foldersKey) ?? [],
    [],
  );
}

Future<DeviceScan> _scanDeviceDocumentsUncached() async {
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
    final renamed = DeviceDocument(
      location: location,
      name: name,
      folder: document.folder,
      size: document.size,
      modified: document.modified,
    );
    await _deviceIndex.replace(document, renamed);
    return renamed;
  }
  await _checkDeviceFile(document);
  final destination = path.join(path.dirname(document.location), name);
  if (await File(destination).exists()) {
    throw const FormatException('A file with that name already exists.');
  }
  final file = await File(document.location).rename(destination);
  final stat = await file.stat();
  final renamed = DeviceDocument(
    location: file.path,
    name: name,
    folder: document.folder,
    size: stat.size,
    modified: stat.modified.millisecondsSinceEpoch,
  );
  await _deviceIndex.replace(document, renamed);
  return renamed;
}

Future<void> deleteDeviceDocument(DeviceDocument document) async {
  if (Platform.isAndroid) {
    await _channel.invokeMethod<void>('delete', {'uri': document.location});
    await _deviceIndex.replace(document, null);
    return;
  }
  await _checkDeviceFile(document);
  await File(document.location).delete();
  await _deviceIndex.replace(document, null);
}
