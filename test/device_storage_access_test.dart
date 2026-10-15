import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/device_documents_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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
