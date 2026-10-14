import 'dart:typed_data';
import 'dart:ui';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Zero-based source page indices; null means deliberately blank paper.
class BookletSide {
  const BookletSide(this.left, this.right);
  final int? left;
  final int? right;
}

class BookletSignature {
  BookletSignature(this.start, this.end, List<int?> pages)
    : pages = List.unmodifiable(pages);
  final int start;
  final int end;
  final List<int?> pages;
  int get blankCount => pages.where((p) => p == null).length;
  int get sheetCount => pages.length ~/ 4;
  List<BookletSide> get sides {
    final result = <BookletSide>[];
    for (var i = 0; i < pages.length ~/ 2; i += 2) {
      result.add(BookletSide(pages[pages.length - 1 - i], pages[i]));
      result.add(BookletSide(pages[i + 1], pages[pages.length - 2 - i]));
    }
    return result;
  }
}

List<BookletSignature> planBooklets(int count, int pagesPerBooklet) {
  if (count < 1) {
    throw const FormatException('This PDF has no pages.');
  }
  if (![0, 4, 8, 12, 16, 20, 24].contains(pagesPerBooklet)) {
    throw const FormatException('Choose a supported booklet size.');
  }
  final chunk = pagesPerBooklet == 0 || pagesPerBooklet > count
      ? count
      : pagesPerBooklet;
  final padded = ((chunk + 3) ~/ 4) * 4;
  return [
    for (var start = 0; start < count; start += chunk)
      BookletSignature(
        start,
        (start + chunk).clamp(0, count),
        List<int?>.generate(padded, (offset) {
          final index = start + offset;
          return offset < chunk && index < count ? index : null;
        }),
      ),
  ];
}

class BookletExport {
  const BookletExport(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
  bool get isZip => name.endsWith('.zip');
}

class PdfBooklet {
  static int pageCount(Uint8List bytes) {
    final source = sf.PdfDocument(inputBytes: bytes);
    try {
      return source.pages.count;
    } finally {
      source.dispose();
    }
  }

  /// Same two-up ordering and paper dimensions for preview and final output.
  /// Page templates retain vector artwork; the original bytes are never changed.
  static Future<Uint8List> _render(
    sf.PdfDocument source,
    BookletSignature signature,
    List<BookletSide> sides,
  ) async {
    final output = sf.PdfDocument();
    try {
      final first = signature.pages.whereType<int>().first;
      final size = source.pages[first].createTemplate().size;
      if (size.width <= 0 || size.height <= 0) {
        throw const FormatException('This PDF has an invalid page size.');
      }
      final sheetSize = Size(size.width * 2, size.height);
      output.pageSettings.orientation = sheetSize.width >= sheetSize.height
          ? sf.PdfPageOrientation.landscape
          : sf.PdfPageOrientation.portrait;
      output.pageSettings.size = sheetSize;
      output.pageSettings.margins.all = 0;
      for (final side in sides) {
        final page = output.pages.add();
        for (var slot = 0; slot < 2; slot++) {
          final index = slot == 0 ? side.left : side.right;
          if (index != null) {
            page.graphics.drawPdfTemplate(
              source.pages[index].createTemplate(),
              Offset(slot * size.width, 0),
              size,
            );
          }
        }
        await Future<void>.delayed(Duration.zero);
      }
      return Uint8List.fromList(await output.save());
    } finally {
      output.dispose();
    }
  }

  static Future<Uint8List> preview(
    Uint8List bytes,
    BookletSignature signature,
    int sideIndex,
  ) async {
    final source = sf.PdfDocument(inputBytes: bytes);
    try {
      return await _render(source, signature, [signature.sides[sideIndex]]);
    } finally {
      source.dispose();
    }
  }

  static Future<BookletExport> export(
    Uint8List bytes,
    String title,
    int pagesPerBooklet, {
    void Function(int done, int total)? onProgress,
  }) async {
    final source = sf.PdfDocument(inputBytes: bytes);
    try {
      final plan = planBooklets(source.pages.count, pagesPerBooklet);
      final safe = title
          .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), '')
          .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
          .trim();
      final base = safe.isEmpty ? 'Document' : safe;
      final archive = Archive();
      for (var i = 0; i < plan.length; i++) {
        final signature = plan[i];
        final data = await _render(source, signature, signature.sides);
        onProgress?.call(i + 1, plan.length);
        if (plan.length == 1) {
          return BookletExport(
            data,
            '${base}_booklet_pages_${signature.start + 1}-${signature.end}.pdf',
          );
        }
        archive.addFile(
          ArchiveFile(
            '${base}_pages_${signature.start + 1}-${signature.end}.pdf',
            data.length,
            data,
          ),
        );
      }
      return BookletExport(
        Uint8List.fromList(ZipEncoder().encode(archive)),
        '${base}_booklets.zip',
      );
    } finally {
      source.dispose();
    }
  }
}
