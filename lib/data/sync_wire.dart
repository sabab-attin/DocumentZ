import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'sync_crypto.dart';

class SyncWire {
  SyncWire(this.socket) : _input = StreamIterator(socket);
  final Socket socket;
  final StreamIterator<Uint8List> _input;
  Uint8List _chunk = Uint8List(0);
  int _offset = 0;
  static const limit = 24 * 1024 * 1024;
  Future<Uint8List> _read(int length) async {
    final output = Uint8List(length);
    var written = 0;
    while (written < length) {
      if (_offset == _chunk.length) {
        if (!await _input.moveNext().timeout(const Duration(seconds: 90))) {
          throw const SocketException('Sync connection closed.');
        }
        _chunk = _input.current;
        _offset = 0;
      }
      final available = _chunk.length - _offset;
      final count = available < length - written ? available : length - written;
      output.setRange(written, written + count, _chunk, _offset);
      written += count;
      _offset += count;
    }
    return output;
  }

  Future<Map<String, dynamic>> read({int maximum = 4096}) async {
    final header = ByteData.sublistView(await _read(4));
    final length = header.getUint32(0, Endian.big);
    if (length < 2 || length > maximum || length > limit) {
      throw const FormatException('Sync message exceeds the size limit.');
    }
    final payload = await _read(length);
    final decoded = length > 4096
        ? await _decodeWireMessage(payload)
        : jsonDecode(utf8.decode(payload));
    return Map<String, dynamic>.from(decoded as Map);
  }

  Future<void> write(Map<String, dynamic> message) async {
    final data = await _encodeWireMessage(message);
    if (data.length > limit) {
      throw const FormatException('Annotations are too large for one sync.');
    }
    final header = ByteData(4)..setUint32(0, data.length, Endian.big);
    socket.add(header.buffer.asUint8List());
    socket.add(data);
    await socket.flush().timeout(const Duration(seconds: 30));
  }

  Future<void> send(SyncCipher cipher, Map<String, dynamic> message) async =>
      write(await cipher.seal(message));
  Future<Map<String, dynamic>> receive(SyncCipher cipher) async =>
      cipher.open(await read(maximum: limit));
  void close() {
    socket.destroy();
    unawaited(_input.cancel());
  }
}

bool isSyncLocalAddress(String host) {
  final address = InternetAddress.tryParse(host);
  if (address == null || address.type != InternetAddressType.IPv4) {
    return false;
  }
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254) ||
      b[0] == 127;
}

Future<Object?> _decodeWireMessage(Uint8List bytes) =>
    Isolate.run(() => jsonDecode(utf8.decode(bytes)));
Future<List<int>> _encodeWireMessage(Map<String, dynamic> message) =>
    Isolate.run(() => utf8.encode(jsonEncode(message)));
