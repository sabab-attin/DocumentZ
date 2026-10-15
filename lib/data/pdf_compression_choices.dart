import 'dart:math' show min, max;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'pdf_compression.dart';

enum PdfCompressionMode {
  preserve('Original quality', 0, 0),
  balanced('Balanced', 150, 82),
  small('Small', 100, 65),
  smallest('Smallest', 72, 45);

  const PdfCompressionMode(this.label, this.dpi, this.quality);
  final String label;
  final int dpi, quality;
}

class PdfCompressionChoice {
  const PdfCompressionChoice(this.mode, this.size, this.bytes);
  final PdfCompressionMode mode;
  final int size;
  final Uint8List? bytes;
  bool get imageOnly => mode != PdfCompressionMode.preserve;
}

Future<List<PdfCompressionChoice>> measurePdfCompression(
  Uint8List input, {
  required bool Function() cancelled,
  required void Function(double) onProgress,
}) async {
  void check() {
    if (cancelled()) {
      throw const PdfCompressionCancelled();
    }
  }

  check();
  final optimized = await optimizePdf(input);
  check();
  final choices = <PdfCompressionChoice>[];
  // Omit no-op lossless optimization; every selectable result must be smaller.
  if (optimized.bytes.length < input.length) {
    choices.add(
      PdfCompressionChoice(
        PdfCompressionMode.preserve,
        optimized.bytes.length,
        optimized.bytes,
      ),
    );
  }
  await pdfrxFlutterInitialize();
  check();
  final source = await PdfDocument.openData(
    input,
    passwordProvider: () => null,
  );
  try {
    if (source.isEncrypted || source.pages.isEmpty) {
      throw const FormatException(
        'Use an unlocked PDF with at least one page.',
      );
    }
    final modes = PdfCompressionMode.values
        .where((m) => m != PdfCompressionMode.preserve)
        .toList();
    final pages = {for (final mode in modes) mode: <CompressedPdfPage>[]};
    for (var i = 0; i < source.pages.length; i++) {
      check();
      final page = source.pages[i];
      if (page.width <= 0 || page.height <= 0) {
        throw const FormatException('Invalid page dimensions.');
      }
      final w = page.width * 150 / 72, h = page.height * 150 / 72;
      final scale = min(1.0, 4096 / max(w, h));
      final raster = await page.render(
        fullWidth: w * scale,
        fullHeight: h * scale,
        backgroundColor: 0xffffffff,
      );
      if (raster == null) {
        throw const FormatException('Could not render this PDF.');
      }
      try {
        final picture = await raster.createImage();
        try {
          final data = await picture.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) {
            throw const FormatException('Could not read this page.');
          }
          final png = data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
          for (final mode in modes) {
            check();
            final jpeg = await resizeAndCompressPageImage(
              png,
              mode.quality,
              max(1, (page.width * mode.dpi / 72 * scale).round()),
            );
            check();
            pages[mode]!.add(CompressedPdfPage(jpeg, page.width, page.height));
          }
        } finally {
          picture.dispose();
        }
      } finally {
        raster.dispose();
      }
      check();
      onProgress((i + 1) / (source.pages.length + modes.length));
    }
    for (var i = 0; i < modes.length; i++) {
      check();
      final mode = modes[i];
      final result = await assembleImagePdf(pages[mode]!);
      pages[mode]!.clear();
      check();
      choices.add(
        PdfCompressionChoice(
          mode,
          result.bytes.length,
          result.bytes.length < input.length ? result.bytes : null,
        ),
      );
      onProgress(
        (source.pages.length + i + 1) / (source.pages.length + modes.length),
      );
    }
    return choices;
  } finally {
    await source.dispose();
  }
}

class PdfCompressionCancelled implements Exception {
  const PdfCompressionCancelled();
}
