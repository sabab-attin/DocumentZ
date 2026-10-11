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
      return Uint8List.fromList(utf8.encode(epubSvgMarkup(book, resource.path, utf8.decode(resource.bytes))));
    }
    return resource?.bytes;
  }
  // EPUBs without a cover manifest often put it in their first spine item.
  final source = RegExp(r'''(?:src|href)\s*=\s*["']([^"']+)["']''', caseSensitive: false)
    .allMatches(book.sections.first.html);
  for (final match in source) {
    final path = epubResourcePath(book.sections.first.path, match.group(1)!);
    if (RegExp(r'\.(png|jpe?g|webp|gif)$', caseSensitive: false).hasMatch(path)) {
      final data = epubImageResource(book, book.sections.first.path, match.group(1)!)?.bytes;
      if (data != null) return data;
    }
  }
  return null;
}

Future<Uint8List?> loadDocumentCover(Book book, ImportableLibrary library) async {
  try {
    if (book.format == BookFormat.epub) return await compute(epubCover, await library.readDocument(book));
    if (book.format != BookFormat.pdf) return null;
    await pdfrxFlutterInitialize();
    final document = book.localPath != null ? await PdfDocument.openFile(book.localPath!)
      : await PdfDocument.openData(await library.readDocument(book));
    try {
      if (document.pages.isEmpty) return null;
      final page = document.pages.first;
      final raster = await page.render(fullWidth: 120, fullHeight: 120 * page.height / page.width);
      if (raster == null) return null;
      try {
        final image = await raster.createImage();
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) return null;
          return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally { image.dispose(); }
      } finally { raster.dispose(); }
    } finally { await document.dispose(); }
  } catch (_) { return null; }
}

class DocumentCover extends StatelessWidget {
  const DocumentCover({super.key, required this.cover, required this.format});
  final Future<Uint8List?> cover;
  final BookFormat format;
  @override
  Widget build(BuildContext context) => SizedBox(width: 56, height: 76,
    child: ClipRRect(borderRadius: BorderRadius.circular(4), child: ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: FutureBuilder<Uint8List?>(future: cover, builder: (context, snapshot) {
        final fallback = Icon(format == BookFormat.pdf ? Icons.picture_as_pdf_outlined : Icons.menu_book_outlined);
        if (snapshot.data != null && utf8.decode(snapshot.data!.take(1024).toList(), allowMalformed: true).contains('<svg')) {
          return SvgPicture.memory(snapshot.data!, fit: BoxFit.contain, excludeFromSemantics: true);
        }
        return snapshot.data == null ? Center(child: fallback) : Image.memory(snapshot.data!, fit: BoxFit.contain, cacheWidth: 168,
          excludeFromSemantics: true, errorBuilder: (_, error, stack) => Center(child: fallback));
      }))));
}
