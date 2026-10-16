import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/nearby_sync_io.dart';
import 'package:documentz/data/sync_pairing_invite.dart';
import 'package:documentz/data/sync_wire.dart';
import 'package:documentz/data/sync_crypto.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const peer = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const code = 'AAAAAAAAAAAAAAAAAAAAAA';
  const descriptor = {
    'link': 'test-link',
    'peer': peer,
    'incoming': false,
    'binding': '4321',
  };
  const codec = StandardMethodCodec();
  Future<void> event(String name, Map<String, dynamic> data) async {
    await messenger.handlePlatformMessage(
      'documentz/nearby',
      codec.encodeMethodCall(MethodCall(name, data)),
      null,
    );
  }

  late NearbySyncTransport transport;
  setUp(() {
    transport = NearbySyncTransport();
    messenger.setMockMethodCallHandler(NearbySyncTransport.channel, (
      call,
    ) async {
      return call.method == 'connect' ? descriptor : null;
    });
  });
  tearDown(() async {
    await transport.stop();
    messenger.setMockMethodCallHandler(NearbySyncTransport.channel, null);
  });

  test('direct QR identifies the intended phone without IP, gateway or permanent secret', () {
    const invite = SyncPairingInvite(addresses: [], code: code, nearbyId: peer);
    final parsed = SyncPairingInvite.parse(invite.encode());
    expect(parsed.addresses, isEmpty);
    expect(parsed.nearbyId, peer);
    expect(parsed.code, code);
    for (final bad in ['', '../phone', '8.8.8.8', 'a' * 33]) {
      expect(
        () => SyncPairingInvite.parse(
          SyncPairingInvite(addresses: [], code: code, nearbyId: bad).encode(),
        ),
        throwsFormatException,
      );
    }
    expect(
      () => SyncPairingInvite.parse(
        const SyncPairingInvite(addresses: [], code: code).encode(),
      ),
      throwsFormatException,
    );
  });

  test('denied Nearby permission keeps clear feedback', () async {
    messenger.setMockMethodCallHandler(NearbySyncTransport.channel, (
      call,
    ) async {
      if (call.method == 'start') {
        throw PlatformException(
          code: 'permission',
          message: 'Allow Nearby devices access.',
        );
      }
      return null;
    });
    await expectLater(
      transport.start(peer),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Nearby devices'),
        ),
      ),
    );
    await expectLater(transport.connect(peer), throwsFormatException);
  });

  test('large framed messages are chunked below SDK limits and reconstructed exactly', () async {
    final chunks = <Uint8List>[];
    messenger.setMockMethodCallHandler(NearbySyncTransport.channel, (
      call,
    ) async {
      if (call.method == 'connect') {
        return descriptor;
      }
      if (call.method == 'send') {
        chunks.add((call.arguments as Map)['bytes'] as Uint8List);
      }
      return null;
    });
    await transport.start(peer);
    final link = await transport.connect(peer);
    final message = {'kind': 'test', 'text': List.filled(70000, 'x').join()};
    await link.wire.write(message);
    expect(chunks.length, greaterThan(2));
    expect(
      chunks.every((chunk) => chunk.length <= 32000 && chunk.isNotEmpty),
      isTrue,
    );
    final all = Uint8List.fromList(chunks.expand((chunk) => chunk).toList());
    expect(ByteData.sublistView(all).getUint32(0), all.length - 4);
    expect(jsonDecode(utf8.decode(all.sublist(4))), message);
    final reading = link.wire.read(maximum: SyncWire.limit);
    for (var offset = 0; offset < all.length; offset += 2000) {
      final end = offset + 2000 < all.length ? offset + 2000 : all.length;
      await event('bytes', {
        'link': 'test-link',
        'bytes': Uint8List.sublistView(all, offset, end),
      });
    }
    expect(await reading, message);
  });

  test('a mismatched or missing nearby identity binding is rejected', () async {
    await transport.start(peer);
    final link = await transport.connect(peer);
    expect(link.wire.binding, 'nearby:4321');
    validateSyncTransportBinding(link.wire, {
      'transportBinding': 'nearby:4321',
    });
    expect(
      () => validateSyncTransportBinding(link.wire, {}),
      throwsFormatException,
    );
    expect(
      () => validateSyncTransportBinding(link.wire, {
        'transportBinding': 'nearby:9999',
      }),
      throwsFormatException,
    );
  });

  test('the authenticated cipher works over fragmented transport streams in both directions', () async {
    final leftInput = StreamController<Uint8List>(),
        rightInput = StreamController<Uint8List>();
    Future<void> fragment(
      StreamController<Uint8List> target,
      List<int> bytes,
    ) async {
      for (var offset = 0; offset < bytes.length; offset += 113) {
        final end = offset + 113 < bytes.length ? offset + 113 : bytes.length;
        target.add(Uint8List.fromList(bytes.sublist(offset, end)));
      }
    }

    final left = SyncWire.transport(
      leftInput.stream,
      write: (bytes) => fragment(rightInput, bytes),
      close: () {},
    );
    final right = SyncWire.transport(
      rightInput.stream,
      write: (bytes) => fragment(leftInput, bytes),
      close: () {},
    );
    final first = List<int>.filled(32, 11), second = List<int>.filled(32, 22);
    final leftCipher = SyncCipher(first, second, [1, 2, 3]);
    final rightCipher = SyncCipher(second, first, [1, 2, 3]);
    final message = {
      'kind': 'annotations',
      'note': 'বাংলা — مرحبا — **saved note**',
      'data': List.filled(40000, 'x').join(),
    };
    try {
      final reading = right.receive(rightCipher);
      await left.send(leftCipher, message);
      expect(await reading, message);
      final reply = left.receive(leftCipher);
      await right.send(rightCipher, {'kind': 'saved', 'digest': 'test-digest'});
      expect((await reply)['kind'], 'saved');
    } finally {
      left.close();
      right.close();
      await leftInput.close();
      await rightInput.close();
    }
  });

  test('disconnect during a partial message fails instead of reporting a completed transfer', () async {
    await transport.start(peer);
    final link = await transport.connect(peer);
    final reading = link.wire.read();
    final failure = expectLater(reading, throwsA(isA<SocketException>()));
    await event('bytes', {
      'link': 'test-link',
      'bytes': Uint8List.fromList([0, 0]),
    });
    await event('disconnected', {'link': 'test-link'});
    await failure;
  });

  test('a failed native send is surfaced with its retry feedback', () async {
    await transport.start(peer);
    final link = await transport.connect(peer);
    messenger.setMockMethodCallHandler(NearbySyncTransport.channel, (
      call,
    ) async {
      if (call.method == 'send') {
        throw PlatformException(
          code: 'nearby',
          message: 'The transfer was interrupted. Retry sync safely.',
        );
      }
      return null;
    });
    await expectLater(
      link.wire.write({'kind': 'test'}),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('Retry sync safely'),
        ),
      ),
    );
  });

  test(
    'a connection closed before connect returns cannot be resurrected',
    () async {
      messenger.setMockMethodCallHandler(NearbySyncTransport.channel, (
        call,
      ) async {
        if (call.method == 'connect') {
          await event('disconnected', {'link': 'test-link'});
          return descriptor;
        }
        return null;
      });
      await transport.start(peer);
      await expectLater(transport.connect(peer), throwsFormatException);
    },
  );
}
