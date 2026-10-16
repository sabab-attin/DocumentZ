import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android keeps a single pending invitation until Flutter can show its
/// confirmation. Receiving a link never approves a device or starts a transfer.
class SyncPairingLinks {
  static const channel = MethodChannel('documentz/sync');
  static void Function(String)? _onInvite;
  static bool Function(String)? receiver;
  static bool _reading = false, _readAgain = false;

  static Future<void> start(void Function(String) onInvite) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    _onInvite = onInvite;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'pairingLinkAvailable') {
        await poll();
      }
    });
    await poll();
  }

  static bool deliverToScreen(String raw) => receiver?.call(raw) ?? false;

  static Future<void> poll() async {
    if (_onInvite == null) {
      return;
    }
    if (_reading) {
      _readAgain = true;
      return;
    }
    _reading = true;
    try {
      do {
        _readAgain = false;
        final raw = await channel.invokeMethod<String>('takePairingLink');
        if (raw != null && raw.length <= 4096) {
          _onInvite?.call(raw);
        }
      } while (_readAgain && _onInvite != null);
    } on MissingPluginException {
      // Desktop has no Android camera-intent bridge.
    } on PlatformException {
      // In-app scan and manual pairing remain available.
    } finally {
      _reading = false;
    }
  }

  static void stop() {
    _onInvite = null;
    _readAgain = false;
    receiver = null;
    channel.setMethodCallHandler(null);
  }
}
