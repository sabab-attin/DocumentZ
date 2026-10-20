import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ReaderPlatform {
  static const channel = MethodChannel('documentz/appearance');
  static bool get isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<void> landscape(bool enabled) async {
    if (!isAndroid) return;
    await channel.invokeMethod<void>('landscape', {'enabled': enabled});
  }

  static Future<void> restoreOrientation() async {
    try {
      await landscape(false);
    } on PlatformException {
      // A disposed reader must not report an unhandled platform cleanup error.
    } on MissingPluginException {
      // Tests and older installed platform implementations.
    }
  }

  static Future<void> fullscreen(bool enabled) async {
    if (kIsWeb ||
        (!isAndroid && defaultTargetPlatform != TargetPlatform.windows)) {
      return;
    }
    try {
      await channel.invokeMethod<void>('fullscreen', {'enabled': enabled});
    } on PlatformException {
      /* Leave document navigation usable. */
    } on MissingPluginException {
      /* Widget tests and older installed builds. */
    }
  }
}
