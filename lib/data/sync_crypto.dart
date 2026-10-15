import 'dart:convert';
import 'dart:math';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'sync_graph.dart';

Uint8List syncRandomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
}

String syncEncode(List<int> bytes) =>
    base64UrlEncode(bytes).replaceAll('=', '');
Uint8List syncDecode(String text, int length) {
  final result = base64Url.decode(base64Url.normalize(text));
  if (result.length != length) {
    throw const FormatException('Invalid sync key.');
  }
  return result;
}

Future<String> syncProof(List<int> secret, Object message) async => syncEncode(
  (await Hmac.sha256().calculateMac(
    utf8.encode(syncCanonical(message)),
    secretKey: SecretKey(secret),
  )).bytes,
);
Future<void> verifySyncProof(
  List<int> secret,
  Object message,
  String proof,
) async {
  final actual = syncDecode(await syncProof(secret, message), 32);
  final supplied = syncDecode(proof, 32);
  var difference = 0;
  for (var i = 0; i < 32; i++) {
    difference |= actual[i] ^ supplied[i];
  }
  if (difference != 0) {
    throw const FormatException('Device authentication failed.');
  }
}

/// Keys are directional and ephemeral. Every message authenticates its session,
/// direction and sequence number; replays and cross-session copies are rejected.
class SyncCipher {
  SyncCipher(this.sendKey, this.receiveKey, this.context);
  final List<int> sendKey, receiveKey, context;
  int _sent = 0, _received = 0;
  Future<Map<String, dynamic>> seal(Map<String, dynamic> message) {
    final count = _sent++;
    final key = sendKey, aad = context;
    return Isolate.run(() => _sealSyncMessage(message, key, aad, count));
  }

  Future<Map<String, dynamic>> open(Map<String, dynamic> message) async {
    if (message['n'] != _received) {
      throw const FormatException('Out-of-order sync message.');
    }
    final count = _received;
    final key = receiveKey, aad = context;
    final result = await Isolate.run(
      () => _openSyncMessage(message, key, aad, count),
    );
    _received++;
    return result;
  }
}

List<int> _syncNonce(int counter) =>
    (ByteData(12)..setUint64(4, counter, Endian.big)).buffer.asUint8List();
Future<Map<String, dynamic>> _sealSyncMessage(
  Map<String, dynamic> message,
  List<int> key,
  List<int> context,
  int count,
) async {
  final box = await Chacha20.poly1305Aead().encrypt(
    utf8.encode(jsonEncode(message)),
    secretKey: SecretKey(key),
    nonce: _syncNonce(count),
    aad: context,
  );
  return {
    'n': count,
    'cipher': syncEncode(box.cipherText),
    'tag': syncEncode(box.mac.bytes),
  };
}

Future<Map<String, dynamic>> _openSyncMessage(
  Map<String, dynamic> message,
  List<int> key,
  List<int> context,
  int count,
) async {
  final ciphertext = base64Url.decode(
    base64Url.normalize(message['cipher'] as String),
  );
  final clear = await Chacha20.poly1305Aead().decrypt(
    SecretBox(
      ciphertext,
      nonce: _syncNonce(count),
      mac: Mac(syncDecode(message['tag'] as String, 16)),
    ),
    secretKey: SecretKey(key),
    aad: context,
  );
  return Map<String, dynamic>.from(jsonDecode(utf8.decode(clear)) as Map);
}

Future<({SyncCipher cipher, String verification})> makeSyncCipher({
  required SimpleKeyPair localKey,
  required String remoteKey,
  required List<int> secret,
  required Object transcript,
  required bool client,
}) async {
  final shared = await X25519().sharedSecretKey(
    keyPair: localKey,
    remotePublicKey: SimplePublicKey(
      syncDecode(remoteKey, 32),
      type: KeyPairType.x25519,
    ),
  );
  final sharedBytes = await shared.extractBytes();
  if (sharedBytes.every((byte) => byte == 0)) {
    throw const FormatException('Invalid key exchange.');
  }
  final hash = (await Sha256().hash(utf8.encode(syncCanonical(transcript))))
      .bytes;
  final keys =
      await (await Hkdf(hmac: Hmac.sha256(), outputLength: 64).deriveKey(
        secretKey: shared,
        nonce: secret,
        info: [...utf8.encode('DocumentZ local sync v1'), ...hash],
      )).extractBytes();
  final first = keys.sublist(0, 32), second = keys.sublist(32);
  final check = (await Hmac.sha256().calculateMac(
    hash,
    secretKey: SecretKey(keys),
  )).bytes;
  final digits = ByteData.sublistView(Uint8List.fromList(check))
      .getUint32(0)
      .toString()
      .padLeft(10, '0');
  return (
    cipher: SyncCipher(client ? first : second, client ? second : first, hash),
    verification: '${digits.substring(0, 5)} ${digits.substring(5)}',
  );
}
