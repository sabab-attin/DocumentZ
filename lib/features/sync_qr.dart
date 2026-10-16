import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';
import 'package:zxing2/qrcode.dart' as zx;

Future<String?> scanSyncQr() async {
  if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) {
    return readSyncQrImage();
  }
  try {
    return await const MethodChannel('documentz/sync')
        .invokeMethod<String>('scanSyncQr');
  } on PlatformException catch (error) {
    throw FormatException(
      error.message ?? 'Scanner unavailable. Use a QR image or manual code.',
    );
  }
}

Future<String?> readSyncQrImage() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['png', 'jpg', 'jpeg'],
  );
  if (file == null) return null;
  final size = file.lengthSync() ?? await file.length();
  if (size != null && size > 8 * 1024 * 1024) {
    throw const FormatException('Choose a QR image smaller than 8 MB.');
  }
  return compute(decodeSyncQrImage, await file.readAsBytes());
}

String decodeSyncQrImage(Uint8List bytes) {
  // This is a QR-thumbnail guard, independent of document import sizes.
  if (bytes.length > 8 * 1024 * 1024) {
    throw const FormatException('QR image too large.');
  }
  final decoder = img.findDecoderForData(bytes);
  final info = decoder?.startDecode(bytes);
  if (info == null || info.width * info.height > 24000000) {
    throw const FormatException('Choose a smaller PNG or JPEG QR image.');
  }
  final decoded = decoder!.decodeFrame(0);
  if (decoded == null) {
    throw const FormatException('Could not read this image.');
  }
  final image = decoded.width > 2400 || decoded.height > 2400
      ? img.copyResize(
          decoded,
          width: decoded.width >= decoded.height ? 2400 : null,
          height: decoded.height > decoded.width ? 2400 : null,
        )
      : decoded;
  final pixels = Int32List(image.width * image.height);
  var index = 0;
  for (final pixel in image) {
    pixels[index++] =
        (pixel.r.toInt() << 16) | (pixel.g.toInt() << 8) | pixel.b.toInt();
  }
  final bitmap = zx.BinaryBitmap(
    zx.HybridBinarizer(
      zx.RGBLuminanceSource(image.width, image.height, pixels),
    ),
  );
  try {
    return zx.QRCodeReader().decode(bitmap).text;
  } catch (_) {
    throw const FormatException(
      'No readable QR code found. Try a sharper image.',
    );
  }
}

class SyncQrCode extends StatefulWidget {
  const SyncQrCode({super.key, required this.value});
  final String value;
  @override
  State<SyncQrCode> createState() => _SyncQrCodeState();
}

class _SyncQrCodeState extends State<SyncQrCode> {
  late QrImage image = _encode();
  QrImage _encode() => QrImage(
    QrCode.fromData(
      data: widget.value,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    ),
  );
  @override
  void didUpdateWidget(SyncQrCode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) image = _encode();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Private pairing QR. Expires with the pairing code in ten minutes.',
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: SizedBox.square(
        dimension: 240,
        child: CustomPaint(painter: _QrPainter(image)),
      ),
    ),
  );
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.image);
  final QrImage image;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final cell = size.shortestSide / (image.moduleCount + 8);
    final ink = Paint()
      ..color = Colors.black
      ..isAntiAlias = false;
    for (var y = 0; y < image.moduleCount; y++) {
      for (var x = 0; x < image.moduleCount; x++) {
        if (image.isDark(y, x)) {
          canvas.drawRect(
            Rect.fromLTWH((x + 4) * cell, (y + 4) * cell, cell, cell),
            ink,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) => oldDelegate.image != image;
}
