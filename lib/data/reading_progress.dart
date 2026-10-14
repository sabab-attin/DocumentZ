import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Furthest observed reading position, stored independently of document bytes.
class ReadingProgress extends ChangeNotifier {
  ReadingProgress();
  static final instance = ReadingProgress();
  static const storageKey = 'documentz.readingProgress.v1';
  final Map<String, double> _values = {};
  Future<void>? _loading;
  Future<void> _writes = Future.value();
  Timer? _timer;
  bool saveFailed = false;

  @visibleForTesting
  void resetForTests() {
    _timer?.cancel();
    _timer = null;
    _values.clear();
    _loading = null;
    _writes = Future<void>.value();
    saveFailed = false;
  }

  double fraction(String id) => _values[id] ?? 0;
  int percent(String id) => (fraction(id) * 100).round();

  Future<void> load() => _loading ??= _load();
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = jsonDecode(prefs.getString(storageKey) ?? '{}');
      if (data is Map) {
        for (final entry in data.entries) {
          if (entry.key is String && entry.value is num) {
            final value = (entry.value as num).toDouble();
            if (value.isFinite) {
              final id = entry.key as String;
              final stored = value.clamp(0.0, 1.0).toDouble();
              if (stored > fraction(id)) {
                _values[id] = stored;
              }
            }
          }
        }
      }
      notifyListeners();
    } catch (_) {
      saveFailed = true;
    }
  }

  void record(String id, double value) {
    if (!value.isFinite) return;
    final next = value.clamp(0.0, 1.0).toDouble();
    if (next <= fraction(id)) return;
    final oldPercent = percent(id);
    _values[id] = next;
    if (percent(id) != oldPercent) {
      notifyListeners();
    }
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), () => unawaited(flush()));
  }

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    _writes = _writes.then((_) async {
      try {
        await load();
        final prefs = await SharedPreferences.getInstance();
        saveFailed = !await prefs.setString(storageKey, jsonEncode(_values));
      } catch (_) {
        saveFailed = true;
      }
    });
    return _writes;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
