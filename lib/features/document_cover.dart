import 'dart:ui' as ui;
import 'dart:convert';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/epub_document.dart';
import '../domain/book.dart';
import '../domain/services.dart';

Uint8List? epubCover(Uint8List bytes) {
  final book = parseEpub(bytes);
  final cover = book.coverPath;
  if (cover != null) {
    final resource = epubImageResource(book, '', '/$cover');
    if (resource != null && resource.path.toLowerCase().endsWith('.svg')) {
      return Uint8List.fromList(
        utf8.encode(
          epubSvgMarkup(book, resource.path, utf8.decode(resource.bytes)),
        ),
      );
    }
    return resource?.bytes;
  }
  // EPUBs without a cover manifest often put it in their first spine item.
  final source = RegExp(
    r'''(?:src|href)\s*=\s*["']([^"']+)["']''',
    caseSensitive: false,
  ).allMatches(book.sections.first.html);
  for (final match in source) {
    final path = epubResourcePath(book.sections.first.path, match.group(1)!);
    if (RegExp(
      r'\.(png|jpe?g|webp|gif)$',
      caseSensitive: false,
    ).hasMatch(path)) {
      final data = epubImageResource(
        book,
        book.sections.first.path,
        match.group(1)!,
      )?.bytes;
      if (data != null) return data;
    }
  }
  return null;
}

Future<Uint8List?> loadDocumentCover(
  Book book,
  ImportableLibrary library,
) async {
  try {
    if (book.format == BookFormat.epub) {
      return await compute(epubCover, await library.readDocument(book));
    }
    if (book.format != BookFormat.pdf) return null;
    await pdfrxFlutterInitialize();
    final document = book.localPath != null
        ? await PdfDocument.openFile(book.localPath!)
        : await PdfDocument.openData(await library.readDocument(book));
    try {
      if (document.pages.isEmpty) return null;
      final page = document.pages.first;
      final raster = await page.render(
        fullWidth: 384,
        fullHeight: 384 * page.height / page.width,
      );
      if (raster == null) return null;
      try {
        final image = await raster.createImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) return null;
          return data.buffer.asUint8List(
            data.offsetInBytes,
            data.lengthInBytes,
          );
        } finally {
          image.dispose();
        }
      } finally {
        raster.dispose();
      }
    } finally {
      await document.dispose();
    }
  } catch (_) {
    return null;
  }
}

class DocumentCover extends StatelessWidget {
  const DocumentCover({
    super.key,
    required this.cover,
    required this.format,
    this.width = 96,
    this.height = 132,
  });
  final Future<Uint8List?> cover;
  final BookFormat format;
  final double width, height;
  IconData get _icon => switch (format.name) {
    'pdf' => Icons.picture_as_pdf_outlined,
    'epub' || 'mobi' => Icons.menu_book_outlined,
    'xls' || 'xlsx' || 'ods' => Icons.table_chart_outlined,
    'ppt' || 'pptx' || 'odp' => Icons.slideshow_outlined,
    'png' ||
    'jpg' ||
    'jpeg' ||
    'gif' ||
    'bmp' ||
    'svg' ||
    'tif' ||
    'tiff' => Icons.image_outlined,
    _ => Icons.description_outlined,
  };
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = format == BookFormat.epub
        ? scheme.tertiary
        : format == BookFormat.pdf
        ? scheme.primary
        : scheme.secondary;
    Widget fallback() => Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  accent.withValues(alpha: .13),
                  accent.withValues(alpha: .035),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          top: 18,
          bottom: 18,
          child: Container(width: 2, color: accent.withValues(alpha: .22)),
        ),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _icon,
                size: (height * .32).clamp(24.0, 44.0),
                color: accent,
              ),
              if (height >= 150) ...[
                const SizedBox(height: 12),
                Text(
                  format.name.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: accent, letterSpacing: 1.6),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return SizedBox(
      width: width,
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ColoredBox(
          color: scheme.surfaceContainerHighest,
          child: FutureBuilder<Uint8List?>(
            future: cover,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) return fallback();
              final svg = utf8
                  .decode(bytes.take(1024).toList(), allowMalformed: true)
                  .contains('<svg');
              return Padding(
                padding: const EdgeInsets.all(10),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: svg
                          ? SvgPicture.memory(
                              bytes,
                              fit: BoxFit.contain,
                              excludeFromSemantics: true,
                            )
                          : Image.memory(
                              bytes,
                              fit: BoxFit.contain,
                              cacheWidth: 384,
                              excludeFromSemantics: true,
                              errorBuilder: (_, error, stack) => fallback(),
                            ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
