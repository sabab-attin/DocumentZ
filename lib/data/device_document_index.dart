import 'dart:async';

import 'device_documents_model.dart';

class DeviceIndexSnapshot {
  const DeviceIndexSnapshot(this.scope, this.scan, {required this.complete});
  final String scope;
  final DeviceScan scan;
  final bool complete;
}

/// Persist metadata once. Opening the app never starts another complete crawl
/// when a finished index for the same permission/folder scope is available.
class DeviceDocumentIndex {
  DeviceDocumentIndex({
    required this.read,
    required this.write,
    required this.quickScan,
    required this.fullScan,
    required this.onChanged,
  });
  final Future<DeviceIndexSnapshot?> Function() read;
  final Future<void> Function(DeviceIndexSnapshot) write;
  final Future<DeviceScan> Function() quickScan;
  final Future<DeviceScan> Function() fullScan;
  final void Function() onChanged;
  String? _scope;
  DeviceScan? _value;
  Future<DeviceScan>? _loading, _scanning;
  Future<void> _writes = Future.value();
  int _epoch = 0;
  bool _complete = false;
  final _mutations = <String, DeviceDocument?>{};
  bool get indexing => _scanning != null;

  Future<DeviceScan> load(String scope, {bool refresh = false}) {
    if (_scope != scope) {
      _scope = scope;
      _epoch++;
      _value = null;
      _loading = null;
      _scanning = null;
      _mutations.clear();
      _complete = false;
    }
    if (refresh) return _scan(scope, _epoch);
    final value = _value;
    if (value != null) return Future.value(value);
    final epoch = _epoch;
    return _loading ??= _load(scope, epoch).whenComplete(() {
      if (_epoch == epoch) _loading = null;
    });
  }

  Future<void> _save(DeviceIndexSnapshot snapshot) {
    _writes = _writes.catchError((Object _) {}).then((_) => write(snapshot));
    return _writes;
  }

  Future<DeviceScan> _load(String scope, int epoch) async {
    final saved = await read();
    if (_epoch != epoch) return const DeviceScan([], [], []);
    if (saved != null && saved.scope == scope) {
      _value = saved.scan;
      _complete = saved.complete;
      if (!saved.complete) _backgroundScan(scope, epoch);
      return saved.scan;
    }
    final seed = await quickScan();
    if (_epoch != epoch) return const DeviceScan([], [], []);
    _value = seed;
    await _save(DeviceIndexSnapshot(scope, seed, complete: false));
    _backgroundScan(scope, epoch);
    return seed;
  }

  void _backgroundScan(String scope, int epoch) {
    unawaited(
      _scan(scope, epoch).then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {
          if (_epoch == epoch) onChanged();
        },
      ),
    );
  }

  Future<DeviceScan> _scan(String scope, int epoch) {
    final current = _scanning;
    if (current != null) return current;
    _mutations.clear();
    final pending = _performScan(scope, epoch).whenComplete(() {
      if (_epoch == epoch) {
        _scanning = null;
        onChanged();
      }
    });
    _scanning = pending;
    onChanged();
    return pending;
  }

  Future<DeviceScan> _performScan(String scope, int epoch) async {
    var scan = await fullScan();
    if (_epoch != epoch) return scan;
    if (_mutations.isNotEmpty) {
      final documents = {for (final doc in scan.documents) doc.location: doc};
      for (final mutation in _mutations.entries) {
        documents.remove(mutation.key);
        final replacement = mutation.value;
        if (replacement != null) documents[replacement.location] = replacement;
      }
      _mutations.clear();
      scan = DeviceScan(documents.values.toList(), scan.folders, scan.errors);
    }
    _value = scan;
    _complete = true;
    await _save(DeviceIndexSnapshot(scope, scan, complete: true));
    if (_epoch == epoch) onChanged();
    return scan;
  }

  Future<void> replace(DeviceDocument previous, DeviceDocument? next) async {
    // Preserve local mutations even if an older crawl is still in flight.
    if (indexing) _mutations[previous.location] = next;
    final value = _value;
    final scope = _scope;
    if (value == null || scope == null) return;
    final documents = value.documents
        .where((doc) => doc.location != previous.location)
        .toList();
    if (next != null) documents.add(next);
    final updated = DeviceScan(documents, value.folders, value.errors);
    _value = updated;
    await _save(DeviceIndexSnapshot(scope, updated, complete: _complete));
  }

  /// Merge a metadata delta without starting another complete storage scan.
  Future<void> applyChanges(DeviceScan changes, Set<String> removed) async {
    final value = _value;
    final scope = _scope;
    if (value == null || scope == null) return;
    final documents = {for (final doc in value.documents) doc.location: doc};
    var changed = false;
    for (final location in removed) {
      changed = documents.remove(location) != null || changed;
      if (indexing) _mutations[location] = null;
    }
    for (final doc in changes.documents) {
      final before = documents[doc.location];
      if (before == null ||
          before.name != doc.name ||
          before.folder != doc.folder ||
          before.size != doc.size ||
          before.modified != doc.modified) {
        documents[doc.location] = doc;
        changed = true;
      }
      if (indexing) _mutations[doc.location] = doc;
    }
    if (!changed) return;
    final updated = DeviceScan(
      documents.values.toList(),
      value.folders,
      value.errors,
    );
    _value = updated;
    await _save(DeviceIndexSnapshot(scope, updated, complete: _complete));
    onChanged();
  }
}
