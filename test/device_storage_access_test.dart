import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/device_documents_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'no connected folders needs no disk cache or native storage calls',
    () async {
      if (supportsDeviceStorageAccess) return;
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      var calls = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls++;
        throw MissingPluginException(call.method);
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      for (final refresh in [false, true, false]) {
        final scan = await scanDeviceDocuments(refresh: refresh);
        expect(scan.documents, isEmpty);
        expect(scan.folders, isEmpty);
        expect(scan.errors, isEmpty);
      }
      expect(deviceDocumentIndexing, isFalse);
      expect(calls, 0);
    },
  );
  test(
    'non-Android storage access does not invoke Android permission channels',
    () async {
      if (supportsDeviceStorageAccess) {
        return;
      }
      var calls = 0;
      const channel = MethodChannel('documentz/device_documents');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            calls++;
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await hasDeviceStorageAccess(), isFalse);
      expect(await requestDeviceStorageAccess(), isFalse);
      expect(calls, 0);
    },
  );
}
