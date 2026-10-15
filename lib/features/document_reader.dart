import '../data/document_links.dart';

import 'dart:async';

import 'continuous_pdf_layout.dart';
import 'reader_pdf_conversion.dart';
import 'annotation_color_picker.dart';
import 'reading_typography.dart';
import 'highlighter_icon.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:pdfrx/pdfrx.dart';

import 'epub_reader.dart';
import 'text_alignment_menu.dart';
import '../core/preferences.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'annotations.dart';
import 'annotation_toolbar.dart';
import 'text_mark_geometry.dart';
import 'pdf_navigation.dart';
import 'find_match_bar.dart';
import 'contents_panel.dart';
import 'reader_controls.dart';
import 'selection_panel.dart';
import 'reader_edit_menu.dart';
import '../data/reading_progress.dart';
import '../data/document_sharing.dart';
import 'settings.dart';
import 'reader_gestures.dart';
import 'page_turn.dart';
import '../data/pdf_page_colors.dart';
import '../data/pdf_editing.dart';
import 'pdf_region_picker.dart';
import 'edit.dart' show PdfResultScreen;

class DocumentReader extends StatefulWidget {
  const DocumentReader({
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
  State<DocumentReader> createState() => _DocumentReaderState();
}

class _DocumentReaderState extends State<DocumentReader> {
  late final Future<Uint8List> _bytes;
  late final AnnotationStore annotations;
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

  String anchor = 'page:1';
  List<List<Offset>> signature = [];
  var viewer = PdfViewerController();
  final epubReader = GlobalKey<EpubReaderState>();
  PdfDocumentRef? _pdfRef;
  bool? _pdfDark;
  int _pdfAppearanceEpoch = 0;
  Matrix4? _appearanceMatrix;
  String? _lastViewing;
  bool _selectionBusy = false;
  bool _redacting = false;
  String _openedPassword = '';
  bool _markImages = false;
  int? _inkColor;
  double _penSize = 3;
  double _markerSize = 18;
  double _eraserSize = 24;
  final _textIndex = PdfTextIndex();
  PdfFindSession? _find;
  int _findGeneration = 0;
  String _display = 'Continuous';
  bool _showContents = false;
  Future<List<PdfOutlineNode>>? _outline;
  final gestures = ReaderGestureSession();
  final pageTurn = GlobalKey<PageTurnState>();
  final Map<int, Future<PdfPageText?>> _pageText = {};
  Future<void> _previewPending = Future.value();
  int _strokeGeneration = 0;
  int _previewRevision = 0;
  bool get _textTool => [
    MarkTool.highlight,
    MarkTool.underline,
    MarkTool.strikethrough,
    MarkTool.note,
  ].contains(tool);
  double get _strokeWidth =>
      (tool == MarkTool.highlight ? _markerSize : _penSize) / 600;

  @override
  void initState() {
    super.initState();
    _annotationMode = widget.annotationMode;
    annotations =
        widget.annotationStore ?? (AnnotationStore(widget.book.id)..load());
    // Native PDFs stream from disk in the viewer; EPUB and browser PDFs use bytes.
    _bytes =
        widget.book.format == BookFormat.pdf && widget.book.localPath != null
        ? Future.value(Uint8List(0))
        : widget.repository.readDocument(widget.book);
  }

  @override
  void dispose() {
    gestures.dispose();
    if (widget.annotationStore == null) annotations.dispose();
    super.dispose();
  }

  Future<bool> _previewText(
    PdfPage page,
    List<Offset> points,
    Size size,
  ) async {
    if (points.isEmpty ||
        !_textTool ||
        _markImages ||
        !viewer.isReady ||
        !viewer.textSelectionDelegate.isCopyAllowed) {
      return false;
    }
    final text = await _pageText.putIfAbsent(
      page.pageNumber,
      page.loadStructuredText,
    );
    if (text == null || !mounted || !viewer.isReady || gestures.value) {
      return false;
    }
    final boxes = text.charRects
        .map((r) => normalizedPdfMarkRect(r, page))
        .toList();
    int closest(Offset point) {
      int best = -1;
      double distance = double.infinity;
      for (int i = 0; i < boxes.length; i++) {
        final r = boxes[i];
        if (r.isEmpty) continue;
        final dx = (point.dx - point.dx.clamp(r.left, r.right)) * size.width;
        final dy = (point.dy - point.dy.clamp(r.top, r.bottom)) * size.height;
        final d = dx * dx + dy * dy;
        if (d < distance) {
          best = i;
          distance = d;
        }
      }
      return best;
    }

    final a = closest(points.first), b = closest(points.last);
    if (a < 0 ||
        b < 0 ||
        boxes[a].inflate(18 / size.shortestSide).contains(points.first) ==
            false) {
      return false;
    }
    // PdfTextSelectionPoint indices are inclusive, including the last glyph.
    final start = a < b ? a : b;
    final end = a > b ? a : b;
    await viewer.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(text, start),
        PdfTextSelectionPoint(text, end),
      ),
    );
    return true;
  }

  void _previewStroke(PdfPage page, List<Offset> points, Size size) {
    final generation = _strokeGeneration;
    final revision = ++_previewRevision;
    _previewPending = _previewPending.then((_) async {
      if (mounted &&
          generation == _strokeGeneration &&
          revision == _previewRevision &&
          !gestures.value) {
        try {
          await _previewText(page, points, size);
        } catch (_) {
          /* Keep image marking available when extraction fails. */
        }
      }
    });
  }

  void _cancelTextStroke() {
    _strokeGeneration++;
    _previewRevision++;
    _previewPending = _previewPending.then((_) async {
      if (mounted && viewer.isReady) {
        await viewer.textSelectionDelegate.clearTextSelection();
      }
    });
  }

  Future<bool> _applyTextStroke(
    PdfPage page,
    List<Offset> points,
    Size size,
  ) async {
    final kind = tool;
    final generation = _strokeGeneration;
    await _previewPending;
    if (!mounted || generation != _strokeGeneration || gestures.value) {
      return true;
    }
    try {
      if (!await _previewText(page, points, size)) {
        return false; // Image/scan: draw a mark instead.
      }
    } catch (_) {
      return false;
    }
    if (mounted) await _markSelection(kind);
    return true;
  }

  void _twoFingerNavigate(Offset delta, Offset focal, double scale) {
    if (!viewer.isReady) return;
    final current = viewer.value;
    final zoom = viewer.currentZoom;
    final nextZoom = (zoom * scale).clamp(viewer.minScale, viewer.maxScale);
    final ratio = nextZoom / zoom;
    final previousFocal = focal - delta;
    final next = current.clone();
    next.setEntry(0, 0, nextZoom);
    next.setEntry(1, 1, nextZoom);
    next.setEntry(
      0,
      3,
      focal.dx + (current.entry(0, 3) - previousFocal.dx) * ratio,
    );
    next.setEntry(
      1,
      3,
      focal.dy + (current.entry(1, 3) - previousFocal.dy) * ratio,
    );
    viewer.value = viewer.makeMatrixInSafeRange(next);
  }

  Future<void> _turnPage(int direction) async {
    if (!viewer.isReady) return;
    final current = viewer.pageNumber ?? 1;
    final target = (current + direction * (_display == 'Dual page' ? 2 : 1))
        .clamp(1, viewer.pageCount);
    if (target == current) return;
    await pageTurn.currentState?.turn(direction, () {
      if (_display == 'Dual page' || _display == 'Continuous') {
        _goPage(target);
        return;
      }
      final matrix = viewer.calcMatrixForPage(pageNumber: target);
      viewer.value = matrix;
    });
  }

  PdfDocumentRef _documentRef() {
    final dark = widget.preferences.pageDark && supportsPdfPageColors;
    if (_pdfRef != null && _pdfDark == dark) return _pdfRef!;
    if (_pdfRef != null && viewer.isReady) {
      _appearanceMatrix = Matrix4.copy(viewer.value);
    }
    if (_pdfRef != null) viewer = PdfViewerController();
    _pdfAppearanceEpoch++;
    _pdfDark = dark;
    _pageText.clear();
    _pdfRef = PdfDocumentRefByLoader(
      (_) async {
        await pdfrxFlutterInitialize();
        final document = widget.book.localPath != null
            ? await PdfDocument.openFile(
                widget.book.localPath!,
                passwordProvider: _password,
              )
            : await PdfDocument.openData(
                await _bytes,
                sourceName: widget.book.id,
                passwordProvider: _password,
              );
        return dark ? applyPdfPageColors(document) : document;
      },
      key: PdfDocumentRefKey(widget.book.id, [
        dark,
        _pdfAppearanceEpoch,
        identityHashCode(this),
      ]),
    );
    return _pdfRef!;
  }

  Future<void> _markSelection(
    MarkTool kind, [
    PdfTextSelectionDelegate? delegate,
  ]) async {
    if (!viewer.isReady ||
        !annotations.loaded ||
        annotations.loadFailed ||
        _selectionBusy) {
      return;
    }
    final selection = delegate ?? viewer.textSelectionDelegate;
    if (!selection.hasSelectedText || !selection.isCopyAllowed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select text first.')));
      return;
    }
    _selectionBusy = true;
    try {
      final ranges = await selection.getSelectedTextRanges();
      if (!mounted || !viewer.isReady) return;
      final marks = <DocumentMark>[];
      final group = DateTime.now().microsecondsSinceEpoch.toString();
      // Capture the original range before the note dialog changes selection.
      for (final range in ranges) {
        final page = viewer.pages[range.pageNumber - 1];
        final rects = selectedPdfLineRects(range, page);
        if (rects.isEmpty) continue;
        marks.add(
          DocumentMark(
            anchor: 'page:${range.pageNumber}',
            tool: kind,
            rects: rects,
            quote: range.text,
            start: range.start,
            end: range.end,
            group: group,
            color: _inkColor,
            width: _penSize / 600,
            rotation: page.rotation.index,
          ),
        );
      }
      if (marks.isEmpty) return;
      String note = '';
      List<String> attachments = [];
      if (kind == MarkTool.note) {
        final result = await editNoteContent(context);
        if (result == null || !mounted) return;
        note = result.text;
        attachments = result.images;
      }
      await annotations.addMany(
        marks
            .map(
              (m) => DocumentMark(
                anchor: m.anchor,
                tool: m.tool,
                rects: m.rects,
                quote: m.quote,
                text: note,
                attachments: attachments,
                start: m.start,
                end: m.end,
                group: m.group,
                color: m.color,
                width: m.width,
                rotation: m.rotation,
              ),
            )
            .toList(),
      );
      if (mounted && viewer.isReady) await selection.clearTextSelection();
    } finally {
      _selectionBusy = false;
    }
  }

  Widget? _selectionMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams params,
  ) {
    final delegate = params.textSelectionDelegate;
    if (!delegate.hasSelectedText || !delegate.isCopyAllowed) return null;
    return Positioned.fill(
      child: SelectionPanel(
        readText: delegate.getSelectedText,
        onClose: () {
          params.dismissContextMenu();
          unawaited(delegate.clearTextSelection());
        },
        onAnnotate: () {
          if (!mounted) return;
          setState(() {
            _annotationMode = true;
            tool = MarkTool.browse;
          });
          ReaderControlsScope.chromeOf(context)
              ?.activity(autoHide: widget.preferences.autoHideControls);
        },
        onMark: (kind, color) async {
          setState(() => _inkColor = color);
          await _markSelection(kind, delegate);
        },
      ),
    );
  }

  Future<void> _notes() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListenableBuilder(
            listenable: annotations,
            builder: (context, _) => Column(
              children: [
                ListTile(
                  title: const Text('Annotations'),
                  trailing: IconButton(
                    tooltip: 'Close',
                    icon: const ReaderToolIcon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Expanded(
                  child: _noteEntries.isEmpty
                      ? const Center(child: Text('No annotations'))
                      : ListView.builder(
                          itemCount: _noteEntries.length,
                          itemBuilder: (context, index) {
                            final mark = _noteEntries[index];
                            return ListTile(
                              onTap: mark.tool == MarkTool.note
                                  ? () => showPageNotes(
                                      context,
                                      annotations,
                                      mark.anchor,
                                      selected: mark,
                                    )
                                  : null,
                              title: Text(
                                mark.text.isEmpty ? mark.tool.name : mark.text,
                              ),
                              subtitle: Text(
                                '${mark.anchor.replaceFirst('page:', 'Page ').replaceFirst('chapter:', 'Chapter ')}${mark.quote.isEmpty ? '' : '\n${mark.quote}'}',
                              ),
                              trailing: IconButton(
                                tooltip: 'Delete annotation',
                                icon: const ReaderToolIcon(
                                  Icons.delete_outline,
                                ),
                                onPressed: () => annotations.remove(mark),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<DocumentMark> get _noteEntries =>
      annotations.entries.where((m) => m.tool != MarkTool.bookmark).toList();

  Future<void> _chooseTool(MarkTool kind, bool epub) async {
    if (epub) {
      setState(() => tool = tool == kind ? MarkTool.browse : kind);
      return;
    }
    if ([
          MarkTool.highlight,
          MarkTool.underline,
          MarkTool.strikethrough,
          MarkTool.note,
        ].contains(kind) &&
        viewer.isReady &&
        viewer.textSelectionDelegate.hasSelectedText) {
      await _markSelection(kind);
      if (mounted) setState(() => tool = kind);
      return;
    }
    if (kind == MarkTool.signature) {
      final strokes = await showDialog<List<List<Offset>>>(
        context: context,
        builder: (_) => const SignaturePad(),
      );
      if (strokes == null || !mounted) return;
      signature = strokes;
    }
    if (mounted) {
      setState(() {
        tool = tool == kind ? MarkTool.browse : kind;
        _markImages = false;
      });
    }
  }

  Future<void> _bookmark() async {
    final matches = annotations.marks
        .where((m) => m.tool == MarkTool.bookmark && m.anchor == anchor)
        .toList();
    if (matches.isNotEmpty) {
      await annotations.remove(matches.first);
    } else {
      final epub = epubReader.currentState;
      await annotations.add(
        DocumentMark(
          anchor: anchor,
          tool: MarkTool.bookmark,
          text: anchor
              .replaceFirst('page:', 'Page ')
              .replaceFirst('chapter:', 'Chapter '),
          points: epub == null ? [] : [Offset(0, epub.bookmarkFraction)],
        ),
      );
    }
  }

  Future<void> _bookmarks() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListenableBuilder(
          listenable: annotations,
          builder: (context, _) {
            final marks = annotations.marks
                .where((m) => m.tool == MarkTool.bookmark)
                .toList();
            return SizedBox(
              height: MediaQuery.sizeOf(context).height * .6,
              child: Column(
                children: [
                  const ListTile(title: Text('Bookmarks')),
                  Expanded(
                    child: marks.isEmpty
                        ? const Center(child: Text('No bookmarks yet'))
                        : ListView(
                            children: marks
                                .map(
                                  (mark) => ListTile(
                                    leading: const ReaderToolIcon(
                                      Icons.bookmark,
                                    ),
                                    title: Text(mark.text),
                                    trailing: IconButton(
                                      tooltip: 'Remove bookmark',
                                      icon: const ReaderToolIcon(Icons.close),
                                      onPressed: () => annotations.remove(mark),
                                    ),
                                    onTap: () {
                                      Navigator.pop(context);
                                      final number =
                                          int.tryParse(
                                            mark.anchor.split(':').last,
                                          ) ??
                                          1;
                                      if (mark.anchor.startsWith('page:') &&
                                          viewer.isReady) {
                                        _goPage(number);
                                      } else {
                                        epubReader.currentState
                                            ?.restoreBookmark(
                                              number - 1,
                                              mark.points.isEmpty
                                                  ? 0
                                                  : mark.points.first.dy,
                                            );
                                      }
                                    },
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _redact() async {
    if (_redacting || !viewer.isReady) return;
    setState(() => _redacting = true);
    try {
      final page = (int.tryParse(anchor.split(':').last) ?? 1) - 1;
      final clean = await PdfEditing.unprotect(
        await widget.repository.readDocument(widget.book),
        _openedPassword,
      );
      if (!mounted) return;
      final region = await Navigator.push<Rect>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              PdfRegionPicker(bytes: clean, page: page, title: 'Redact'),
        ),
      );
      if (region == null || !mounted) return;
      final result = await PdfEditing.redact(clean, page, region);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PdfResultScreen(
            bytes: result,
            name: '${widget.book.title} - Redacted',
            repository: widget.repository,
            onSaved: () {},
            message: 'The selected area is removed from a flattened copy. Text, forms, and links are removed.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not redact this page.')),
        );
      }
    } finally {
      if (mounted) setState(() => _redacting = false);
    }
  }

  Future<void> _drawingOptions([bool epub = false]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          void change(VoidCallback action) {
            setState(action);
            update(() {});
          }

          final colors = <String, Color>{
            'Black': Colors.black,
            'White': Colors.white,
            'Blue': const Color(0xff1565c0),
            'Red': const Color(0xffc62828),
            'Green': const Color(0xff2e7d32),
            'Purple': const Color(0xff7b1fa2),
            'Yellow': const Color(0xffffcc00),
            'Pink': const Color(0xffec407a),
          };
          Widget slider(
            String label,
            double value,
            double minimum,
            double maximum,
            ValueChanged<double> changed,
          ) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$label: ${value.round()}',
                style: Theme.of(sheetContext).textTheme.titleSmall,
              ),
              Slider(
                value: value,
                min: minimum,
                max: maximum,
                divisions: (maximum - minimum).round(),
                label: value.round().toString(),
                onChanged: changed,
              ),
            ],
          );
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Annotation colors${epub ? '' : ' & sizes'}',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Automatic'),
                        selected: _inkColor == null,
                        onSelected: (_) => change(() => _inkColor = null),
                      ),
                      for (final entry in colors.entries)
                        ChoiceChip(
                          label: Text(entry.key),
                          avatar: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: entry.value,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey),
                            ),
                          ),
                          selected: _inkColor == entry.value.toARGB32(),
                          onSelected: (_) =>
                              change(() => _inkColor = entry.value.toARGB32()),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.color_lens_outlined),
                    label: const Text('Custom color wheel'),
                    onPressed: () async {
                      final picked = await pickAnnotationColor(
                        sheetContext,
                        initial: Color(_inkColor ?? 0xffffcc00),
                      );
                      if (picked != null && mounted && sheetContext.mounted) {
                        change(() => _inkColor = picked.toARGB32());
                      }
                    },
                  ),
                  if (!epub) ...[
                    const SizedBox(height: 20),
                    slider(
                      'Pen / line size',
                      _penSize,
                      1,
                      12,
                      (v) => change(() => _penSize = v),
                    ),
                    slider(
                      'Marker size',
                      _markerSize,
                      8,
                      40,
                      (v) => change(() => _markerSize = v),
                    ),
                    slider(
                      'Stroke eraser size',
                      _eraserSize,
                      8,
                      48,
                      (v) => change(() => _eraserSize = v),
                    ),
                    SizedBox(
                      height: 48,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: MarkPainter(
                          marks: [
                            DocumentMark(
                              anchor: '',
                              tool: MarkTool.pen,
                              color: _inkColor,
                              width: _penSize / 600,
                              points: const [
                                Offset(.1, .6),
                                Offset(.3, .2),
                                Offset(.5, .8),
                                Offset(.7, .2),
                                Offset(.9, .6),
                              ],
                            ),
                          ],
                          dark:
                              Theme.of(sheetContext).brightness ==
                              Brightness.dark,
                        ),
                      ),
                    ),
                  ],
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _displayModes() async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final name in ['Continuous', 'Single page', 'Dual page'])
              ListTile(
                title: Text(name),
                selected: _display == name,
                onTap: () => Navigator.pop(context, name),
              ),
          ],
        ),
      ),
    );
    if (mode == null || !mounted) return;
    final target = int.tryParse(anchor.split(':').last) ?? 1;
    setState(() => _display = mode);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !viewer.isReady) return;
      viewer.invalidate();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !viewer.isReady) return;
        _goPage(target);
      });
    });
  }

  void _goPage(int number) {
    if (!viewer.isReady) return;
    final page = number.clamp(1, viewer.pageCount);
    if (_display == 'Continuous' && widget.preferences.viewingFit != 'custom') {
      final matrix = viewer.calcMatrixFitWidthForPage(pageNumber: page);
      if (matrix != null) viewer.value = viewer.makeMatrixInSafeRange(matrix);
    } else if (_display == 'Dual page') {
      final first = ((page - 1) ~/ 2) * 2;
      final layouts = viewer.layout.pageLayouts;
      var rect = layouts[first];
      if (first + 1 < layouts.length) {
        rect = rect.expandToInclude(layouts[first + 1]);
      }
      viewer.value = viewer.calcMatrixForArea(rect: rect);
    } else {
      viewer.goToPage(pageNumber: page);
    }
  }

  Future<void> _shapes() async {
    final kind = await showModalBottomSheet<MarkTool>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in const {
              MarkTool.arrow: (Icons.arrow_right_alt, 'Arrow'),
              MarkTool.rectangle: (Icons.crop_square, 'Rectangle'),
              MarkTool.callout: (Icons.chat_bubble_outline, 'Callout'),
              MarkTool.note: (Icons.sticky_note_2_outlined, 'Margin note'),
            }.entries)
              ListTile(
                leading: ReaderToolIcon(entry.value.$1),
                title: Text(entry.value.$2),
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == MarkTool.note || kind == MarkTool.callout) {
      final text = await editNote(context);
      if (text == null || !mounted) return;
      _shapeText = text;
    }
    setState(() {
      tool = kind;
      _markImages = true;
    });
  }

  String _shapeText = '';

  PdfPageLayout _layout(List<PdfPage> pages, PdfViewerParams params) {
    if (_display == 'Continuous') {
      return continuousPdfLayout(
        pages.map((page) => Size(page.width, page.height)),
      );
    }
    final layouts = <Rect>[];
    final margin = params.margin;
    double width = 0, height = margin;
    if (_display == 'Dual page') {
      for (int i = 0; i < pages.length; i += 2) {
        final a = pages[i];
        final b = i + 1 < pages.length ? pages[i + 1] : null;
        final rowWidth = a.width + (b?.width ?? a.width) + margin * 3;
        if (rowWidth > width) width = rowWidth;
        layouts.add(Rect.fromLTWH(margin, height, a.width, a.height));
        if (b != null) {
          layouts.add(
            Rect.fromLTWH(margin * 2 + a.width, height, b.width, b.height),
          );
        }
        height +=
            (b != null && b.height > a.height ? b.height : a.height) + margin;
      }
    } else if (_display == 'Single page') {
      final maxHeight =
          pages.fold<double>(0, (h, p) => p.height > h ? p.height : h) +
          margin * 2;
      double x = margin;
      for (final page in pages) {
        layouts.add(Rect.fromLTWH(x, margin, page.width, page.height));
        x += page.width + margin;
      }
      return PdfPageLayout(
        pageLayouts: layouts,
        documentSize: Size(x, maxHeight),
      );
    } else {
      width =
          pages.fold<double>(0, (w, p) => p.width > w ? p.width : w) +
          margin * 2;
      for (final page in pages) {
        layouts.add(
          Rect.fromLTWH(
            (width - page.width) / 2,
            height,
            page.width,
            page.height,
          ),
        );
        height += page.height + margin;
      }
    }
    return PdfPageLayout(
      pageLayouts: layouts,
      documentSize: Size(width, height),
    );
  }

  Future<void> _addText() async {
    final draft = await composeAnnotationText(context);
    if (!mounted || draft == null) return;
    setState(() {
      _insertText = draft;
      _annotationMode = true;
      tool = MarkTool.text;
    });
  }

  Future<void> _addImage() async {
    try {
      final image = await pickAnnotationImage();
      if (!mounted || image == null) return;
      setState(() {
        _insertImage = image;
        _annotationMode = true;
        tool = MarkTool.image;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message.toString()
                  : 'Could not open this image.',
            ),
          ),
        );
      }
    }
  }

  Widget _annotationBar(bool epub) => ListenableBuilder(
    listenable: annotations,
    builder: (context, _) => AnnotationToolbar(
      tool: tool,
      onTool: (kind) => setState(() => tool = kind),
      onText: _addText,
      onImage: _addImage,
      onColor: () => _drawingOptions(epub),
      onUndo: annotations.canUndo(anchor)
          ? () => annotations.undo(anchor)
          : null,
      onExit: () => setState(() {
        _annotationMode = false;
        tool = MarkTool.browse;
      }),
    ),
  );

  Future<void> _showFindHit(int index) async {
    final session = _find;
    if (session == null || !viewer.isReady || session.hits.isEmpty) return;
    final token = ++_findGeneration;
    final selected = index.clamp(0, session.hits.length - 1);
    setState(() => _find = session.withIndex(selected));
    final hit = session.hits[selected];
    final page = viewer.pages[hit.page - 1];
    final text = await page.loadStructuredText();
    if (!mounted || !viewer.isReady || token != _findGeneration) return;
    _goPage(hit.page);
    if (text.charRects.isNotEmpty &&
        hit.start < text.charRects.length &&
        viewer.textSelectionDelegate.isCopyAllowed) {
      await viewer.goToRectInsidePage(
        pageNumber: hit.page,
        rect: text.charRects[hit.start],
      );
      if (!mounted || token != _findGeneration) return;
      await viewer.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(text, hit.start),
          PdfTextSelectionPoint(
            text,
            (hit.end - 1).clamp(0, text.charRects.length - 1),
          ),
        ),
      );
    }
  }

  void _applyViewing() {
    if (!viewer.isReady) return;
    final page = viewer.pageNumber ?? 1;
    final prefs = widget.preferences;
    final matrix =
        prefs.viewingFit == 'fitWidth' ||
            (_display == 'Continuous' && prefs.viewingFit != 'custom')
        ? viewer.calcMatrixFitWidthForPage(pageNumber: page)
        : viewer.calcMatrixForRect(
            viewer.layout.pageLayouts[page - 1],
            margin: 0,
          );
    if (prefs.viewingFit == 'custom') {
      viewer.setZoom(
        viewer.layout.pageLayouts[page - 1].center,
        prefs.viewingZoom.clamp(viewer.minScale, viewer.maxScale),
      );
    } else if (matrix != null) {
      viewer.value = viewer.makeMatrixInSafeRange(matrix);
    }
  }

  Future<void> _fitting() async {
    if (!viewer.isReady) return;
    await showReaderZoom(
      context,
      current: viewer.currentZoom,
      onZoom: (zoom) {
        widget.preferences.setViewing(fit: 'custom', zoom: zoom);
        if (viewer.isReady) {
          viewer.setZoom(
            viewer.layout.pageLayouts[(viewer.pageNumber ?? 1) - 1].center,
            zoom.clamp(viewer.minScale, viewer.maxScale),
          );
        }
      },
      onBestFit: () {
        widget.preferences.setViewing(fit: 'bestFit');
        _applyViewing();
      },
      onFitWidth: () {
        widget.preferences.setViewing(fit: 'fitWidth');
        if (!viewer.isReady) return;
        final matrix = viewer.calcMatrixFitWidthForPage(
          pageNumber: viewer.pageNumber ?? 1,
        );
        if (matrix != null) viewer.value = viewer.makeMatrixInSafeRange(matrix);
      },
    );
  }

  Widget _toolbar(bool epub) => ListenableBuilder(
    listenable: annotations,
    builder: (context, _) {
      final bookmarked = annotations.marks.any(
        (m) => m.tool == MarkTool.bookmark && m.anchor == anchor,
      );
      final ready = annotations.loaded && !annotations.loadFailed;
      Widget action(
        String label,
        IconData icon,
        VoidCallback? callback, {
        bool selected = false,
      }) => ReaderMenuAction(
        label: label,
        icon: icon,
        selected: selected,
        onTap: callback == null
            ? null
            : () {
                ReaderControlsScope.of(context)?.value = false;
                callback();
              },
      );
      void navigate() {
        if (viewer.isReady) {
          Navigator.push<PdfFindSession>(
            context,
            MaterialPageRoute(
              builder: (_) => PdfNavigationScreen(
                controller: viewer,
                index: _textIndex,
                initialFind: _find,
              ),
            ),
          ).then((session) {
            if (session != null && mounted) {
              setState(() => _find = session);
              _showFindHit(session.active);
            }
          });
        }
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ReaderMenuGrid(
            children: [
              action(
                'Page dark mode',
                Icons.dark_mode_outlined,
                () => widget.preferences.setPageDark(
                  !widget.preferences.pageDark,
                ),
                selected: widget.preferences.pageDark,
              ),
              action(
                'Find in document',
                Icons.search,
                epub
                    ? () {
                        epubReader.currentState?.searchDocument();
                      }
                    : navigate,
              ),
              if (!epub)
                action('Go to page', Icons.auto_stories_outlined, navigate),
              action(
                'Bookmark page',
                bookmarked ? Icons.bookmark : Icons.bookmark_border,
                ready ? _bookmark : null,
                selected: bookmarked,
              ),
              action(
                epub ? 'Font, size & alignment' : 'Page fitting',
                Icons.fit_screen,
                epub
                    ? () => showReadingTypography(context, widget.preferences)
                    : _fitting,
              ),
              action(
                'Annotation mode',
                Icons.draw_outlined,
                () => setState(() {
                  _annotationMode = true;
                  tool = MarkTool.browse;
                }),
              ),
              action(
                'Page notes',
                Icons.sticky_note_2_outlined,
                () => showPageNotes(context, annotations, anchor),
              ),
              action(
                'Reader controls',
                Icons.tune,
                () => showReaderControlOptions(context, widget.preferences),
              ),
              action(
                'Full screen',
                Icons.fullscreen,
                ReaderControlsScope.toggleFullscreenOf(context),
              ),
              action(
                'Display mode',
                Icons.chrome_reader_mode_outlined,
                epub
                    ? () => epubReader.currentState?.showDisplayModes()
                    : _displayModes,
              ),
              action(
                'Share',
                Icons.share_outlined,
                () => shareDocument(context, widget.repository, widget.book),
              ),
              if (!epub)
                action(
                  'Add signature',
                  Icons.gesture,
                  ready ? () => _chooseTool(MarkTool.signature, false) : null,
                ),
            ],
          ),
          const Divider(color: Color(0xff46515a), height: 24),
          ReaderMenuGrid(
            children: [
              action('Contents', Icons.menu_book_outlined, () {
                if (epub) {
                  epubReader.currentState?.toggleContents();
                } else if (viewer.isReady) {
                  setState(() {
                    _outline ??= viewer.document.loadOutline();
                    _showContents = !_showContents;
                  });
                }
              }),
              action('My bookmarks', Icons.bookmarks_outlined, _bookmarks),
              action('Notes & marks', Icons.sticky_note_2_outlined, _notes),
              action(
                'Highlight',
                Icons.border_color,
                ready ? () => _chooseTool(MarkTool.highlight, epub) : null,
                selected: tool == MarkTool.highlight,
              ),
              action(
                'Underline',
                Icons.format_underlined,
                ready ? () => _chooseTool(MarkTool.underline, epub) : null,
                selected: tool == MarkTool.underline,
              ),
              action(
                'Strikethrough',
                Icons.strikethrough_s,
                ready ? () => _chooseTool(MarkTool.strikethrough, epub) : null,
                selected: tool == MarkTool.strikethrough,
              ),
              action(
                'Add note',
                Icons.add_comment_outlined,
                ready ? () => _chooseTool(MarkTool.note, epub) : null,
                selected: tool == MarkTool.note,
              ),
              if (!epub)
                action(
                  'Draw',
                  Icons.edit_outlined,
                  ready ? () => _chooseTool(MarkTool.pen, false) : null,
                  selected: tool == MarkTool.pen,
                ),
              if (!epub)
                action(
                  'Eraser',
                  Icons.auto_fix_normal,
                  ready ? () => _chooseTool(MarkTool.eraser, false) : null,
                  selected: tool == MarkTool.eraser,
                ),
              action(
                'Undo',
                Icons.undo,
                ready && annotations.canUndo(anchor)
                    ? () {
                        annotations.undo(anchor);
                      }
                    : null,
              ),
              action(
                epub ? 'Colors' : 'Color & size',
                Icons.palette_outlined,
                () => _drawingOptions(epub),
              ),
              if (!epub) action('Shapes', Icons.category_outlined, _shapes),
              if (!epub)
                action(
                  'Redact',
                  Icons.rectangle_outlined,
                  _redacting ? null : _redact,
                ),
              if (epub)
                ConvertPdfMenuAction(
                  book: widget.book,
                  repository: widget.repository,
                  preferences: widget.preferences,
                ),
              if (epub) TextAlignmentMenu(preferences: widget.preferences),
              action(
                'Settings',
                Icons.settings_outlined,
                () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => Scaffold(
                      appBar: AppBar(title: const Text('Reading appearance')),
                      body: SafeArea(
                        child: SettingsScreen(
                          preferences: widget.preferences,
                          showTextOptions: epub,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              action(
                'Read / scroll',
                Icons.pan_tool_outlined,
                () => setState(() => tool = MarkTool.browse),
                selected: tool == MarkTool.browse,
              ),
            ],
          ),
          if (!epub && tool != MarkTool.browse)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Two fingers to navigate',
                      style: TextStyle(color: readerPanelInk),
                    ),
                  ),
                  if (_textTool && tool != MarkTool.note)
                    TextButton(
                      onPressed: () =>
                          setState(() => _markImages = !_markImages),
                      child: Text(_markImages ? 'Select text' : 'Mark images'),
                    ),
                ],
              ),
            ),
          const Divider(color: Color(0xff46515a), height: 24),
          ReaderEditMenu(
            book: widget.book,
            repository: widget.repository,
            onAnnotate: () => setState(() {
              _annotationMode = true;
              tool = MarkTool.browse;
            }),
          ),
          if (annotations.saveFailed || annotations.loadFailed)
            const Text('Annotations could not be saved.'),
        ],
      );
    },
  );

  Future<String?> _password() async {
    if (!mounted) return null;
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PdfPasswordDialog(),
    );
    if (password != null) _openedPassword = password;
    return password;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.book.format == BookFormat.epub) {
      if (anchor.startsWith('page:')) anchor = 'chapter:1';
      return ReaderControlsOverlay(
        controls: _toolbar(true),
        child: Stack(
          children: [
            Positioned.fill(
              child: EpubReader(
                key: epubReader,
                bytes: _bytes,
                preferences: widget.preferences,
                annotations: annotations,
                activeTool: tool,
                annotationMode: _annotationMode,
                onAnnotate: () => setState(() {
                  _annotationMode = true;
                  tool = MarkTool.browse;
                }),
                insertText: _insertText,
                insertImage: _insertImage,
                onPlaced: _placed,
                color: _inkColor,
                onProgress: (value) =>
                    ReadingProgress.instance.record(widget.book.id, value),
                onSectionChanged: (index) =>
                    setState(() => anchor = 'chapter:${index + 1}'),
              ),
            ),
            if (_annotationMode)
              Positioned(
                bottom: 12,
                left: 12,
                right: 12,
                child: _annotationBar(true),
              ),
          ],
        ),
      );
    }
    final viewSignature =
        '${widget.preferences.viewingFit}-${widget.preferences.viewingZoom}';
    if (_lastViewing != viewSignature) {
      _lastViewing = viewSignature;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyViewing();
      });
    }
    final params = PdfViewerParams(
      backgroundColor: Theme.of(context).colorScheme.surface,
      margin: 0,
      panEnabled: tool == MarkTool.browse && _display != 'Single page',
      scaleEnabled: tool == MarkTool.browse,
      layoutPages: _layout,
      onViewSizeChanged: (size, oldSize, controller) {
        if (_display != 'Continuous' ||
            widget.preferences.viewingFit == 'custom' ||
            oldSize == null ||
            oldSize.width == size.width ||
            !controller.isReady) {
          return;
        }
        final center = controller.value.calcPosition(oldSize);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted ||
              !identical(controller, viewer) ||
              !controller.isReady ||
              _display != 'Continuous' ||
              widget.preferences.viewingFit == 'custom') {
            return;
          }
          final width = controller.layout.documentSize.width;
          if (width <= 0) return;
          controller.value = controller.makeMatrixInSafeRange(
            controller.calcMatrixFor(
              center,
              zoom: size.width / width,
              viewSize: size,
            ),
          );
        });
      },
      textSelectionParams: PdfTextSelectionParams(
        enabled: tool == MarkTool.browse || (_textTool && !_markImages),
        showContextMenuAutomatically: tool == MarkTool.browse,
        enableSelectionHandles: tool == MarkTool.browse,
      ),
      buildContextMenu: _selectionMenu,
      linkHandlerParams: tool == MarkTool.browse
          ? PdfLinkHandlerParams(
              onLinkTap: (link) async {
                final opened = await followPdfLink(
                  link,
                  goToDestination: (dest) => viewer.goToDest(dest),
                );
                if (!opened && mounted && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This link target could not be opened.'),
                    ),
                  );
                }
              },
            )
          : null,
      onViewerReady: (document, controller) {
        if (mounted) setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !viewer.isReady) return;
          if (_appearanceMatrix != null) {
            viewer.value = viewer.makeMatrixInSafeRange(_appearanceMatrix!);
            _appearanceMatrix = null;
          } else {
            _applyViewing();
          }
        });
        if (mounted && document.pages.isNotEmpty) {
          ReadingProgress.instance.record(
            widget.book.id,
            (controller.pageNumber ?? 1) / document.pages.length,
          );
        }
      },
      onPageChanged: (page) {
        if (page != null && mounted) {
          if (anchor != 'page:$page') setState(() => anchor = 'page:$page');
          if (viewer.isReady && viewer.pageCount > 0) {
            ReadingProgress.instance.record(
              widget.book.id,
              page / viewer.pageCount,
            );
          }
        }
      },
      pageOverlaysBuilder: (context, pageRect, page) => [
        Positioned.fill(
          child: ListenableBuilder(
            listenable: annotations,
            builder: (context, _) => PageMarks(
              isPdf: true,
              annotationMode: _annotationMode,
              insertText: _insertText?.text ?? '',
              insertImage: _insertImage,
              onPlaced: _placed,
              font: _insertText?.font ?? 'sans-serif',
              fontSize: _insertText?.size ?? 24,
              store: annotations,
              anchor: 'page:${page.pageNumber}',
              tool: tool,
              gestureSession: gestures,
              onTextPreview: _textTool && !_markImages
                  ? (points, size) => _previewStroke(page, points, size)
                  : null,
              onTextStroke: _textTool && !_markImages
                  ? (points, size) => _applyTextStroke(page, points, size)
                  : null,
              onTextCancel: _cancelTextStroke,
              color: _inkColor,
              width: _strokeWidth,
              eraserRadius: _eraserSize / 600,
              shapeText: _shapeText,
              dark: widget.preferences.pageDark && supportsPdfPageColors,
              signature: signature,
              onTouched: () =>
                  setState(() => anchor = 'page:${page.pageNumber}'),
            ),
          ),
        ),
      ],
      errorBannerBuilder: (context, error, stack, reference) =>
          const DocumentReadError(format: 'PDF'),
    );
    return ReaderControlsOverlay(
      controls: _toolbar(false),
      child: Stack(
        children: [
          Positioned.fill(
            child: ReaderGestureSurface(
              session: gestures,
              active: tool != MarkTool.browse,
              onNavigate: _twoFingerNavigate,
              onSwipe: _display == 'Single page' ? _turnPage : null,
              child: PageTurn(
                key: pageTurn,
                paper: widget.preferences.pageDark
                    ? const Color(0xff151515)
                    : Colors.white,
                child: PdfViewer(
                  _documentRef(),
                  key: ValueKey(_pdfAppearanceEpoch),
                  controller: viewer,
                  params: params,
                  initialPageNumber:
                      int.tryParse(anchor.replaceFirst('page:', '')) ?? 1,
                ),
              ),
            ),
          ),
          Positioned(
            top: 64,
            right: 12,
            child: PageNotesButton(store: annotations, anchor: anchor),
          ),
          if (_annotationMode)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: _annotationBar(false),
            ),
          if (!_annotationMode)
            Positioned.fill(
              child: ReaderBottomBar(
                preferences: widget.preferences,
                label: viewer.isReady
                    ? '${viewer.pageNumber ?? 1} / ${viewer.pageCount}'
                    : '',
                onPrevious: viewer.isReady && (viewer.pageNumber ?? 1) > 1
                    ? () => _turnPage(-1)
                    : null,
                onNext:
                    viewer.isReady &&
                        (viewer.pageNumber ?? 1) < viewer.pageCount
                    ? () => _turnPage(1)
                    : null,
              ),
            ),
          if (_find != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 72,
              child: FindMatchBar(
                current: _find!.active,
                count: _find!.hits.length,
                query: _find!.query,
                onPrevious: () => _showFindHit(_find!.active - 1),
                onNext: () => _showFindHit(_find!.active + 1),
                onClose: () {
                  _findGeneration++;
                  setState(() => _find = null);
                  if (viewer.isReady) {
                    viewer.textSelectionDelegate.clearTextSelection();
                  }
                },
              ),
            ),
          if (_showContents && _outline != null)
            Positioned(
              top: 56,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .26,
                  child: ContentsPanel(
                    outline: _outline!,
                    onPage: (page) {
                      _goPage(page);
                      setState(() => _showContents = false);
                    },
                    onHide: () => setState(() => _showContents = false),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PdfPasswordDialog extends StatefulWidget {
  const _PdfPasswordDialog();
  @override
  State<_PdfPasswordDialog> createState() => _PdfPasswordDialogState();
}

class _PdfPasswordDialogState extends State<_PdfPasswordDialog> {
  final input = TextEditingController();
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('PDF password'),
    content: TextField(
      controller: input,
      autofocus: true,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Document password'),
      onSubmitted: (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, input.text),
        child: const Text('Open PDF'),
      ),
    ],
  );
}

class DocumentReadError extends StatelessWidget {
  const DocumentReadError({super.key, required this.format});
  final String format;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ReaderToolIcon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(
            'Could not open this $format',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Try another copy of the file.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Back to library'),
          ),
        ],
      ),
    ),
  );
}
