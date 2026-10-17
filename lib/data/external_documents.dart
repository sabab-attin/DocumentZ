import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExternalDocuments {
  static const channel = MethodChannel('documentz/documents');
  static void Function()? _available;
  static Future<void> start(void Function() available) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    _available = available;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'documentAvailable') _available?.call();
    });
    available();
  }

  static Future<Map<String, dynamic>?> take() async {
    try {
      return await channel.invokeMapMethod<String, dynamic>('takeDocument');
    } on MissingPluginException {
      return null;
    }
  }

  static Future<void> finish(String id) async {
    await channel.invokeMethod<void>('finishDocument', {'id': id});
  }

  static void stop() {
    _available = null;
    channel.setMethodCallHandler(null);
  }
}
