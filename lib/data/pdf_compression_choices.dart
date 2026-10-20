import 'dart:typed_data';

import 'pdf_compression.dart';

enum PdfCompressionMode {
  preserve('Original quality', 0, 0),
  balanced('Balanced', 2048, 82),
  small('Small', 1440, 65),
  smallest('Smallest', 1024, 45);

  const PdfCompressionMode(this.label, this.maxImageDimension, this.quality);
  final String label;
  final int maxImageDimension, quality;
}

class PdfCompressionChoice {
  const PdfCompressionChoice(this.mode, this.size, this.bytes);
  final PdfCompressionMode mode;
  final int size;
  final Uint8List? bytes;
  // All choices retain the original text, links, forms and page graphics.
  bool get imageOnly => false;
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
  final choices = <PdfCompressionChoice>[];
  final optimized = await optimizePdf(input);
  check();
  var best = optimized.bytes;
  choices.add(
    PdfCompressionChoice(
      PdfCompressionMode.preserve,
      best.length,
      best.length < input.length ? best : null,
    ),
  );
  onProgress(1 / PdfCompressionMode.values.length);
  for (final mode in PdfCompressionMode.values.skip(1)) {
    check();
    final candidate = await optimizePdf(
      input,
      imageQuality: mode.quality,
      maxImageDimension: mode.maxImageDimension,
    );
    check();
    // Stronger settings never offer a larger result than a preceding setting.
    if (candidate.bytes.length < best.length) {
      best = candidate.bytes;
    }
    choices.add(
      PdfCompressionChoice(
        mode,
        best.length,
        best.length < input.length ? best : null,
      ),
    );
    onProgress((mode.index + 1) / PdfCompressionMode.values.length);
  }
  return choices;
}

class PdfCompressionCancelled implements Exception {
  const PdfCompressionCancelled();
}
