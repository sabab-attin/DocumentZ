import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentDocuments extends ChangeNotifier {
  static final instance = RecentDocuments();
  static const storageKey = 'documentz.recent.v1';
  final Map<String, int> accessed = {};
  final removed = <String>{};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  bool saveFailed = false;

  /// Each widget test owns a separate fake clock and preferences store.
  @visibleForTesting
  void resetForTests() {
    accessed.clear();
    removed.clear();
    _loading = null;
    _writes = Future<void>.value();
    saveFailed = false;
  }

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      removed.addAll(prefs.getStringList('documentz.recentRemoved.v1') ?? []);
      Map raw;
      try {
        raw = jsonDecode(prefs.getString(storageKey) ?? '{}') as Map;
      } catch (_) {
        raw = {};
      }
      for (final e in raw.entries) {
        if (e.key is String && e.value is int) {
          accessed.putIfAbsent(e.key as String, () => e.value as int);
        }
      }
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await load();
    accessed.remove(id);
    removed.add(id);
    notifyListeners();
    final data = jsonEncode(accessed);
    final removedData = removed.toList();
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        saveFailed = !await prefs.setString(storageKey, data);
        await prefs.setStringList('documentz.recentRemoved.v1', removedData);
      } catch (_) {
        saveFailed = true;
      }
    });
    await _writes;
  }

  Future<void> record(String id) async {
    await load();
    removed.remove(id);
    accessed[id] = DateTime.now().millisecondsSinceEpoch;
    notifyListeners();
    final data = jsonEncode(accessed);
    final removedData = removed.toList();
    _writes = _writes.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        saveFailed = !await prefs.setString(storageKey, data);
        await prefs.setStringList('documentz.recentRemoved.v1', removedData);
      } catch (_) {
        saveFailed = true;
      }
    });
    await _writes;
  }
}
