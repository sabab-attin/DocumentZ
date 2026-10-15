import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:documentz/data/sync_crypto.dart';
import 'package:documentz/data/sync_wire.dart';

void main() {
  test(
    'pairing proof rejects a wrong secret and a changed transcript',
    () async {
      final secret = syncRandomBytes(16);
      final proof = await syncProof(secret, {'role': 'client', 'nonce': 'one'});
      await verifySyncProof(secret, {'role': 'client', 'nonce': 'one'}, proof);
      await expectLater(
        verifySyncProof(syncRandomBytes(16), {
          'role': 'client',
          'nonce': 'one',
        }, proof),
        throwsFormatException,
      );
      await expectLater(
        verifySyncProof(secret, {'role': 'client', 'nonce': 'two'}, proof),
        throwsFormatException,
      );
    },
  );
  test('ephemeral sessions authenticate both directions, reject tampering and replay', () async {
    final a = await X25519().newKeyPair(), b = await X25519().newKeyPair();
    final secret = syncRandomBytes(32);
    final transcript = {
      'clientNonce': syncEncode(syncRandomBytes(32)),
      'serverNonce': syncEncode(syncRandomBytes(32)),
    };
    final client = await makeSyncCipher(
      localKey: a,
      remoteKey: syncEncode((await b.extractPublicKey()).bytes),
      secret: secret,
      transcript: transcript,
      client: true,
    );
    final server = await makeSyncCipher(
      localKey: b,
      remoteKey: syncEncode((await a.extractPublicKey()).bytes),
      secret: secret,
      transcript: transcript,
      client: false,
    );
    expect(client.verification, server.verification);
    final packet = await client.cipher.seal({'text': 'Private note'});
    expect(jsonEncode(packet), isNot(contains('Private note')));
    final altered = Map<String, dynamic>.from(packet);
    final bytes = base64Url.decode(
      base64Url.normalize(packet['cipher'] as String),
    );
    bytes[0] ^= 1;
    altered['cipher'] = syncEncode(bytes);
    await expectLater(
      server.cipher.open(altered),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
    expect((await server.cipher.open(packet))['text'], 'Private note');
    await expectLater(server.cipher.open(packet), throwsFormatException);
    final response = await server.cipher.seal({'ok': true});
    expect((await client.cipher.open(response))['ok'], true);
    final fresh = await makeSyncCipher(
      localKey: a,
      remoteKey: syncEncode((await b.extractPublicKey()).bytes),
      secret: secret,
      transcript: {'differentSession': true},
      client: false,
    );
    await expectLater(
      fresh.cipher.open(packet),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
  test(
    'framed transport handles split packets and rejects oversized lengths',
    () async {
      final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final accepted = listener.first;
      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        listener.port,
      );
      final server = SyncWire(await accepted);
      addTearDown(() async {
        client.destroy();
        server.close();
        await listener.close();
      });
      final payload = utf8.encode(jsonEncode({'message': 'split packet'}));
      final header = (ByteData(
        4,
      )..setUint32(0, payload.length, Endian.big)).buffer.asUint8List();
      client.add(header.sublist(0, 2));
      await client.flush();
      client.add(header.sublist(2));
      client.add(payload);
      await client.flush();
      expect((await server.read())['message'], 'split packet');
      client.add(
        (ByteData(
          4,
        )..setUint32(0, SyncWire.limit + 1, Endian.big)).buffer.asUint8List(),
      );
      await client.flush();
      await expectLater(server.read(), throwsFormatException);
    },
  );
  test('direct sync accepts only local IPv4 addresses, never public hosts', () {
    for (final host in [
      '192.168.1.20',
      '10.0.0.2',
      '172.16.0.2',
      '169.254.1.2',
      '127.0.0.1',
    ]) {
      expect(isSyncLocalAddress(host), isTrue);
    }
    for (final host in [
      '8.8.8.8',
      'example.com',
      '172.32.0.1',
      '0.0.0.0',
      '255.255.255.255',
      '::1',
    ]) {
      expect(isSyncLocalAddress(host), isFalse);
    }
  });
}
