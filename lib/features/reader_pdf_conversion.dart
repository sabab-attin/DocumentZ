import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:image/image.dart' as image;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/preferences.dart';
import '../data/document_conversion.dart';
import '../data/epub_document.dart';
import '../data/readable_document.dart';
import '../data/image_document.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'reader.dart';
import 'reader_controls.dart';
import 'selection_panel.dart';

const _external = [
  BookFormat.doc,
  BookFormat.xls,
  BookFormat.ppt,
  BookFormat.mobi,
  BookFormat.eps,
  BookFormat.ps,
];
const _office = [
  ..._external,
  BookFormat.docx,
  BookFormat.xlsx,
  BookFormat.pptx,
  BookFormat.odt,
  BookFormat.ods,
  BookFormat.odp,
];
const _images = [
  BookFormat.png,
  BookFormat.jpg,
  BookFormat.jpeg,
  BookFormat.bmp,
  BookFormat.tiff,
  BookFormat.tif,
  BookFormat.gif,
  BookFormat.svg,
];

Future<Uint8List> _makePdf(
  (Uint8List, BookFormat, String, String, Uint8List) job,
) async {
  final (bytes, format, title, alignment, fontBytes) = job;
  final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
  final pdf = pw.Document(title: title);
  if (_images.contains(format)) {
    final frames = [BookFormat.tiff, BookFormat.tif].contains(format)
        ? tiffPages(bytes)
        : [bytes];
    for (final frame in frames) {
      final content = format == BookFormat.svg
          ? pw.SvgImage(svg: utf8.decode(frame))
          : pw.Image(
              pw.MemoryImage(
                image.encodePng(
                  image.decodeImage(frame) ??
                      (throw const FormatException(
                        'Could not decode this image.',
                      )),
                ),
              ),
            );
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(child: content),
        ),
      );
    }
  } else {
    final parsed = format == BookFormat.epub
        ? parseEpub(bytes)
        : parseReadableDocument((format, bytes));
    final align = switch (alignment) {
      'left' => pw.TextAlign.left,
      'right' => pw.TextAlign.right,
      'center' => pw.TextAlign.center,
      _ => pw.TextAlign.justify,
    };
    for (final section in parsed.sections) {
      final body = html.parse(section.html).body;
      final widgets = <pw.Widget>[];
      final blocks =
          body?.querySelectorAll(
            'h1,h2,h3,h4,h5,h6,p,li,pre,blockquote,table,img',
          ) ??
          [];
      for (final block in blocks) {
        if (block.localName == 'img') {
          final path = epubResourcePath(
            section.path,
            block.attributes['src'] ?? '',
          );
          final data = parsed.resources[path];
          if (data != null) {
            final decoded = image.decodeImage(data);
            if (decoded != null) {
              widgets.add(
                pw.SizedBox(
                  height: 200,
                  child: pw.Image(pw.MemoryImage(image.encodePng(decoded))),
                ),
              );
            }
          }
          continue;
        }
        if (block.parent?.localName == 'li' && block.localName == 'p') continue;
        final text = block.localName == 'table'
            ? block
                  .querySelectorAll('tr')
                  .map(
                    (row) => row.children
                        .map((cell) => cell.text.trim())
                        .join(' | '),
                  )
                  .join('\n')
            : block.text.trim();
        if (text.isEmpty) continue;
        final heading =
            (block.localName ?? '').startsWith('h') &&
            block.localName != 'html';
        widgets.add(
          pw.Paragraph(
            text: text,
            textAlign: heading ? pw.TextAlign.left : align,
            style: pw.TextStyle(font: font, fontSize: heading ? 18 : 12),
          ),
        );
      }
      if (widgets.isEmpty) {
        widgets.add(
          pw.Paragraph(
            text: body?.text.trim() ?? section.title,
            style: pw.TextStyle(font: font),
          ),
        );
      }
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          maxPages: 2000,
          theme: pw.ThemeData.withFont(
            base: font,
            bold: font,
            italic: font,
            boldItalic: font,
          ),
          build: (_) => widgets,
        ),
      );
    }
  }
  return pdf.save();
}

class ConvertPdfMenuAction extends StatefulWidget {
  const ConvertPdfMenuAction({
    super.key,
    required this.book,
    required this.repository,
    required this.preferences,
  });
  final Book book;
  final ImportableLibrary repository;
  final ReaderPreferences preferences;
  @override
  State<ConvertPdfMenuAction> createState() => _ConvertPdfMenuActionState();
}

class _ConvertPdfMenuActionState extends State<ConvertPdfMenuAction> {
  bool busy = false;
  Future<void> convert() async {
    if (busy) return;
    ReaderControlsScope.chromeOf(context)?.hold();
    final external = _external.contains(widget.book.format);
    if (external && !supportsLocalConversion) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This legacy format requires conversion tools in the Windows app.',
          ),
        ),
      );
      return;
    }
    final agreed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Create a PDF copy?'),
        content: Text(
          supportsLocalConversion && _office.contains(widget.book.format)
              ? 'Uses your installed conversion software. The original document stays unchanged.'
              : _images.contains(widget.book.format)
              ? 'Creates PDF pages from this image. The original stays unchanged.'
              : 'Creates a reflowed reading copy. Complex layouts and some styling may change. App annotations are not transferred. The original stays unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Convert'),
          ),
        ],
      ),
    );
    if (agreed != true || !mounted) return;
    setState(() => busy = true);
    try {
      final source = await widget.repository.readDocument(widget.book);
      final font = await rootBundle.load('assets/fonts/Tinos-Regular.ttf');
      final data =
          supportsLocalConversion && _office.contains(widget.book.format)
          ? await convertDocumentToPdf(source, widget.book.format)
          : await compute(_makePdf, (
              source,
              widget.book.format,
              widget.book.title,
              widget.preferences.alignment.name,
              font.buffer.asUint8List(font.offsetInBytes, font.lengthInBytes),
            ));
      final copy = await widget.repository.importDocument(
        '${widget.book.title} - converted.pdf',
        Stream.value(data),
      );
      if (!mounted) return;
      final navigator = Navigator.of(context);
      ReaderControlsScope.of(context)?.value = false;
      await navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: copy,
            repository: widget.repository,
            preferences: widget.preferences.globalDefaults,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not convert this document. Check the format and conversion software.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ReaderMenuAction(
    label: busy ? 'Converting…' : 'Convert to PDF',
    icon: Icons.picture_as_pdf_outlined,
    onTap: busy ? null : convert,
  );
}
