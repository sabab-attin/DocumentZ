import 'dart:convert';
import 'dart:math';

String syncRandomId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

String syncCanonical(Object? value) {
  Object? sorted(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sorted(item[key])};
    }
    if (item is List) {
      return item.map(sorted).toList();
    }
    return item;
  }

  return jsonEncode(sorted(value));
}

/// An operation DAG per annotation. Union is commutative and idempotent.
/// A removal is a retained null-valued operation; it is never inferred from
/// an absent remote mark. Concurrent live heads remain separately editable.
class SyncGraph {
  SyncGraph([Map<String, dynamic>? data]) {
    if (data != null) {
      for (final entry in (data['documents'] as Map? ?? {}).entries) {
        documents[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
      bindings.addAll(
        Map<String, dynamic>.from(data['bindings'] as Map? ?? {}),
      );
    }
  }
  final documents = <String, Map<String, dynamic>>{};
  final bindings = <String, dynamic>{};
  Map<String, dynamic> toJson() => {
    'documents': documents,
    'bindings': bindings,
  };
  Map<String, dynamic> _ops(String fingerprint) =>
      documents.putIfAbsent(fingerprint, () => {});
  Map<String, dynamic> _value(Map<String, dynamic> mark) =>
      Map.of(mark)..remove('id');
  Map<String, List<String>> _headsByRoot(String fingerprint) {
    final ops = _ops(fingerprint);
    final superseded = <String>{};
    for (final raw in ops.values) {
      superseded.addAll((raw['parents'] as List).cast<String>());
    }
    final result = <String, List<String>>{};
    for (final id in ops.keys.where((id) => !superseded.contains(id))) {
      result.putIfAbsent(ops[id]['root'] as String, () => []).add(id);
    }
    for (final ids in result.values) {
      ids.sort();
    }
    return result;
  }

  List<String> heads(String fingerprint, String root) =>
      _headsByRoot(fingerprint)[root] ?? [];
  String _add(
    String fingerprint,
    String root,
    List<String> parents,
    Map<String, dynamic>? value,
  ) {
    final id = syncRandomId();
    _ops(fingerprint)[id] = {'root': root, 'parents': parents, 'value': value};
    return id;
  }

  void capture(
    String localId,
    String fingerprint,
    List<Map<String, dynamic>> marks,
  ) {
    final previous = bindings[localId];
    final old = previous != null && previous['fingerprint'] == fingerprint
        ? Map<String, dynamic>.from(previous['aliases'] as Map)
        : <String, dynamic>{};
    final current = {for (final mark in marks) mark['id'] as String: mark};
    if (current.length != marks.length) {
      throw const FormatException('Duplicate local annotation IDs.');
    }
    final aliases = <String, dynamic>{};
    final removed = <String, List<String>>{};
    for (final entry in old.entries) {
      final alias = entry.value as Map;
      final mark = current[entry.key];
      if (mark == null) {
        final root = alias['root'] as String;
        removed
            .putIfAbsent(root, () => [])
            .add(_add(fingerprint, root, [alias['op'] as String], null));
      } else if (syncCanonical(_value(mark)) != syncCanonical(alias['value'])) {
        final value = _value(mark);
        final observed = (alias['heads'] as List? ?? [alias['op']])
            .cast<String>();
        final parents = alias['liveCount'] == 1 && observed.length <= 64
            ? observed
            : [alias['op'] as String];
        aliases[entry.key] = {
          'root': alias['root'],
          'op': _add(fingerprint, alias['root'] as String, parents, value),
          'value': value,
        };
      } else {
        aliases[entry.key] = alias;
      }
    }
    // Removing one displayed conflict copy explicitly keeps the other copies.
    // Make that resolution causal, so a deliberate choice stops being flagged.
    for (final entry in aliases.entries.toList()) {
      final alias = entry.value as Map;
      final deleted = removed[alias['root']];
      if (deleted != null && deleted.length < 64) {
        final parents = <String>{alias['op'] as String, ...deleted}.toList();
        aliases[entry.key] = {
          ...alias,
          'op': _add(
            fingerprint,
            alias['root'] as String,
            parents,
            Map<String, dynamic>.from(alias['value'] as Map),
          ),
        };
      }
    }
    final availableHeads = _headsByRoot(fingerprint);
    for (final entry in current.entries.where((e) => !old.containsKey(e.key))) {
      final value = _value(entry.value);
      final existing = (availableHeads[entry.key] ?? <String>[]).where(
        (id) =>
            syncCanonical(_ops(fingerprint)[id]['value']) ==
            syncCanonical(value),
      );
      final id = existing.isNotEmpty
          ? existing.first
          : _add(fingerprint, entry.key, [], value);
      aliases[entry.key] = {'root': entry.key, 'op': id, 'value': value};
    }
    bindings[localId] = {'fingerprint': fingerprint, 'aliases': aliases};
  }

  ({
    List<Map<String, dynamic>> marks,
    Map<String, dynamic> aliases,
    int conflicts,
  })
  materialize(String fingerprint) {
    final ops = _ops(fingerprint);
    final byRoot = _headsByRoot(fingerprint);
    final roots = byRoot.keys.toList()..sort();
    final marks = <Map<String, dynamic>>[];
    final aliases = <String, dynamic>{};
    var conflicts = 0;
    for (final root in roots) {
      final all = byRoot[root]!;
      final live = all.where((id) => ops[id]['value'] != null).toList();
      if (live.isNotEmpty && all.length > 1) {
        conflicts++;
      }
      for (final op in live) {
        final id = live.length == 1 ? root : '$root~$op';
        final value = Map<String, dynamic>.from(ops[op]['value'] as Map);
        if (live.length > 1 &&
            value['group'] is String &&
            (value['group'] as String).isNotEmpty) {
          value['group'] = '${value['group']}~$op';
        }
        marks.add({...value, 'id': id});
        aliases[id] = {
          'root': root,
          'op': op,
          'value': value,
          'heads': all,
          'liveCount': live.length,
        };
      }
    }
    return (marks: marks, aliases: aliases, conflicts: conflicts);
  }

  void applied(
    String localId,
    String fingerprint,
    Map<String, dynamic> aliases,
  ) {
    bindings[localId] = {'fingerprint': fingerprint, 'aliases': aliases};
  }

  Map<String, dynamic> export(Set<String> fingerprints) => {
    for (final fingerprint in fingerprints) fingerprint: _ops(fingerprint),
  };
  void merge(Map<String, dynamic> incoming, Set<String> allowed) {
    // Work on a copy first: one malformed operation must not partly merge.
    final candidate = <String, Map<String, dynamic>>{};
    for (final entry in incoming.entries) {
      if (!allowed.contains(entry.key) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(entry.key)) {
        throw const FormatException('Unexpected sync document.');
      }
      final ops = Map<String, dynamic>.from(documents[entry.key] ?? {});
      for (final op in (entry.value as Map).entries) {
        final id = op.key as String;
        if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
          throw const FormatException('Invalid operation ID.');
        }
        final data = Map<String, dynamic>.from(op.value as Map);
        final root = data['root'];
        final parents = data['parents'];
        if (!data.containsKey('value') ||
            root is! String ||
            root.isEmpty ||
            root.length > 256 ||
            parents is! List ||
            parents.length > 64 ||
            data.keys.toSet().difference({
              'root',
              'parents',
              'value',
            }).isNotEmpty) {
          throw const FormatException('Invalid annotation operation.');
        }
        if (data['value'] != null && data['value'] is! Map) {
          throw const FormatException('Invalid annotation value.');
        }
        if (ops.containsKey(id) &&
            syncCanonical(ops[id]) != syncCanonical(data)) {
          throw const FormatException('Conflicting operation identity.');
        }
        ops[id] = data;
      }
      if (ops.length > 30000) {
        throw const FormatException('Sync history is too large.');
      }
      final remaining = <String, int>{};
      final children = <String, List<String>>{};
      for (final op in ops.entries) {
        final parents = (op.value['parents'] as List).cast<String>().toSet();
        remaining[op.key] = parents.length;
        for (final parent in parents) {
          if (!ops.containsKey(parent) ||
              ops[parent]['root'] != op.value['root']) {
            throw const FormatException('Missing annotation history.');
          }
          children.putIfAbsent(parent, () => []).add(op.key);
        }
      }
      final ready = remaining.keys.where((id) => remaining[id] == 0).toList();
      var seen = 0;
      while (ready.isNotEmpty) {
        final id = ready.removeLast();
        seen++;
        for (final child in children[id] ?? <String>[]) {
          remaining[child] = remaining[child]! - 1;
          if (remaining[child] == 0) {
            ready.add(child);
          }
        }
      }
      if (seen != ops.length) {
        throw const FormatException('Cyclic annotation history.');
      }
      candidate[entry.key] = ops;
    }
    documents.addAll(candidate);
  }
}
