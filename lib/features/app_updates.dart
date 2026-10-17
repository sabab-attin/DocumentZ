import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppUpdatesSettings extends StatefulWidget {
  const AppUpdatesSettings({super.key});
  @override
  State<AppUpdatesSettings> createState() => _AppUpdatesSettingsState();
}

class _AppUpdatesSettingsState extends State<AppUpdatesSettings>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('documentz/updates');
  Map<String, dynamic> _state = {};
  bool _busy = false;
  String? _error;
  Timer? _timer;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_supported) unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_state['downloading'] == true && !_busy) unawaited(_refresh());
    });
  }

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _supported) unawaited(_refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('state');
      if (mounted && value != null) setState(() => _state = value);
    } on PlatformException {
      // Keep the last status during a transient download-service failure.
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = 'Update checks need the updated Android app.');
      }
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _run(String method, [Map<String, dynamic>? arguments]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        method,
        arguments,
      );
      if (mounted && value != null) setState(() => _state = value);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _error =
              error.message ?? 'Could not complete the update request.',
        );
      }
    } on MissingPluginException {
      if (mounted) {
        setState(() => _error = 'Update checks need the updated Android app.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        unawaited(_refresh());
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) return const SizedBox.shrink();
    final available = _state['available'] as String?;
    final downloading = _state['downloading'] == true;
    final ready = _state['ready'] == true;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('App updates', style: Theme.of(context).textTheme.titleLarge),
            if (_state['version'] != null)
              Text('Installed version: ${_state['version']}'),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Automatic update checks'),
              subtitle: const Text(
                'Notify me about new releases. Tap the notification to download.',
              ),
              value: _state['automatic'] == true,
              onChanged: _busy
                  ? null
                  : (value) => _run('automatic', {'enabled': value}),
            ),
            Text(
              _error ??
                  _state['status'] as String? ??
                  'Check GitHub for a newer version.',
            ),
            if (_busy || downloading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: LinearProgressIndicator(),
              ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: _busy || downloading ? null : () => _run('check'),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Check for updates'),
                ),
                if (available != null)
                  FilledButton.icon(
                    onPressed: _busy || downloading
                        ? null
                        : () => _run(ready ? 'install' : 'download'),
                    icon: Icon(ready ? Icons.system_update : Icons.download),
                    label: Text(
                      ready ? 'Install update' : 'Download $available',
                    ),
                  ),
                if (_state['notifications'] == false)
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run('notificationSettings'),
                    child: const Text('Notification settings'),
                  ),
              ],
            ),
            const Text(
              'Checks run periodically when Android allows. Downloads use your current connection. Android asks before installing.',
            ),
          ],
        ),
      ),
    );
  }
}
