import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/services.dart';
import 'local_annotation_sync.dart';

/// Owned by ReaderShell, rather than the settings route. No pairing can be
/// approved without a visible confirmation screen.
class AnnotationSyncSession with WidgetsBindingObserver {
  AnnotationSyncSession._(this.library) {
    WidgetsBinding.instance.addObserver(this);
  }
  static final _sessions = Expando<AnnotationSyncSession>();
  static AnnotationSyncSession forLibrary(ImportableLibrary library) =>
      _sessions[library] ??= AnnotationSyncSession._(library);
  @visibleForTesting
  static AnnotationSyncSession withEngine(
    ImportableLibrary library,
    LocalAnnotationSync engine,
  ) {
    final session = AnnotationSyncSession._(library).._engine = engine;
    _sessions[library] = session;
    return session;
  }

  static const preferenceKey = 'documentz.localSync.enabled.v1';
  final ImportableLibrary library;
  LocalAnnotationSync? _engine;
  LocalAnnotationSync get engine =>
      _engine ??= LocalAnnotationSync(library, approve: (_, _) async => false);
  bool _wanted = false, _disposed = false;
  Future<void>? _restore;
  Future<void> restore() => _restore ??= _restoreSetting();
  Future<void> _restoreSetting() async {
    final SharedPreferences preferences;
    try {
      preferences = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    if (_disposed) return;
    engine.setNearbyMode(
      preferences.getBool('documentz.sync.directNearby.v1') ?? true,
    );
    _wanted = preferences.getBool(preferenceKey) ?? false;
    if (_wanted && localSyncAvailable) {
      await engine.start();
      if (engine.enabled) {
        engine.allowPairing();
      } else {
        _wanted = false;
        await preferences.setBool(preferenceKey, false);
      }
    }
  }

  Future<void> setEnabled(bool value) async {
    await restore();
    if (_disposed) return;
    _wanted = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(preferenceKey, value);
    if (value) {
      await engine.start();
      if (engine.enabled && !engine.busy) {
        engine.allowPairing();
      } else if (!engine.enabled) {
        _wanted = false;
        await preferences.setBool(preferenceKey, false);
      }
    } else {
      await engine.stop();
    }
  }

  Future<void> setNearbyMode(bool direct) async {
    if (_disposed || engine.enabled || engine.busy) {
      return;
    }
    engine.setNearbyMode(direct);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('documentz.sync.directNearby.v1', direct);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _wanted &&
        !_disposed &&
        !engine.enabled &&
        !engine.busy) {
      unawaited(engine.start());
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sessions[library] = null;
    _engine?.dispose();
  }
}
