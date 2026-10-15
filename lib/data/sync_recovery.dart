import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'sync_graph.dart';

const syncJournalKey = 'documentz.annotationSync.journal.v1';
String syncRecoveryKey(String journal) => journal == syncJournalKey
    ? 'documentz.annotationSync.recovery.v1'
    : '$journal.recovery';
Future<void>? _storageTail;
Future<T> withSyncStorageLock<T>(Future<T> Function() work) async {
  final previous = _storageTail;
  final released = Completer<void>();
  _storageTail = released.future;
  try {
    if (previous != null) {
      await previous;
    }
    return await work();
  } finally {
    // Keep no completed Future from a previous execution zone while idle.
    if (identical(_storageTail, released.future)) {
      _storageTail = null;
    }
    released.complete();
  }
}

/// This is local recovery only: no network, secret-store or crypto initialization.
/// Readers check it before loading annotations, so a crash cannot expose a
/// partially applied snapshot as a new baseline for later offline edits.
Future<void> recoverPendingSyncAnnotations(
  SharedPreferences storage, {
  String journal = syncJournalKey,
}) => withSyncStorageLock(() async {
  final key = syncRecoveryKey(journal);
  final recovery = storage.getString(key);
  if (recovery == null) {
    return;
  }
  final raw = storage.getString(journal);
  if (raw == null) {
    throw const FormatException('Missing annotation recovery history.');
  }
  final graph = SyncGraph(Map<String, dynamic>.from(jsonDecode(raw) as Map));
  for (final raw in jsonDecode(recovery) as List) {
    final item = Map<String, dynamic>.from(raw as Map);
    final target = item['key'] as String;
    if (!target.startsWith('annotations.v1.')) {
      throw const FormatException('Invalid annotation recovery key.');
    }
    final current = storage.getString(target) ?? '[]';
    if (current == item['before']) {
      if (!await storage.setString(target, item['after'] as String)) {
        throw const FormatException('Could not recover synced annotations.');
      }
      graph.applied(
        item['localId'] as String,
        item['fingerprint'] as String,
        Map<String, dynamic>.from(item['aliases'] as Map),
      );
    } else if (current == item['after']) {
      graph.applied(
        item['localId'] as String,
        item['fingerprint'] as String,
        Map<String, dynamic>.from(item['aliases'] as Map),
      );
    }
  }
  // Preserve unexpected newer local data rather than overwrite it.
  if (!await storage.setString(journal, jsonEncode(graph.toJson()))) {
    throw const FormatException('Could not save annotation recovery.');
  }
  if (!await storage.remove(key)) {
    throw const FormatException('Could not finish annotation recovery.');
  }
});
