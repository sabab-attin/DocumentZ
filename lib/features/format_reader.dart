import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import '../core/preferences.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import '../data/import_validation.dart';
import '../data/readable_document.dart';
import '../data/image_document.dart';
import '../data/document_conversion.dart';
import 'annotations.dart';
import 'epub_reader.dart';
import 'reader.dart';
import 'reader_controls.dart';
import 'text_alignment_menu.dart';

class FormatReader extends StatefulWidget {
  const FormatReader({super.key, required this.book, required this.repository, required this.preferences});
  final Book book;
  final ImportableLibrary repository;
  final ReaderPreferences preferences;
  @override
  State<FormatReader> createState() => _FormatReaderState();
}

class _FormatReaderState extends State<FormatReader> {
  late final bytes = widget.repository.readDocument(widget.book);
  late final document = bytes.then((data) => compute(parseReadableDocument, (widget.book.format, data)));
  late final frames = bytes.then((data) => [BookFormat.tiff, BookFormat.tif].contains(widget.book.format)
    ? compute(tiffPages, data) : widget.book.format == BookFormat.bmp
      ? compute(bmpPage, data).then((image) => [image]) : Future.value([data]));
  late final annotations = AnnotationStore(widget.book.id)..load();
  final epub = GlobalKey<EpubReaderState>();
  int? color;
  MarkTool tool = MarkTool.browse;
  int imagePage = 0;
  bool converting = false;
  String? conversionError;
  bool get image => rasterFormats.contains(widget.book.format) || widget.book.format == BookFormat.svg;
  bool get legacy => conversionFormats.contains(widget.book.format);
  @override
  void dispose() { annotations.dispose(); super.dispose(); }

  Future<void> convert({bool chooseExecutable = false}) async {
    if (converting) return;
    setState(() { converting = true; conversionError = null; });
    try {
      String? binary;
      if (chooseExecutable) {
        final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['exe']);
        if (file == null) return;
        binary = file.path;
      }
      final data = await convertDocumentToPdf(await bytes, widget.book.format, executable: binary);
      final copy = await widget.repository.importDocument('${widget.book.title} - converted.pdf', Stream.value(data));
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(MaterialPageRoute(builder: (_) => ReaderScreen(
        book: copy, preferences: widget.preferences, repository: widget.repository)));
    } catch (error) {
      if (mounted) setState(() => conversionError = error is FormatException ? error.message.toString() : 'Conversion failed. Check the conversion software and try again.');
    } finally { if (mounted) setState(() => converting = false); }
  }

  Future<void> chooseColor() async {
    await showModalBottomSheet<void>(context: context, builder: (sheet) => SafeArea(child: Padding(padding: const EdgeInsets.all(20),
      child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final entry in const {'Yellow': 0xffffcc00, 'Pink': 0xffec407a, 'Green': 0xff2e7d32,
          'Blue': 0xff1565c0, 'Purple': 0xff7b1fa2, 'Red': 0xffc62828, 'Black': 0xff000000, 'White': 0xffffffff}.entries)
          ChoiceChip(label: Text(entry.key), selected: color == entry.value,
            avatar: CircleAvatar(backgroundColor: Color(entry.value), radius: 9),
            onSelected: (_) { setState(() => color = entry.value); Navigator.pop(sheet); }),
      ]))));
  }
  Widget conversion() => Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, children: [
    if (legacy) Text(supportsLocalConversion
      ? '${widget.book.format.name.toUpperCase()} opens through ${conversionTool(widget.book.format)} on this computer.'
      : 'Convert this file to PDF in the Windows app, then share and import the PDF here.'),
    if (conversionError != null) Padding(padding: const EdgeInsets.all(8), child: Text(conversionError!)),
    if (supportsLocalConversion) Wrap(alignment: WrapAlignment.center, spacing: 12, children: [
      FilledButton.icon(onPressed: converting ? null : convert, icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(converting ? 'Converting…' : 'Convert to PDF')),
      TextButton(onPressed: converting ? null : () => convert(chooseExecutable: true),
        child: Text('Choose ${conversionTool(widget.book.format)} executable')),
    ]),
    if (converting) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
  ]));

  @override
  Widget build(BuildContext context) {
    if (legacy) return Center(child: SingleChildScrollView(child: conversion()));
    if (image) {
      return FutureBuilder<List<Uint8List>>(future: frames, builder: (context, snapshot) {
      if (snapshot.hasError) return const Center(child: Text('Could not read this image. It may be damaged or use an unsupported encoding.'));
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return Column(children: [
        if (snapshot.data!.length > 1) Padding(padding: const EdgeInsets.all(12), child: Text('Page ${imagePage + 1} / ${snapshot.data!.length}')),
        Expanded(child: PageView.builder(itemCount: snapshot.data!.length, onPageChanged: (i) => setState(() => imagePage = i),
          itemBuilder: (context, i) => InteractiveViewer(minScale: .5, maxScale: 8, child: Center(
            child: widget.book.format == BookFormat.svg ? SvgPicture.memory(snapshot.data![i], fit: BoxFit.contain, semanticsLabel: widget.book.title)
              : Image.memory(snapshot.data![i], fit: BoxFit.contain, semanticLabel: widget.book.title,
                errorBuilder: (_, error, stack) => const Text('Could not decode this image.')))))),
      ]);
      });
    }
    return ReaderControlsOverlay(controls: Column(mainAxisSize: MainAxisSize.min, children: [
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        TextAlignmentMenu(preferences: widget.preferences),
        TextButton.icon(onPressed: chooseColor, icon: const Icon(Icons.palette_outlined), label: const Text('Color')),
        for (final entry in const {MarkTool.highlight: 'Highlight', MarkTool.underline: 'Underline', MarkTool.strikethrough: 'Strike', MarkTool.note: 'Note'}.entries)
          TextButton(onPressed: () => setState(() => tool = tool == entry.key ? MarkTool.browse : entry.key),
            style: TextButton.styleFrom(backgroundColor: tool == entry.key ? Theme.of(context).colorScheme.primaryContainer : null), child: Text(entry.value)),
        IconButton(tooltip: 'Search document', onPressed: () => epub.currentState?.searchDocument(), icon: const Icon(Icons.search)),
        if (supportsLocalConversion && (officeArchiveFormats.contains(widget.book.format) || widget.book.format == BookFormat.rtf))
          TextButton(onPressed: converting ? null : convert, child: Text(converting ? 'Converting…' : 'PDF layout')),
      ])),
      if (conversionError != null) Padding(padding: const EdgeInsets.all(8), child: Column(children: [
        Text(conversionError!),
        if (supportsLocalConversion) TextButton(onPressed: converting ? null : () => convert(chooseExecutable: true),
          child: Text('Choose ${conversionTool(widget.book.format)} executable')),
      ])),
      if (officeArchiveFormats.contains(widget.book.format) || widget.book.format == BookFormat.rtf)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: Text('Reading view · Original page layout may differ.')),
    ]), child: EpubReader(key: epub, bytes: bytes, parsedDocument: document,
        preferences: widget.preferences, annotations: annotations, color: color, activeTool: tool));
  }
}
