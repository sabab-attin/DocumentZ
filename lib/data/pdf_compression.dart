import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as image;

class PdfCompressionResult {
  const PdfCompressionResult(
    this.bytes, {
    required this.pages,
    required this.imageOnly,
  });
  final Uint8List bytes;
  final int pages;
  final bool imageOnly;
}

class CompressedPdfPage {
  const CompressedPdfPage(this.jpeg, this.width, this.height);
  final Uint8List jpeg;
  final double width, height;
}

// Conservative guards: encrypted and signed inputs are never silently rewritten.
bool _contains(Uint8List data, String marker) {
  final pattern = marker.codeUnits;
  for (var i = 0; i <= data.length - pattern.length; i++) {
    if (data[i] != pattern.first) {
      continue;
    }
    var match = true;
    for (var j = 1; j < pattern.length; j++) {
      if (data[i + j] != pattern[j]) {
        match = false;
        break;
      }
    }
    if (match) {
      return true;
    }
  }
  return false;
}

void checkPdfCompressionInput(Uint8List bytes) {
  if (_contains(bytes, '/Encrypt')) {
    throw const FormatException(
      'Protected PDFs are kept unchanged. Compress an unlocked copy instead.',
    );
  }
  if (_contains(bytes, '/ByteRange')) {
    throw const FormatException(
      'Signed PDFs are kept unchanged to protect their digital signatures.',
    );
  }
}

Future<void> validatePdfCompressionInput(Uint8List bytes) =>
    compute(checkPdfCompressionInput, bytes);
Future<PdfCompressionResult> optimizePdf(Uint8List bytes) =>
    compute(_optimizePdf, bytes);
Future<PdfCompressionResult> _optimizePdf(Uint8List bytes) async {
  checkPdfCompressionInput(bytes);
  final source = sf.PdfDocument(inputBytes: bytes);
  sf.PdfDocument? checked;
  try {
    final count = source.pages.count;
    if (count == 0) {
      throw const FormatException('This PDF has no pages.');
    }
    for (var i = 0; i < source.form.fields.count; i++) {
      final field = source.form.fields[i];
      if (field is sf.PdfSignatureField && field.signature != null) {
        throw const FormatException(
          'Signed PDFs cannot be rewritten without invalidating their signatures.',
        );
      }
    }
    final extractor = sf.PdfTextExtractor(source);
    final content = [
      for (var i = 0; i < count; i++)
        (
          size: source.pages[i].getClientSize(),
          rotation: source.pages[i].rotation,
          annotations: source.pages[i].annotations.count,
          text: extractor.extractText(startPageIndex: i, endPageIndex: i),
        ),
    ];
    final fields = source.form.fields.count, bookmarks = source.bookmarks.count;
    source.fileStructure.incrementalUpdate = false;
    source.compressionLevel = sf.PdfCompressionLevel.best;
    final output = Uint8List.fromList(await source.save());
    if (output.length >= bytes.length) {
      return PdfCompressionResult(bytes, pages: count, imageOnly: false);
    }
    checked = sf.PdfDocument(inputBytes: output);
    if (checked.pages.count != count ||
        checked.form.fields.count != fields ||
        checked.bookmarks.count != bookmarks) {
      throw const FormatException(
        'Could not preserve this PDF. The original is unchanged.',
      );
    }
    final after = sf.PdfTextExtractor(checked);
    for (var i = 0; i < count; i++) {
      final page = checked.pages[i],
          size = page.getClientSize(),
          original = content[i];
      if ((size.width - original.size.width).abs() > .01 ||
          (size.height - original.size.height).abs() > .01 ||
          page.rotation != original.rotation ||
          page.annotations.count != original.annotations ||
          after.extractText(startPageIndex: i, endPageIndex: i) !=
              original.text) {
        throw const FormatException(
          'Could not preserve this PDF. The original is unchanged.',
        );
      }
    }
    return PdfCompressionResult(output, pages: count, imageOnly: false);
  } finally {
    checked?.dispose();
    source.dispose();
  }
}

Future<Uint8List> compressPageImage(Uint8List png, int quality) =>
    compute(_jpeg, (png, quality));
Uint8List _jpeg((Uint8List, int) job) {
  final pixels = image.decodePng(job.$1);
  if (pixels == null) {
    throw const FormatException('Could not decode the page preview.');
  }
  return Uint8List.fromList(image.encodeJpg(pixels, quality: job.$2));
}

Future<PdfCompressionResult> assembleImagePdf(List<CompressedPdfPage> pages) =>
    compute(_imagePdf, pages);
Future<PdfCompressionResult> _imagePdf(List<CompressedPdfPage> pages) async {
  if (pages.isEmpty) {
    throw const FormatException('This PDF has no pages.');
  }
  final pdf = pw.Document(compress: true);
  for (final page in pages) {
    if (page.width <= 0 || page.height <= 0) {
      throw const FormatException('Invalid PDF page dimensions.');
    }
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(page.width, page.height, marginAll: 0),
        build: (_) => pw.Image(pw.MemoryImage(page.jpeg), fit: pw.BoxFit.fill),
      ),
    );
  }
  final bytes = await pdf.save();
  final checked = sf.PdfDocument(inputBytes: bytes);
  try {
    if (checked.pages.count != pages.length) {
      throw const FormatException('Could not validate the compressed PDF.');
    }
    for (var i = 0; i < pages.length; i++) {
      final size = checked.pages[i].getClientSize();
      if ((size.width - pages[i].width).abs() > .01 ||
          (size.height - pages[i].height).abs() > .01) {
        throw const FormatException('Could not preserve page dimensions.');
      }
    }
  } finally {
    checked.dispose();
  }
  return PdfCompressionResult(bytes, pages: pages.length, imageOnly: true);
}

Future<Uint8List> resizeAndCompressPageImage(
  Uint8List png,
  int quality,
  int width,
) => compute(_resizedJpeg, (png, quality, width));
Uint8List _resizedJpeg((Uint8List, int, int) job) {
  var pixels = image.decodePng(job.$1);
  if (pixels == null) {
    throw const FormatException('Could not decode this page.');
  }
  if (pixels.width > job.$3) {
    pixels = image.copyResize(
      pixels,
      width: job.$3,
      interpolation: image.Interpolation.average,
    );
  }
  return Uint8List.fromList(image.encodeJpg(pixels, quality: job.$2));
}
