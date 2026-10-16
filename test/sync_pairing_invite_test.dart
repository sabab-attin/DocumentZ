import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:documentz/data/sync_pairing_invite.dart';
import 'package:documentz/features/sync_qr.dart';

void main() {
  const code = 'AAAAAAAAAAAAAAAAAAAAAA';
  test(
    'pairing QR round trips local addresses without persistent credentials',
    () {
      const invite = SyncPairingInvite(
        addresses: ['192.168.1.4:45831', '10.0.0.2:45831'],
        code: code,
      );
      final parsed = SyncPairingInvite.parse(invite.encode());
      expect(parsed.addresses, invite.addresses);
      expect(parsed.code, code);
      final uri = Uri.parse(invite.encode());
      expect(uri.scheme, 'documentz');
      expect(uri.host, 'pair');
      expect(uri.query, isEmpty);
      final legacy = '${SyncPairingInvite.prefix}${uri.fragment.substring(3)}';
      expect(SyncPairingInvite.parse(legacy).code, code);
    },
  );
  test(
    'pairing QR rejects public addresses, URLs, bad keys and oversized input',
    () {
      for (final addresses in [
        <String>[],
        ['8.8.8.8:45831'],
        ['127.0.0.1:45831'],
        ['192.168.1.2:0'],
        ['192.168.1.2:65536'],
        ['192.168.1.2:80/path'],
        ['file:///secret'],
      ]) {
        expect(
          () => SyncPairingInvite.parse(
            SyncPairingInvite(addresses: addresses, code: code).encode(),
          ),
          throwsFormatException,
        );
      }
      expect(
        () => SyncPairingInvite.parse('https://example.com'),
        throwsFormatException,
      );
      expect(
        () => SyncPairingInvite.parse(List.filled(5000, 'x').join()),
        throwsFormatException,
      );
      final badPayload = base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'addresses': ['10.1.1.1:45831'],
            'code': 'bad',
          }),
        ),
      );
      expect(
        () => SyncPairingInvite.parse('${SyncPairingInvite.prefix}$badPayload'),
        throwsFormatException,
      );
    },
  );
  test('actual QR pixels decode locally back into the validated invite', () {
    const invite = SyncPairingInvite(
      addresses: ['192.168.1.4:45831'],
      code: code,
    );
    final qr = QrImage(
      QrCode.fromData(
        data: invite.encode(),
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );
    final raster = img.Image(
      width: (qr.moduleCount + 8) * 5,
      height: (qr.moduleCount + 8) * 5,
    );
    img.fill(raster, color: img.ColorRgb8(255, 255, 255));
    for (var y = 0; y < qr.moduleCount; y++) {
      for (var x = 0; x < qr.moduleCount; x++) {
        if (!qr.isDark(y, x)) continue;
        img.fillRect(
          raster,
          x1: (x + 4) * 5,
          y1: (y + 4) * 5,
          x2: (x + 5) * 5 - 1,
          y2: (y + 5) * 5 - 1,
          color: img.ColorRgb8(0, 0, 0),
        );
      }
    }
    final decoded = decodeSyncQrImage(
      Uint8List.fromList(img.encodePng(raster)),
    );
    expect(SyncPairingInvite.parse(decoded).addresses, invite.addresses);
  });
}
