import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:documentz/data/android_lan_connection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(androidLanChannel, null));
  test('Wi-Fi route uses a token-authenticated loopback stream without changing the sync payload', () async {
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final received = Completer<List<int>>();
    final peers = <Socket>[];
    proxy.listen((peer) {
      peers.add(peer);
      final data = <int>[];
      peer.listen((chunk) {
        data.addAll(chunk);
        if (data.length >= 32 + 15 && !received.isCompleted) {
          received.complete(data);
        }
      });
    });
    const token = '0123456789abcdef0123456789abcdef';
    messenger.setMockMethodCallHandler(androidLanChannel, (call) async {
      expect(call.method, 'connect');
      expect((call.arguments as Map)['host'], '192.168.1.20');
      return {'id': token, 'port': proxy.port};
    });
    final socket = await connectAndroidLan(
      InternetAddress('192.168.1.20'),
      45831,
      const Duration(seconds: 4),
    );
    try {
      socket.add(ascii.encode('encrypted-frame'));
      await socket.flush();
      final data = await received.future.timeout(const Duration(seconds: 2));
      expect(ascii.decode(data.take(32).toList()), token);
      expect(ascii.decode(data.skip(32).toList()), 'encrypted-frame');
    } finally {
      socket.destroy();
      for (final peer in peers) {
        peer.destroy();
      }
      await proxy.close();
    }
  });
  test('VPN/default-network and missing-plugin fallback preserve the ordinary socket route', () async {
    for (final missing in [false, true]) {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <Socket>[];
      server.listen(peers.add);
      messenger.setMockMethodCallHandler(androidLanChannel, (call) async {
        if (missing) throw MissingPluginException();
        return null;
      });
      final socket = await connectAndroidLan(
        InternetAddress.loopbackIPv4,
        server.port,
        const Duration(seconds: 2),
      );
      socket.destroy();
      for (final peer in peers) {
        peer.destroy();
      }
      await server.close();
    }
  });
  test(
    'malformed native proxy capabilities are rejected before opening a stream',
    () async {
      messenger.setMockMethodCallHandler(
        androidLanChannel,
        (_) async => {'id': 'wrong', 'port': 45831},
      );
      await expectLater(
        connectAndroidLan(
          InternetAddress('192.168.1.20'),
          45831,
          const Duration(seconds: 2),
        ),
        throwsFormatException,
      );
    },
  );
}
