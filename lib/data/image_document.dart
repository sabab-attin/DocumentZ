import 'dart:typed_data';

import 'package:image/image.dart' as img;

List<Uint8List> tiffPages(Uint8List bytes) {
  final decoder = img.TiffDecoder();
  final info = decoder.startDecode(bytes);
  if (info == null) {
    throw const FormatException('This TIFF could not be decoded.');
  }
  if (decoder.numFrames() > 200) {
    throw const FormatException(
      'This TIFF has more than 200 pages. Split it first.',
    );
  }
  final frames = <Uint8List>[];
  int total = 0;
  for (int i = 0; i < decoder.numFrames(); i++) {
    final page = decoder.decodeFrame(i);
    if (page == null) {
      throw FormatException('Could not read TIFF page ${i + 1}.');
    }
    total += page.width * page.height;
    if (total > 80 * 1000 * 1000) {
      throw const FormatException(
        'This scan is too large to decode. Split it into smaller files.',
      );
    }
    frames.add(img.encodePng(page));
  }
  return frames;
}

Uint8List bmpPage(Uint8List bytes) {
  final image = img.decodeBmp(bytes);
  if (image == null) {
    throw const FormatException('This BMP could not be decoded.');
  }
  return img.encodePng(image);
}
