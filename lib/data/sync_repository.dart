import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/services.dart';
import '../features/annotations.dart';
import 'sync_graph.dart';
import 'sync_recovery.dart';
export 'sync_recovery.dart' show syncJournalKey;

const syncPayloadLimit = 16 * 1024 * 1024;

Future<String> _fileFingerprint(String path, String format) =>
    Isolate.run(() async {
      final stream = Stream<List<int>>.multi((sink) async {
        sink.add([...utf8.encode(format), 0]);
        try {
          await for (final bytes in File(path).openRead()) {
            sink.add(bytes);
          }
          sink.close();
        } catch (error, stack) {
          sink.addError(error, stack);
          sink.close();
        }
      });
      return (await crypto.sha256.bind(stream).first).toString();
    });
String _bytesFingerprint((String, Uint8List) input) => crypto.sha256.convert([
  ...utf8.encode(input.$1),
  0,
  ...input.$2,
]).toString();

class SyncRepository {
  SyncRepository(this.library, {this.storageKey = syncJournalKey});
  final String storageKey;
  String get _recoveryKey => syncRecoveryKey(storageKey);
  final ImportableLibrary library;
  late SharedPreferences storage;
  SyncGraph graph = SyncGraph();
  final indexed = <String, String>{};
  final _fingerprints = <String, (int, int, String)>{};
  bool loaded = false;
  int documentCount = 0, conflicts = 0;
  Set<String> get fingerprints => indexed.values.toSet();
  Future<void> load() async {
    if (loaded) {
      return;
    }
    storage = await SharedPreferences.getInstance();
    await recoverPendingSyncAnnotations(storage, journal: storageKey);
    final raw = storage.getString(storageKey);
    if (raw != null) {
      graph = SyncGraph(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    }
    loaded = true;
  }

  Future<void> save() async {
    final state = graph.toJson();
    final encoded = await compute(_encodeSyncJson, state);
    if (utf8.encode(encoded).length > 64 * 1024 * 1024) {
      throw const FormatException('Annotation sync history is too large.');
    }
    if (!await storage.setString(storageKey, encoded)) {
      throw const FileSystemException(
        'Could not save annotation sync history.',
      );
    }
  }

  Future<void> prepare({bool Function()? active}) async {
    await load();
    final books = await library.listBooks();
    indexed.clear();
    for (final book in books) {
      if (active != null && !active()) {
        throw const SocketException('Sync was stopped.');
      }
      final String fingerprint;
      final path = book.localPath;
      if (path != null && await File(path).exists()) {
        final stat = await File(path).stat();
        final cached = _fingerprints[book.id];
        if (cached != null &&
            cached.$1 == stat.size &&
            cached.$2 == stat.modified.microsecondsSinceEpoch) {
          fingerprint = cached.$3;
        } else {
          fingerprint = await _fileFingerprint(path, book.format.name);
          _fingerprints[book.id] = (
            stat.size,
            stat.modified.microsecondsSinceEpoch,
            fingerprint,
          );
        }
      } else {
        final data = await library.readDocument(book);
        fingerprint = await compute(_bytesFingerprint, (
          book.format.name,
          data,
        ));
      }
      if (active != null && !active()) {
        throw const SocketException('Sync was stopped.');
      }
      indexed[book.id] = fingerprint;
      final marks = parseSyncMarks(
        jsonDecode(storage.getString('annotations.v1.${book.id}') ?? '[]'),
      );
      graph.capture(book.id, fingerprint, marks);
    }
    documentCount = fingerprints.length;
    await save();
  }

  Future<Map<String, dynamic>> snapshot(Set<String> common) async {
    final data = graph.export(common);
    final size = await syncEncodedSize(data);
    if (size > syncPayloadLimit) {
      throw const FormatException('Annotations exceed the 16 MB sync limit.');
    }
    return data;
  }

  Future<void> accept(
    Map<String, dynamic> remote,
    Set<String> common,
    bool Function() active,
  ) => withSyncStorageLock(() async {
    if (!active()) {
      throw const SocketException('Sync was stopped.');
    }
    final images = <String>{};
    for (final document in remote.values) {
      for (final op in (document as Map).values) {
        final value = op['value'];
        if (value != null) {
          final marks = parseSyncMarks([
            {...Map<String, dynamic>.from(value as Map), 'id': op['root']},
          ]);
          for (final mark in marks) {
            images.addAll((mark['attachments'] as List).cast<String>());
          }
        }
      }
    }
    await compute<Set<String>, void>(validateSyncImages, images);
    // The original graph stays untouched if validation fails.
    final baseline = graph.toJson();
    final candidate = await compute(_mergeSyncGraphs, (
      baseline,
      remote,
      common,
    ));
    if (!active()) {
      throw const SocketException('Sync was stopped.');
    }
    final results = {
      for (final fingerprint in common)
        fingerprint: candidate.materialize(fingerprint),
    };
    if (results.values.any((result) => result.marks.length > 10000)) {
      throw const FormatException(
        'Too many synced annotations in one document.',
      );
    }
    graph = candidate;
    await save();
    final pending = <Map<String, dynamic>>[];
    conflicts = 0;
    for (final entry in indexed.entries.where(
      (e) => common.contains(e.value),
    )) {
      final result = results[entry.value]!;
      conflicts += result.conflicts;
      final key = 'annotations.v1.${entry.key}';
      final before = storage.getString(key) ?? '[]';
      final after = jsonEncode(result.marks);
      pending.add({
        'key': key,
        'before': before,
        'after': after,
        'localId': entry.key,
        'fingerprint': entry.value,
        'aliases': result.aliases,
      });
    }
    if (!active()) {
      throw const SocketException('Sync was stopped.');
    }
    // A small write-ahead record lets the next sync finish an interrupted apply.
    if (!await storage.setString(_recoveryKey, jsonEncode(pending))) {
      throw const FileSystemException('Could not prepare synced annotations.');
    }
    for (final item in pending) {
      if (!active()) {
        throw const SocketException('Sync was stopped.');
      }
      final key = item['key'] as String;
      if ((storage.getString(key) ?? '[]') != item['before']) {
        throw const FileSystemException(
          'Local annotations changed. Retry sync after closing the reader.',
        );
      }
      if (!await storage.setString(key, item['after'] as String)) {
        throw const FileSystemException('Could not save synced annotations.');
      }
      graph.applied(
        item['localId'] as String,
        item['fingerprint'] as String,
        Map<String, dynamic>.from(item['aliases'] as Map),
      );
    }
    await save();
    if (!await storage.remove(_recoveryKey)) {
      throw const FileSystemException('Could not complete sync.');
    }
  });
}

List<Map<String, dynamic>> parseSyncMarks(Object? raw) {
  if (raw is! List || raw.length > 10000) {
    throw const FormatException('Invalid annotation list.');
  }
  return raw.map((item) {
    final data = Map<String, dynamic>.from(item as Map);
    final mark = DocumentMark.fromJson(data);
    if (mark.id.isEmpty ||
        mark.id.length > 256 ||
        mark.anchor.length > 2048 ||
        mark.text.length > 100000 ||
        mark.quote.length > 100000 ||
        mark.points.length > 100000 ||
        mark.rects.length > 10000 ||
        mark.attachments.length > 16 ||
        !mark.fontSize.isFinite ||
        mark.fontSize <= 0 ||
        mark.fontSize > 1000 ||
        (mark.width != null &&
            (!mark.width!.isFinite ||
                mark.width! <= 0 ||
                mark.width! > 1000)) ||
        mark.points.any(
          (p) =>
              !p.dx.isFinite ||
              !p.dy.isFinite ||
              p.dx.abs() > 1000000 ||
              p.dy.abs() > 1000000,
        ) ||
        mark.rects.any(
          (r) =>
              !r.left.isFinite ||
              !r.top.isFinite ||
              !r.right.isFinite ||
              !r.bottom.isFinite ||
              r.left.abs() > 1000000 ||
              r.top.abs() > 1000000 ||
              r.right.abs() > 1000000 ||
              r.bottom.abs() > 1000000 ||
              r.width < 0 ||
              r.height < 0,
        )) {
      throw const FormatException('Invalid annotation geometry or content.');
    }
    for (final attachment in mark.attachments) {
      if (attachment.length > 1500000 ||
          base64Decode(attachment).length > 1024 * 1024) {
        throw const FormatException('Annotation image is too large.');
      }
    }
    return mark.toJson();
  }).toList();
}

void validateSyncImages(Set<String> images) {
  for (final encoded in images) {
    final bytes = base64Decode(encoded);
    final img.Decoder decoder;
    if (bytes.length > 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      decoder = img.PngDecoder();
    } else if (bytes.length > 2 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      decoder = img.JpegDecoder();
    } else {
      throw const FormatException('Annotation images must be PNG or JPEG.');
    }
    final info = decoder.startDecode(bytes);
    if (info == null ||
        info.width < 1 ||
        info.height < 1 ||
        info.width * info.height > 8000000 ||
        info.numFrames > 1) {
      throw const FormatException(
        'Annotation image dimensions are invalid or too large.',
      );
    }
    if (decoder.decodeFrame(0) == null) {
      throw const FormatException('Annotation image is damaged.');
    }
  }
}

String _encodeSyncJson(Object? value) => jsonEncode(value);
int _encodedSyncSize(Object? value) => utf8.encode(jsonEncode(value)).length;
Future<int> syncEncodedSize(Object? value) => compute(_encodedSyncSize, value);
SyncGraph _mergeSyncGraphs(
  (Map<String, dynamic>, Map<String, dynamic>, Set<String>) input,
) {
  final copy = SyncGraph(
    Map<String, dynamic>.from(jsonDecode(jsonEncode(input.$1)) as Map),
  );
  copy.merge(input.$2, input.$3);
  return copy;
}

/// Compare the entire shared operation history, including deletion records.
Future<String> syncSnapshotDigest(Map<String, dynamic> snapshot) =>
    compute(_snapshotDigest, snapshot);
String _snapshotDigest(Map<String, dynamic> snapshot) =>
    crypto.sha256.convert(utf8.encode(syncCanonical(snapshot))).toString();
