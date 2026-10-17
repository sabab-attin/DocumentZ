import 'dart:async';

import 'package:documentz/data/automatic_device_changes.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final channel = AutomaticDeviceChanges.channel;
  tearDown(() {
    AutomaticDeviceChanges.stop();
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'a background change is acknowledged only after its cache write succeeds',
    () async {
      final started = Completer<void>();
      final saved = Completer<void>();
      final acknowledged = Completer<void>();
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'changes') {
          return {
            'scope': 'allowed',
            'revision': 12,
            'files': [],
            'removed': [],
          };
        }
        if (call.method == 'acknowledge') {
          expect((call.arguments as Map)['revision'], 12);
          acknowledged.complete();
        }
        return null;
      });
      AutomaticDeviceChanges.start((raw) async {
        started.complete();
        await saved.future;
      });
      await started.future;
      expect(acknowledged.isCompleted, isFalse);
      saved.complete();
      await acknowledged.future;
    },
  );

  test(
    'a failed cache write leaves native changes unacknowledged for retry',
    () async {
      final attempted = Completer<void>();
      var acknowledgements = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'changes') {
          return {
            'scope': 'allowed',
            'revision': 13,
            'files': [],
            'removed': [],
          };
        }
        if (call.method == 'acknowledge') acknowledgements++;
        return null;
      });
      AutomaticDeviceChanges.start((raw) async {
        attempted.complete();
        throw StateError('Storage is temporarily unavailable.');
      });
      await attempted.future;
      await Future<void>.delayed(Duration.zero);
      expect(acknowledgements, 0);
    },
  );
}
