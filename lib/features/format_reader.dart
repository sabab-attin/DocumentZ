import 'reader_pdf_conversion.dart';
import 'reading_typography.dart';
import 'annotation_color_picker.dart';
import 'highlighter_icon.dart';

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
import 'annotation_toolbar.dart';
import 'epub_reader.dart';
import 'reader.dart';
import 'reader_controls.dart';
import 'selection_panel.dart';
import 'reader_edit_menu.dart';
import '../data/reading_progress.dart';
import '../data/document_sharing.dart';
import 'settings.dart';
import 'text_alignment_menu.dart';

class FormatReader extends StatefulWidget {
  const FormatReader({
    super.key,
    required this.book,
    required this.repository,
    required this.preferences,
    this.annotationMode = false,
    this.annotationStore,
  });
  final AnnotationStore? annotationStore;
  final bool annotationMode;
  final Book book;
  final ImportableLibrary repository;
  final ReaderPreferences preferences;
  @override
  State<FormatReader> createState() => _FormatReaderState();
}

class _FormatReaderState extends State<FormatReader> {
  late final bytes = widget.repository.readDocument(widget.book);
  late final document = bytes.then(
    (data) => compute(parseReadableDocument, (widget.book.format, data)),
  );
  late final frames = bytes.then(
    (data) => [BookFormat.tiff, BookFormat.tif].contains(widget.book.format)
        ? compute(tiffPages, data)
        : widget.book.format == BookFormat.bmp
        ? compute(bmpPage, data).then((image) => [image])
        : Future.value([data]),
  );
  late final annotations =
      widget.annotationStore ?? (AnnotationStore(widget.book.id)..load());
  final epub = GlobalKey<EpubReaderState>();
  int? color;
  MarkTool tool = MarkTool.browse;
  bool _annotationMode = false;
  TextAnnotationDraft? _insertText;
  String? _insertImage;
  void _placed() {
    if (mounted) {
      setState(() {
        tool = MarkTool.browse;
        _insertText = null;
        _insertImage = null;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _annotationMode = widget.annotationMode;
  }

  Future<void> _addText() async {
    final draft = await composeAnnotationText(context);
    if (mounted && draft != null) {
      setState(() {
        _insertText = draft;
        _annotationMode = true;
        tool = MarkTool.text;
      });
    }
  }

  Future<void> _addImage() async {
    try {
      final image = await pickAnnotationImage();
      if (mounted && image != null) {
        setState(() {
          _insertImage = image;
          _annotationMode = true;
          tool = MarkTool.image;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open image. Choose an image smaller than 12 MB.',
            ),
          ),
        );
      }
    }
  }

  final _imageZoom = TransformationController();
  final _imagePages = PageController();
  BoxFit _imageFit = BoxFit.contain;
  int imagePage = 0;
  String? _lastImageView;
  Future<void> _imageFitting() => showReaderZoom(
    context,
    current: _imageZoom.value.getMaxScaleOnAxis(),
    onZoom: (zoom) {
      widget.preferences.setViewing(fit: 'custom', zoom: zoom);
      _imageZoom.value = Matrix4.diagonal3Values(
        zoom.clamp(.5, 8),
        zoom.clamp(.5, 8),
        1,
      );
    },
    onBestFit: () {
      widget.preferences.setViewing(fit: 'bestFit');
      _imageZoom.value = Matrix4.identity();
      setState(() => _imageFit = BoxFit.contain);
    },
    onFitWidth: () {
      widget.preferences.setViewing(fit: 'fitWidth');
      _imageZoom.value = Matrix4.identity();
      setState(() => _imageFit = BoxFit.fitWidth);
    },
  );
  bool converting = false;
  String? conversionError;
  bool get image =>
      rasterFormats.contains(widget.book.format) ||
      widget.book.format == BookFormat.svg;
  bool get legacy =>
      conversionFormats.contains(widget.book.format) &&
      widget.book.format != BookFormat.mobi;
  @override
  void dispose() {
    _imageZoom.dispose();
    _imagePages.dispose();
    if (widget.annotationStore == null) annotations.dispose();
    super.dispose();
  }

  Future<void> convert({bool chooseExecutable = false}) async {
    if (converting) return;
    setState(() {
      converting = true;
      conversionError = null;
    });
    try {
      String? binary;
      if (chooseExecutable) {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['exe'],
        );
        if (file == null) return;
        binary = file.path;
      }
      final data = await convertDocumentToPdf(
        await bytes,
        widget.book.format,
        executable: binary,
      );
      final copy = await widget.repository.importDocument(
        '${widget.book.title} - converted.pdf',
        Stream.value(data),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement<void, void>(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: copy,
            preferences: widget.preferences.globalDefaults,
            repository: widget.repository,
            annotationMode: _annotationMode,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => conversionError = error is FormatException
              ? error.message.toString()
              : 'Conversion failed. Check the conversion software and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => converting = false);
    }
  }

  Future<void> chooseColor() async {
    final selected = await pickAnnotationColor(
      context,
      initial: Color(color ?? 0xffffcc00),
    );
    if (selected != null && mounted) {
      setState(() => color = selected.toARGB32());
    }
  }

  Widget conversion() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (legacy)
          Text(
            supportsLocalConversion
                ? '${widget.book.format.name.toUpperCase()} opens through ${conversionTool(widget.book.format)} on this computer.'
                : 'Convert this file to PDF in the Windows app, then share and import the PDF here.',
          ),
        if (conversionError != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(conversionError!),
          ),
        if (supportsLocalConversion)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: converting ? null : convert,
                icon: const ReaderToolIcon(Icons.picture_as_pdf_outlined),
                label: Text(converting ? 'Converting…' : 'Convert to PDF'),
              ),
              TextButton(
                onPressed: converting
                    ? null
                    : () => convert(chooseExecutable: true),
                child: Text(
                  'Choose ${conversionTool(widget.book.format)} executable',
                ),
              ),
            ],
          ),
        if (converting)
          const Padding(
            padding: EdgeInsets.all(8),
            child: LinearProgressIndicator(),
          ),
      ],
    ),
  );

  Widget _basicMenu({bool includeEdit = true}) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      ReaderMenuGrid(
        children: [
          ConvertPdfMenuAction(
            book: widget.book,
            repository: widget.repository,
            preferences: widget.preferences,
          ),
          if (!image && !legacy)
            ReaderMenuAction(
              label: 'Annotation mode',
              icon: Icons.draw_outlined,
              onTap: () {
                ReaderControlsScope.of(context)?.value = false;
                setState(() => _annotationMode = true);
              },
            ),
          if (image)
            ReaderMenuAction(
              label: 'Page fitting',
              icon: Icons.fit_screen,
              onTap: () {
                ReaderControlsScope.of(context)?.value = false;
                _imageFitting();
              },
            ),
          ReaderMenuAction(
            label: 'Reader controls',
            icon: Icons.tune,
            onTap: () {
              ReaderControlsScope.of(context)?.value = false;
              showReaderControlOptions(context, widget.preferences);
            },
          ),
          if (!image && !legacy)
            ReaderMenuAction(
              label: 'Font, size & alignment',
              icon: Icons.text_fields,
              onTap: () {
                ReaderControlsScope.of(context)?.value = false;
                showReadingTypography(context, widget.preferences);
              },
            ),
          ReaderMenuAction(
            label: 'Full screen',
            icon: Icons.fullscreen,
            onTap: () {
              ReaderControlsScope.of(context)?.value = false;
              ReaderControlsScope.toggleFullscreenOf(context)?.call();
            },
          ),
          ReaderMenuAction(
            label: 'Share',
            icon: Icons.share_outlined,
            onTap: () {
              ReaderControlsScope.of(context)?.value = false;
              shareDocument(context, widget.repository, widget.book);
            },
          ),
          ReaderMenuAction(
            label: 'Settings',
            icon: Icons.settings_outlined,
            onTap: () {
              ReaderControlsScope.of(context)?.value = false;
              Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Reading appearance')),
                    body: SafeArea(
                      child: SettingsScreen(
                        preferences: widget.preferences,
                        showTextOptions: !image && !legacy,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      if (includeEdit)
        ReaderEditMenu(
          book: widget.book,
          repository: widget.repository,
          onAnnotate: !image && !legacy
              ? () => setState(() => _annotationMode = true)
              : null,
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (legacy) {
      return ReaderControlsOverlay(
        controls: _basicMenu(),
        child: Center(child: SingleChildScrollView(child: conversion())),
      );
    }
    if (image) {
      final signature =
          '${widget.preferences.viewingFit}-${widget.preferences.viewingZoom}';
      if (_lastImageView != signature) {
        _lastImageView = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _imageZoom.value = widget.preferences.viewingFit == 'custom'
              ? Matrix4.diagonal3Values(
                  widget.preferences.viewingZoom,
                  widget.preferences.viewingZoom,
                  1,
                )
              : Matrix4.identity();
          setState(
            () => _imageFit = widget.preferences.viewingFit == 'fitWidth'
                ? BoxFit.fitWidth
                : BoxFit.contain,
          );
        });
      }

      return ReaderControlsOverlay(
        controls: _basicMenu(),
        child: FutureBuilder<List<Uint8List>>(
          future: frames,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not read this image.'));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                ReadingProgress.instance.record(
                  widget.book.id,
                  (imagePage + 1) / snapshot.data!.length,
                );
              }
            });
            return Stack(
              children: [
                Positioned.fill(
                  child: PageView.builder(
                    controller: _imagePages,
                    itemCount: snapshot.data!.length,
                    onPageChanged: (i) {
                      setState(() => imagePage = i);
                      _imageZoom.value = Matrix4.identity();
                      ReadingProgress.instance.record(
                        widget.book.id,
                        (i + 1) / snapshot.data!.length,
                      );
                    },
                    itemBuilder: (context, i) => LayoutBuilder(
                      builder: (context, size) => InteractiveViewer(
                        transformationController: _imageZoom,
                        minScale: .5,
                        maxScale: 8,
                        child: SizedBox(
                          width: size.maxWidth,
                          height: size.maxHeight,
                          child: widget.book.format == BookFormat.svg
                              ? SvgPicture.memory(
                                  snapshot.data![i],
                                  fit: _imageFit,
                                  semanticsLabel: widget.book.title,
                                )
                              : Image.memory(
                                  snapshot.data![i],
                                  fit: _imageFit,
                                  semanticLabel: widget.book.title,
                                  errorBuilder: (_, error, stack) => const Text(
                                    'Could not decode this image.',
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: ReaderBottomBar(
                    preferences: widget.preferences,
                    label: '${imagePage + 1} / ${snapshot.data!.length}',
                    onPrevious: imagePage > 0
                        ? () => _imagePages.previousPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                          )
                        : null,
                    onNext: imagePage + 1 < snapshot.data!.length
                        ? () => _imagePages.nextPage(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                          )
                        : null,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }
    return ReaderControlsOverlay(
      controls: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _basicMenu(includeEdit: false),
          const Divider(color: Color(0xff46515a)),
          ReaderMenuGrid(
            children: [
              ReaderMenuAction(
                label: 'Page dark mode',
                icon: Icons.dark_mode_outlined,
                selected: widget.preferences.pageDark,
                onTap: () {
                  ReaderControlsScope.of(context)?.value = false;
                  widget.preferences.setPageDark(!widget.preferences.pageDark);
                },
              ),
              ReaderMenuAction(
                label: 'Find in document',
                icon: Icons.search,
                onTap: () {
                  ReaderControlsScope.of(context)?.value = false;
                  epub.currentState?.searchDocument();
                },
              ),
              ReaderMenuAction(
                label: 'Contents',
                icon: Icons.menu_book_outlined,
                onTap: () {
                  ReaderControlsScope.of(context)?.value = false;
                  epub.currentState?.toggleContents();
                },
              ),
              ReaderMenuAction(
                label: 'Display mode',
                icon: Icons.chrome_reader_mode_outlined,
                onTap: () {
                  ReaderControlsScope.of(context)?.value = false;
                  epub.currentState?.showDisplayModes();
                },
              ),
              TextAlignmentMenu(preferences: widget.preferences),
              ReaderMenuAction(
                label: 'Colors',
                icon: Icons.palette_outlined,
                onTap: () {
                  ReaderControlsScope.of(context)?.value = false;
                  chooseColor();
                },
              ),
              for (final entry in const {
                MarkTool.highlight: (Icons.border_color, 'Highlight'),
                MarkTool.underline: (Icons.format_underlined, 'Underline'),
                MarkTool.strikethrough: (
                  Icons.strikethrough_s,
                  'Strikethrough',
                ),
                MarkTool.note: (Icons.add_comment_outlined, 'Add note'),
                MarkTool.browse: (Icons.pan_tool_outlined, 'Read / scroll'),
              }.entries)
                ReaderMenuAction(
                  label: entry.value.$2,
                  icon: entry.value.$1,
                  selected: tool == entry.key,
                  onTap: () {
                    ReaderControlsScope.of(context)?.value = false;
                    setState(
                      () => tool = tool == entry.key
                          ? MarkTool.browse
                          : entry.key,
                    );
                  },
                ),
              if (supportsLocalConversion &&
                  (officeArchiveFormats.contains(widget.book.format) ||
                      widget.book.format == BookFormat.rtf ||
                      widget.book.format == BookFormat.mobi))
                ReaderMenuAction(
                  label: converting ? 'Converting…' : 'PDF layout',
                  icon: Icons.picture_as_pdf_outlined,
                  onTap: converting
                      ? null
                      : () {
                          ReaderControlsScope.of(context)?.value = false;
                          convert();
                        },
                ),
            ],
          ),
          ReaderEditMenu(
            book: widget.book,
            repository: widget.repository,
            onAnnotate: () => setState(() => _annotationMode = true),
          ),
          if (conversionError != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Text(conversionError!),
                  if (supportsLocalConversion)
                    TextButton(
                      onPressed: converting
                          ? null
                          : () => convert(chooseExecutable: true),
                      child: Text(
                        'Choose ${conversionTool(widget.book.format)} executable',
                      ),
                    ),
                ],
              ),
            ),
          if (officeArchiveFormats.contains(widget.book.format) ||
              widget.book.format == BookFormat.rtf)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text('Reading view · Original page layout may differ.'),
            ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: EpubReader(
              key: epub,
              paperTexture: widget.book.format == BookFormat.mobi,
              bytes: bytes,
              parsedDocument: document,
              preferences: widget.preferences,
              annotations: annotations,
              color: color,
              activeTool: tool,
              annotationMode: _annotationMode,
              onAnnotate: () => setState(() {
                _annotationMode = true;
                tool = MarkTool.browse;
              }),
              insertText: _insertText,
              insertImage: _insertImage,
              onPlaced: _placed,
              onProgress: (value) =>
                  ReadingProgress.instance.record(widget.book.id, value),
            ),
          ),
          if (_annotationMode)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: AnnotationToolbar(
                tool: tool,
                onTool: (kind) => setState(() => tool = kind),
                onText: _addText,
                onImage: _addImage,
                onColor: chooseColor,
                onUndo: () => annotations.undo(
                  'chapter:${(epub.currentState?.section ?? 0) + 1}',
                ),
                onExit: () => setState(() {
                  _annotationMode = false;
                  tool = MarkTool.browse;
                }),
              ),
            ),
        ],
      ),
    );
  }
}
