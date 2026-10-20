// Syncfusion's public Flutter API does not expose loaded image replacement or
// stream recompression. Keep that version-specific adapter in this file, pin
// its dependency, and verify output with PDFium and preservation regressions.
// ignore_for_file: implementation_imports
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as image;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/pdf_document/pdf_document.dart'
    show PdfDocumentHelper;
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_array.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_dictionary.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_name.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_number.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_null.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_reference_holder.dart';
import 'package:syncfusion_flutter_pdf/src/pdf/implementation/primitives/pdf_stream.dart';

const _maxDecodedStream = 32 * 1024 * 1024;
Object? _resolve(Object? value) =>
    value is PdfReferenceHolder ? value.object : value;
String? _name(Object? value) => switch (_resolve(value)) {
  PdfName n => n.name,
  _ => null,
};
int? _number(Object? value) {
  final primitive = _resolve(value);
  if (primitive is! PdfNumber) {
    return null;
  }
  final number = primitive.value;
  if (number == null || !number.isFinite || number != number.roundToDouble()) {
    return null;
  }
  return number.toInt();
}

/// Rewrites resource streams in place; page text, graphics and interactive
/// objects remain in the original graph. Unknown codecs and image semantics
/// are left untouched. Only a smaller encoded stream replaces its source.
void optimizePdfResources(
  sf.PdfDocument document, {
  int? imageQuality,
  int? maxImageDimension,
}) {
  final pending = <Object?>[PdfDocumentHelper.getHelper(document).catalog];
  final seen = HashSet<Object>.identity();
  final streams = <PdfStream>[];
  final masks = HashSet<Object>.identity();
  while (pending.isNotEmpty) {
    final value = _resolve(pending.removeLast());
    if (value == null || !seen.add(value)) {
      continue;
    }
    if (value is PdfArray) {
      pending.addAll(value.elements);
    } else if (value is PdfDictionary) {
      pending.addAll(value.items!.values);
      for (final key in ['SMask', 'Mask']) {
        final mask = _resolve(value[key]);
        if (mask != null) {
          masks.add(mask);
        }
      }
      if (value is PdfStream) {
        streams.add(value);
      }
    }
  }
  // Mark complete soft-mask graphs before changing any image, regardless of
  // object traversal order. Transparency masks must never become lossy JPEGs.
  final maskPending = masks.toList();
  final maskSeen = HashSet<Object>.identity();
  while (maskPending.isNotEmpty) {
    final value = _resolve(maskPending.removeLast());
    if (value == null || !maskSeen.add(value)) {
      continue;
    }
    masks.add(value);
    if (value is PdfArray) {
      maskPending.addAll(value.elements.whereType<Object>());
    }
    if (value is PdfDictionary) {
      // Resource trees can refer back to the page; do not traverse parents.
      maskPending.addAll(
        value.items!.entries
            .where((e) => e.key?.name != 'Parent' && e.key?.name != 'P')
            .map((e) => e.value)
            .whereType<Object>(),
      );
    }
  }
  for (final stream in streams) {
    try {
      if (imageQuality != null &&
          !masks.contains(stream) &&
          _name(stream['Subtype']) == 'Image') {
        _optimizeImage(stream, imageQuality, maxImageDimension!);
      }
      _recompressStream(stream);
    } on Exception {
      // Unsupported/malformed resources retain their original encoding.
    }
  }
}

String? _filter(PdfStream stream) {
  final filter = _resolve(stream['Filter']);
  if (filter == null) {
    return '';
  }
  if (filter is PdfArray && filter.count == 1) {
    return _name(filter[0]);
  }
  return _name(filter);
}

void _replace(PdfStream stream, Uint8List bytes, String filter) {
  stream.data = bytes;
  stream.compress = false;
  stream['Filter'] = PdfName(filter);
  stream['Length'] = PdfNumber(bytes.length);
}

void _recompressStream(PdfStream stream) {
  final filter = _filter(stream), original = stream.dataStream;
  if (original == null ||
      original.isEmpty ||
      original.length > _maxDecodedStream ||
      (filter != '' && filter != 'FlateDecode' && filter != 'Fl')) {
    return;
  }
  final decoded = filter == ''
      ? original
      : const ZLibDecoder().decodeBytes(
          original,
          verify: true,
          maxOutputSize: _maxDecodedStream,
        );
  final encoded = const ZLibEncoder().encodeBytes(decoded, level: 9);
  // Allow for a newly added /Filter entry when the stream was uncompressed.
  if (encoded.length + (filter == '' ? 30 : 0) < original.length) {
    // Flate predictors are left encoded, so their DecodeParms stay valid.
    final originalFilter = stream['Filter'];
    _replace(stream, encoded, 'FlateDecode');
    if (filter != '' && originalFilter != null) {
      stream['Filter'] = originalFilter;
    }
  }
}

void _optimizeImage(PdfStream stream, int quality, int dimension) {
  final width = _number(stream['Width']), height = _number(stream['Height']);
  final color = _name(stream['ColorSpace']), filter = _filter(stream);
  final original = stream.dataStream;
  final decode = _resolve(stream['Decode']);
  final channels = color == 'DeviceRGB' ? 3 : 1;
  final identityDecode =
      decode == null ||
      decode is PdfNull ||
      decode is PdfArray &&
          decode.count == channels * 2 &&
          [for (var i = 0; i < decode.count; i++) _number(decode[i]) == i % 2]
              .every((v) => v);
  // Do not reinterpret CMYK, ICC/indexed colour, masks, transparency, decode
  // arrays or uncommon bit depths. Their existing data remains lossless.
  if (!identityDecode ||
      width == null ||
      height == null ||
      width < 64 ||
      height < 64 ||
      width * height > 10000000 ||
      _number(stream['BitsPerComponent']) != 8 ||
      (color != 'DeviceRGB' && color != 'DeviceGray') ||
      [
        'SMask',
        'Mask',
        'ImageMask',
        'Alternates',
        'SMaskInData',
      ].any(stream.containsKey) ||
      original == null ||
      original.length < 1024 ||
      (filter != 'DCTDecode' &&
          filter != 'DCT' &&
          filter != 'FlateDecode' &&
          filter != 'Fl' &&
          filter != '')) {
    return;
  }
  image.Image? pixels;
  if (filter == 'DCTDecode' || filter == 'DCT') {
    var parameters = _resolve(stream['DecodeParms']);
    if (parameters is PdfArray && parameters.count == 1) {
      parameters = _resolve(parameters[0]);
    }
    // DCTDecode defines ColorTransform; unrelated predictor keys written by
    // some producers are ignored by PDF readers. Explicit nondefault colour
    // transforms are left unchanged.
    if (parameters != null &&
        parameters is! PdfNull &&
        !(parameters is PdfDictionary &&
            (!parameters.containsKey('ColorTransform') ||
                _number(parameters['ColorTransform']) == 1 &&
                    color == 'DeviceRGB'))) {
      return;
    }
    // Four-component JPEGs need colour transforms; keep them unchanged.
    final decoder = image.JpegDecoder(maxPixels: 10000000);
    decoder.startDecode(Uint8List.fromList(original));
    final info = decoder.info;
    if (info == null ||
        info.width != width ||
        info.height != height ||
        info.numComponents != (color == 'DeviceRGB' ? 3 : 1)) {
      return;
    }
    pixels = decoder.decodeFrame(0);
  } else {
    final channels = color == 'DeviceRGB' ? 3 : 1;
    var bytes = filter == ''
        ? Uint8List.fromList(original)
        : const ZLibDecoder().decodeBytes(
            original,
            verify: true,
            maxOutputSize: _maxDecodedStream,
          );
    var parameters = _resolve(stream['DecodeParms']);
    if (parameters is PdfArray && parameters.count == 1) {
      parameters = _resolve(parameters[0]);
    }
    if (parameters is PdfDictionary) {
      final predictor = _number(parameters['Predictor']) ?? 1;
      if (predictor != 1) {
        if ((_number(parameters['Columns']) ?? 1) != width ||
            (_number(parameters['Colors']) ?? 1) != channels ||
            (_number(parameters['BitsPerComponent']) ?? 8) != 8) {
          return;
        }
        bytes = _unpredict(bytes, width, height, channels, predictor);
      }
    } else if (parameters != null && parameters is! PdfNull) {
      return;
    }
    if (bytes.length != width * height * channels) {
      return;
    }
    pixels = image.Image.fromBytes(
      width: width,
      height: height,
      bytes: bytes.buffer,
      bytesOffset: bytes.offsetInBytes,
      numChannels: channels,
    );
  }
  if (pixels == null || pixels.width != width || pixels.height != height) {
    return;
  }
  if (math.max(width, height) > dimension) {
    final scale = dimension / math.max(width, height);
    pixels = image.copyResize(
      pixels,
      width: math.max(1, (width * scale).round()),
      height: math.max(1, (height * scale).round()),
      interpolation: image.Interpolation.average,
    );
  }
  final jpeg = Uint8List.fromList(image.encodeJpg(pixels, quality: quality));
  if (jpeg.length + 32 >= original.length) {
    return;
  }
  stream['Width'] = PdfNumber(pixels.width);
  stream['Height'] = PdfNumber(pixels.height);
  stream['ColorSpace'] = PdfName('DeviceRGB');
  stream['BitsPerComponent'] = PdfNumber(8);
  stream.remove('DecodeParms');
  stream.remove('Decode');
  _replace(stream, jpeg, 'DCTDecode');
}

Uint8List _unpredict(
  Uint8List data,
  int width,
  int height,
  int channels,
  int predictor,
) {
  final row = width * channels;
  if (predictor == 2 && data.length == row * height) {
    final result = Uint8List.fromList(data);
    for (var y = 0; y < height; y++) {
      for (var x = channels; x < row; x++) {
        final at = y * row + x;
        result[at] = (result[at] + result[at - channels]) & 255;
      }
    }
    return result;
  }
  if (predictor < 10 || predictor > 15 || data.length != (row + 1) * height) {
    throw const FormatException('Unsupported image predictor.');
  }
  final result = Uint8List(row * height);
  for (var y = 0; y < height; y++) {
    final filter = data[y * (row + 1)];
    if (filter > 4) {
      throw const FormatException('Invalid image predictor.');
    }
    for (var x = 0; x < row; x++) {
      final at = y * row + x;
      final left = x >= channels ? result[at - channels] : 0;
      final up = y > 0 ? result[at - row] : 0;
      final corner = y > 0 && x >= channels ? result[at - row - channels] : 0;
      final value = switch (filter) {
        0 => 0,
        1 => left,
        2 => up,
        3 => (left + up) ~/ 2,
        _ => _paeth(left, up, corner),
      };
      result[at] = (data[y * (row + 1) + x + 1] + value) & 255;
    }
  }
  return result;
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs(), pb = (p - b).abs(), pc = (p - c).abs();
  return pa <= pb && pa <= pc
      ? a
      : pb <= pc
      ? b
      : c;
}
