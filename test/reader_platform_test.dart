import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/core/reader_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'reader fullscreen entry and exit call the Android system-bar bridge',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(ReaderPlatform.channel, (call) async {
            calls.add(call);
            return null;
          });
      try {
        await ReaderPlatform.fullscreen(true);
        await ReaderPlatform.fullscreen(false);
        expect(calls.map((call) => call.method), ['fullscreen', 'fullscreen']);
        expect(calls.map((call) => call.arguments['enabled']), [true, false]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(ReaderPlatform.channel, null);
      }
    },
  );
}
