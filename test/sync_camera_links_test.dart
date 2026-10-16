import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/sync_pairing_invite.dart';
import 'package:documentz/data/sync_pairing_links.dart';
import 'package:documentz/features/sync_qr.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('documentz/sync');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SyncPairingLinks.stop();
  });
  tearDown(() {
    SyncPairingLinks.stop();
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'camera scan uses the sync bridge and cancellation is harmless',
    () async {
      var scans = 0;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'scanSyncQr');
        scans++;
        return null;
      });
      expect(await scanSyncQr(), isNull);
      expect(scans, 1);
    },
  );
  test('camera permission failures retain specific feedback', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'camera_permission',
        message: 'Allow camera access for DocumentZ.',
      );
    });
    await expectLater(
      scanSyncQr(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('camera access'),
        ),
      ),
    );
  });
  test('pending links are consumed once on cold launch and later foreground deliveries', () async {
    const invite = SyncPairingInvite(
      addresses: ['192.168.1.5:45831'],
      code: 'AAAAAAAAAAAAAAAAAAAAAA',
    );
    String? pending = invite.encode();
    final seen = <String>[];
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      final next = pending;
      pending = null;
      return next;
    });
    await SyncPairingLinks.start(seen.add);
    await SyncPairingLinks.poll();
    expect(seen, [invite.encode()]);
    pending = invite.encode();
    await SyncPairingLinks.poll();
    expect(seen, [invite.encode(), invite.encode()]);
    expect(
      methods.every((method) => method == 'takePairingLink'),
      isTrue,
      reason: 'Receiving a link must not approve pairing or start a transfer.',
    );
    SyncPairingLinks.stop();
    pending = invite.encode();
    await SyncPairingLinks.poll();
    expect(seen.length, 2);
  });
  test(
    'pairing links reject other hosts, paths, query parameters and versions',
    () {
      const invite = SyncPairingInvite(
        addresses: ['10.0.0.2:45831'],
        code: 'AAAAAAAAAAAAAAAAAAAAAA',
      );
      final fragment = Uri.parse(invite.encode()).fragment;
      for (final raw in [
        'https://pair#$fragment',
        'documentz://pair.example.com#$fragment',
        'documentz://someone@pair#$fragment',
        'documentz://pair:80#$fragment',
        'documentz://pair/extra#$fragment',
        'documentz://pair?redirect=https://example.com#$fragment',
        'documentz://pair#v2=bad',
      ]) {
        expect(() => SyncPairingInvite.parse(raw), throwsFormatException);
      }
    },
  );
}
