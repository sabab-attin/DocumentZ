import 'dart:async';

import 'package:flutter/services.dart';

/// Native observers and background jobs keep deltas until Flutter saves them.
class AutomaticDeviceChanges {
  static const channel = MethodChannel('documentz/library_index');
  static Future<void> Function(Map<String, dynamic>)? _apply;
  static bool _reading = false, _again = false;
  static DateTime? _lastRequest;
  static int _generation = 0;
  static Timer? _retry;
  static int _retrySeconds = 5;

  static void start(Future<void> Function(Map<String, dynamic>) apply) {
    if (_apply != null) return;
    _apply = apply;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') await _poll();
    });
    unawaited(_poll());
  }

  static Future<void> requestRefresh() async {
    final now = DateTime.now();
    if (_lastRequest != null && now.difference(_lastRequest!).inSeconds < 5) {
      return;
    }
    _lastRequest = now;
    try {
      await channel.invokeMethod<void>('refresh');
    } on MissingPluginException {
      // Only Android has a native change journal.
    } on PlatformException {
      // Keep the saved list usable; a later observer/job will retry.
    }
  }

  static Future<void> _poll() async {
    if (_reading) {
      _again = true;
      return;
    }
    final generation = _generation;
    _reading = true;
    try {
      do {
        _again = false;
        final raw = await channel.invokeMapMethod<String, dynamic>('changes');
        if (generation != _generation) return;
        if (raw != null && raw['scope'] is String) {
          await _apply?.call(raw);
          if (generation != _generation) return;
          await channel.invokeMethod<void>('acknowledge', {
            'revision': raw['revision'],
          });
          _retry?.cancel();
          _retry = null;
          _retrySeconds = 5;
        }
      } while (_again && generation == _generation);
    } on MissingPluginException {
      // Existing saved indexes remain usable during development.
    } on PlatformException {
      // The native journal retains changes until they are saved successfully.
      _scheduleRetry(generation);
    } catch (_) {
      // Do not acknowledge a failed cache write. Retry on the next notification.
      _scheduleRetry(generation);
    } finally {
      if (generation == _generation) _reading = false;
    }
  }

  static void _scheduleRetry(int generation) {
    if (generation != _generation || _apply == null || _retry != null) return;
    _retry = Timer(Duration(seconds: _retrySeconds), () {
      _retry = null;
      if (generation == _generation) unawaited(_poll());
    });
    _retrySeconds = _retrySeconds >= 30 ? 60 : _retrySeconds * 2;
  }

  static void stop() {
    _generation++;
    _apply = null;
    _reading = false;
    _again = false;
    _lastRequest = null;
    _retry?.cancel();
    _retry = null;
    _retrySeconds = 5;
    channel.setMethodCallHandler(null);
  }
}
