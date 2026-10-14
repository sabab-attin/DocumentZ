import 'text_controller_owner.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'dart:convert';

import '../data/epub_document.dart';
import '../core/preferences.dart';
import 'annotations.dart';
import 'annotated_paragraph.dart';
import 'reader_gestures.dart';
import 'reader_controls.dart';
import 'page_turn.dart';
import 'find_match_bar.dart';

import 'package:html/parser.dart' as html;

List<String> indexEpubText(List<String> chapters) =>
    chapters.map((chapter) => html.parse(chapter).body?.text ?? '').toList();

class EpubReader extends StatefulWidget {
  const EpubReader({
    super.key,
    required this.bytes,
    required this.preferences,
    required this.annotations,
    this.onSectionChanged,
    this.onProgress,
    this.color,
    this.parsedDocument,
    this.activeTool = MarkTool.browse,
    this.annotationMode = false,
    this.insertText,
    this.insertImage,
    this.onPlaced,
  });
  final bool annotationMode;
  final TextAnnotationDraft? insertText;
  final String? insertImage;
  final VoidCallback? onPlaced;
  final MarkTool activeTool;
  final Future<EpubDocumentData>? parsedDocument;
  final int? color;
  final Future<Uint8List> bytes;
  final ReaderPreferences preferences;
  final AnnotationStore annotations;
  final ValueChanged<int>? onSectionChanged;
  final ValueChanged<double>? onProgress;
  @override
  State<EpubReader> createState() => EpubReaderState();
}

class EpubReaderState extends State<EpubReader> {
  late final Future<EpubDocumentData> document =
      widget.parsedDocument ??
      widget.bytes.then((bytes) => compute(parseEpub, bytes));
  final scroll = ScrollController();
  List<double> _sectionWeights = [];
  List<double> _sectionStarts = [];
  double _totalWeight = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(_reportProgress);
    searchIndex.then((texts) {
      if (!mounted) return;
      _sectionWeights = texts
          .map((text) => text.isEmpty ? 1.0 : text.length.toDouble())
          .toList();
      _totalWeight = 0;
      _sectionStarts = [];
      for (final weight in _sectionWeights) {
        _sectionStarts.add(_totalWeight);
        _totalWeight += weight;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportProgress());
    }, onError: (Object error, StackTrace stack) {});
  }

  void _reportProgress() {
    if (!mounted || !scroll.hasClients || _sectionWeights.isEmpty) return;
    final position = scroll.position;
    if (!position.hasContentDimensions || section >= _sectionWeights.length) {
      return;
    }
    final extent = position.maxScrollExtent + position.viewportDimension;
    final within = extent > 0
        ? ((position.pixels + position.viewportDimension) / extent).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    final before = _sectionStarts[section];
    final total = _totalWeight;
    widget.onProgress?.call(
      (before + within * _sectionWeights[section]) / total,
    );
  }

  final gestures = ReaderGestureSession();

  final pageTurn = GlobalKey<PageTurnState>();
  Future<void> turnSection(int direction) async {
    final book = await document;
    if (!mounted) return;
    if (scroll.hasClients) {
      final position = scroll.position;
      final offset = (scroll.offset + direction * position.viewportDimension)
          .clamp(0.0, position.maxScrollExtent);
      if ((offset - scroll.offset).abs() > 1) {
        await pageTurn.currentState?.turn(
          direction,
          () => scroll.jumpTo(offset),
        );
        return;
      }
    }
    final next = (section + direction).clamp(0, book.sections.length - 1);
    if (next != section) {
      await pageTurn.currentState?.turn(direction, () {
        showSection(next);
        if (direction < 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients) {
              scroll.jumpTo(scroll.position.maxScrollExtent);
            }
          });
        }
      });
    }
  }

  int section = 0;
  bool _showContents = false;
  void toggleContents() => setState(() => _showContents = !_showContents);
  Future<void> Function(MarkTool)? _selectionAction;
  final Map<String, String> _markup = {};
  late final Future<List<String>> searchIndex = document.then(
    (book) => compute(indexEpubText, book.sections.map((s) => s.html).toList()),
  );

  final _searchKeys = <String, GlobalKey>{};
  List<({int chapter, String block, int offset, String snippet})> _matches = [];
  int _match = 0;
  String _query = '';
  Future<void> showTextSize() => showReaderZoom(
    context,
    current: widget.preferences.fontSize / 20,
    title: 'Text size',
    percentages: const [80, 90, 100, 110, 120, 140, 160],
    onZoom: (zoom) => widget.preferences.setFontSize(20 * zoom),
    onBestFit: () => widget.preferences.setFontSize(20),
  );
  void _goMatch(int index) {
    if (_matches.isEmpty) return;
    final selected = index.clamp(0, _matches.length - 1);
    final hit = _matches[selected];
    setState(() => _match = selected);
    showSection(hit.chapter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _searchKeys[hit.block]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: .25,
          duration: const Duration(milliseconds: 220),
        );
      }
    });
  }

  Future<void> searchDocument() async {
    final input = TextEditingController(text: _query);
    bool inputOwnedByRoute = false;
    try {
      final book = await document;
      if (!mounted) return;
      final blocks = <({int chapter, String block, String text})>[];
      for (int chapter = 0; chapter < book.sections.length; chapter++) {
        final source = book.sections[chapter];
        for (final element
            in html
                .parse(prepareSelectableMarkup(source.html))
                .querySelectorAll('[data-qr-block]')) {
          blocks.add((
            chapter: chapter,
            block: '${source.path}:${element.attributes['data-qr-block']!}',
            text: paragraphRuns(element).map((run) => run.text).join(),
          ));
        }
      }
      List<({int chapter, String block, int offset, String snippet})> results =
          [];
      void search() {
        results = [];
        final query = input.text.trim().toLowerCase();
        if (query.isEmpty) return;
        for (final block in blocks) {
          final text = block.text.toLowerCase();
          int offset = 0;
          while ((offset = text.indexOf(query, offset)) >= 0) {
            results.add((
              chapter: block.chapter,
              block: block.block,
              offset: offset,
              snippet: block.text.substring(
                (offset - 40).clamp(0, text.length),
                (offset + query.length + 80).clamp(0, text.length),
              ),
            ));
            offset += query.length;
          }
        }
      }

      search();
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) {
          inputOwnedByRoute = true;
          return TextControllerOwner(
            controller: input,
            child: StatefulBuilder(
              builder: (sheet, update) => SafeArea(
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheet).height * .8,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          controller: input,
                          autofocus: true,
                          decoration: const InputDecoration(
                            labelText: 'Find in document',
                            prefixIcon: Icon(Icons.search),
                          ),
                          onChanged: (_) => update(search),
                        ),
                      ),
                      Text('${results.length} matches'),
                      Expanded(
                        child: results.isEmpty
                            ? Center(
                                child: Text(
                                  input.text.trim().isEmpty
                                      ? 'Enter a keyword'
                                      : 'No matches',
                                ),
                              )
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (sheet, i) => ListTile(
                                  title: Text(
                                    book.sections[results[i].chapter].title,
                                  ),
                                  subtitle: Text(results[i].snippet),
                                  onTap: () {
                                    setState(() {
                                      _query = input.text.trim();
                                      _matches = List.of(results);
                                      _match = i;
                                    });
                                    Navigator.pop(sheet);
                                    _goMatch(i);
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    } finally {
      if (!inputOwnedByRoute) input.dispose();
    }
  }

  double get bookmarkFraction =>
      scroll.hasClients && scroll.position.maxScrollExtent > 0
      ? (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1)
      : 0;
  void restoreBookmark(int chapter, double fraction) {
    showSection(chapter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.jumpTo(fraction.clamp(0, 1) * scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> annotateSelection(MarkTool kind) async {
    if (_selectionAction == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Select text first.')));
      return;
    }
    await _selectionAction!(kind);
  }

  @override
  void dispose() {
    gestures.dispose();
    scroll.dispose();
    super.dispose();
  }

  void showSection(int index) {
    setState(() => section = index);
    _selectionAction = null;
    widget.onSectionChanged?.call(index);
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<EpubDocumentData>(
    future: document,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.parsedDocument == null
                  ? 'Could not open this EPUB. It may be damaged or DRM-protected. Try another copy.'
                  : 'Could not read this document. It may be damaged, encrypted, or too large. Try Windows PDF conversion.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (!snapshot.hasData) {
        return const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Opening EPUB'),
        );
      }
      final book = snapshot.data!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportProgress());
      final chapter = book.sections[section];
      final pageInk = widget.preferences.pageDark
          ? Colors.white
          : widget.preferences.theme.brightness == Brightness.dark
          ? const Color(0xff202020)
          : widget.preferences.theme.ink;
      final ink = pageInk
          .toARGB32()
          .toRadixString(16)
          .padLeft(8, '0')
          .substring(2);
      final paper = widget.preferences.pageDark
          ? Colors.black
          : widget.preferences.theme.brightness == Brightness.dark
          ? Colors.white
          : widget.preferences.theme.background;
      final bodyStyle = TextStyle(
        fontSize:
            widget.preferences.fontSize *
            (widget.preferences.viewingFit == 'custom'
                ? widget.preferences.viewingZoom
                : 1),
        height: 1.65,
        color: pageInk,
        fontFamily: widget.preferences.fontFamily,
        fontFamilyFallback: const ['Tinos'],
      );
      return Stack(
        children: [
          Positioned.fill(
            child: PageTurn(
              key: pageTurn,
              paper: paper,
              child: ReaderGestureSurface(
                session: gestures,
                active: widget.activeTool != MarkTool.browse,
                onSwipe: turnSection,
                onNavigate: (delta, focal, scale) {
                  if (scroll.hasClients) {
                    scroll.jumpTo(
                      (scroll.offset - delta.dy).clamp(
                        0,
                        scroll.position.maxScrollExtent,
                      ),
                    );
                  }
                },
                child: ColoredBox(
                  color: widget.preferences.pageDark ? Colors.black : paper,
                  child: SingleChildScrollView(
                    controller: scroll,
                    physics: widget.activeTool == MarkTool.browse
                        ? null
                        : const NeverScrollableScrollPhysics(),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 720),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(28, 40, 28, 80),
                          child: Stack(
                            children: [
                              HtmlWidget(
                                _markup.putIfAbsent(
                                  chapter.path,
                                  () => prepareSelectableMarkup(chapter.html),
                                ),
                                key: ValueKey(chapter.path),
                                rebuildTriggers: [
                                  widget.preferences.alignment,
                                  widget.activeTool,
                                  widget.color,
                                  _query,
                                  _match,
                                ],
                                textStyle: bodyStyle,
                                customStylesBuilder: (element) => {
                                  'font-family': widget.preferences.fontFamily,
                                  'color': '#$ink',
                                  'background-color': 'transparent',
                                  if ([
                                    'p',
                                    'div',
                                    'li',
                                    'td',
                                    'th',
                                    'blockquote',
                                  ].contains(element.localName))
                                    'text-align':
                                        widget.preferences.alignment ==
                                            ReadingAlignment.center
                                        ? 'center'
                                        : widget.preferences.alignment.name,
                                },
                                customWidgetBuilder: (element) {
                                  final block =
                                      element.attributes['data-qr-block'];
                                  if (block != null) {
                                    return AnnotatedParagraph(
                                      key: _searchKeys.putIfAbsent(
                                        '${chapter.path}:$block',
                                        GlobalKey.new,
                                      ),
                                      searchQuery: _query,
                                      searchOffset:
                                          _matches.isNotEmpty &&
                                              _matches[_match].block ==
                                                  '${chapter.path}:$block'
                                          ? _matches[_match].offset
                                          : null,
                                      element: element,
                                      block: '${chapter.path}:$block',
                                      anchor: 'chapter:${section + 1}',
                                      store: widget.annotations,
                                      color: widget.color,
                                      activeTool: widget.activeTool,
                                      gestureSession: gestures,
                                      style: bodyStyle,
                                      textAlign: widget
                                          .preferences
                                          .alignment
                                          .textAlign,
                                      onSelection: (action) =>
                                          _selectionAction = action,
                                      onLink: (url) {
                                        final index = book.sections.indexWhere(
                                          (item) =>
                                              item.path ==
                                              epubResourcePath(
                                                chapter.path,
                                                url,
                                              ),
                                        );
                                        if (index >= 0) showSection(index);
                                      },
                                    );
                                  }
                                  if (element.localName == 'svg') {
                                    try {
                                      return SvgPicture.string(
                                        epubSvgMarkup(
                                          book,
                                          chapter.path,
                                          element.outerHtml,
                                        ),
                                        semanticsLabel:
                                            element.attributes['aria-label'],
                                        fit: BoxFit.contain,
                                      );
                                    } catch (_) {
                                      return const Text(
                                        'Image could not be displayed.',
                                      );
                                    }
                                  }
                                  if (![
                                    'img',
                                    'image',
                                    'object',
                                  ].contains(element.localName)) {
                                    return null;
                                  }
                                  final source =
                                      element.attributes['src'] ??
                                      element.attributes['href'] ??
                                      element.attributes['xlink:href'] ??
                                      element.attributes['data'] ??
                                      '';
                                  final resource = epubImageResource(
                                    book,
                                    chapter.path,
                                    source,
                                  );
                                  if (resource == null) {
                                    return Text(
                                      element.attributes['alt'] ??
                                          'Image is missing from this book.',
                                    );
                                  }
                                  if (resource.path.toLowerCase().endsWith(
                                    '.svg',
                                  )) {
                                    try {
                                      return SvgPicture.string(
                                        epubSvgMarkup(
                                          book,
                                          resource.path,
                                          utf8.decode(resource.bytes),
                                        ),
                                        semanticsLabel:
                                            element.attributes['alt'],
                                        fit: BoxFit.contain,
                                      );
                                    } catch (_) {
                                      return const Text(
                                        'Image could not be displayed.',
                                      );
                                    }
                                  }
                                  return Image.memory(
                                    resource.bytes,
                                    semanticLabel: element.attributes['alt'],
                                    errorBuilder: (_, error, stack) =>
                                        const Text(
                                          'Image could not be displayed.',
                                        ),
                                  );
                                },
                                onTapUrl: (url) {
                                  final path = epubResourcePath(
                                    chapter.path,
                                    url,
                                  );
                                  final index = book.sections.indexWhere(
                                    (item) => item.path == path,
                                  );
                                  if (index >= 0) showSection(index);
                                  return true;
                                },
                              ),
                              Positioned.fill(
                                child: ListenableBuilder(
                                  listenable: widget.annotations,
                                  builder: (context, _) => PageMarks(
                                    store: widget.annotations,
                                    anchor: 'chapter:${section + 1}',
                                    tool:
                                        [
                                          MarkTool.highlight,
                                          MarkTool.underline,
                                          MarkTool.strikethrough,
                                          MarkTool.note,
                                        ].contains(widget.activeTool)
                                        ? MarkTool.browse
                                        : widget.activeTool,
                                    dark: widget.preferences.pageDark,
                                    onTouched: () {},
                                    annotationMode: widget.annotationMode,
                                    gestureSession: gestures,
                                    color: widget.color,
                                    insertText: widget.insertText?.text ?? '',
                                    insertImage: widget.insertImage,
                                    onPlaced: widget.onPlaced,
                                    font:
                                        widget.insertText?.font ?? 'sans-serif',
                                    fontSize: widget.insertText?.size ?? 24,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 64,
            right: 12,
            child: PageNotesButton(
              store: widget.annotations,
              anchor: 'chapter:${section + 1}',
            ),
          ),
          if (!widget.annotationMode)
            Positioned.fill(
              child: ReaderBottomBar(
                preferences: widget.preferences,
                label: '${section + 1} / ${book.sections.length}',
                onPrevious: () => turnSection(-1),
                onNext: () => turnSection(1),
              ),
            ),
          if (_matches.isNotEmpty)
            Positioned(
              left: 12,
              right: 12,
              bottom: 72,
              child: FindMatchBar(
                current: _match,
                count: _matches.length,
                query: _query,
                onPrevious: () => _goMatch(_match - 1),
                onNext: () => _goMatch(_match + 1),
                onClose: () => setState(() {
                  _matches = [];
                  _query = '';
                }),
              ),
            ),
          if (_showContents)
            Positioned(
              top: 112,
              left: 0,
              right: 0,
              child: Material(
                elevation: 8,
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * .26,
                  child: Column(
                    children: [
                      ListTile(
                        title: const Text('Table of contents'),
                        trailing: IconButton(
                          tooltip: 'Hide contents',
                          onPressed: toggleContents,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: book.sections.length,
                          itemBuilder: (context, index) => ListTile(
                            title: Text(book.sections[index].title),
                            selected: index == section,
                            onTap: () {
                              showSection(index);
                              setState(() => _showContents = false);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
