import 'dart:typed_data';

const mobilePdfSupported = false;
Future<Uint8List?> scanPdf() async =>
    throw UnsupportedError('Scanning requires Android or iOS.');
Future<Uint8List> recognizePdf(
  Uint8List bytes,
  void Function(int) progress,
) async => throw UnsupportedError('OCR requires Android or iOS.');
