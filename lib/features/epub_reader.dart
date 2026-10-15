import 'ebook_box_layout.dart';
import 'ebook_styles.dart';

import 'package:image/image.dart' as raster;

import 'book_paper.dart';
import 'book_viewport.dart';
import '../data/document_links.dart';

import 'package:html/dom.dart' as dom;

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
    this.onAnnotate,
    this.paperTexture = true,
  });
  final bool paperTexture;
  final bool annotationMode;
  final TextAnnotationDraft? insertText;
  final String? insertImage;
  final VoidCallback? onPlaced;
  final VoidCallback? onAnnotate;
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
  EpubDocumentData? _navigationDocument;
  final scroll = ScrollController();
  final bookPages = BookPageController();
  String displayMode = 'Single page';
  final _imageKeys = <String, GlobalKey>{};
  final _rasterAspects = <String, double?>{};
  final _rasterWidths = <String, double>{};

  Widget _rasterArtwork(
    EpubSection chapter,
    dom.Element element,
    int column,
    ({String path, Uint8List bytes}) resource,
  ) {
    // Reserve the full aspect-correct layout before Flutter decodes the image.
    // A zero-height loading image must not make a picture chapter look finished.
    final aspect = _rasterAspects.putIfAbsent(resource.path, () {
      try {
        final info = raster
            .findDecoderForData(resource.bytes)
            ?.startDecode(resource.bytes);
        if (info != null && info.width > 0) {
          _rasterWidths[resource.path] = info.width.toDouble();
        }
        return info != null && info.width > 0 && info.height > 0
            ? info.width / info.height
            : null;
      } catch (_) {
        return null;
      }
    });
    final artwork = Image.memory(
      resource.bytes,
      fit: BoxFit.contain,
      key: _imageKey(chapter, element, column),
      semanticLabel: element.attributes['alt'],
      errorBuilder: (_, error, stack) =>
          const Text('Image could not be displayed.'),
    );
    return aspect == null
        ? artwork
        : LayoutBuilder(
            builder: (context, bounds) {
              final styles = ebookStyle(element);
              final em =
                  widget.preferences.fontSize *
                  (double.tryParse(
                        element.attributes['data-book-size'] ?? '',
                      ) ??
                      1);
              final natural = _rasterWidths[resource.path] ?? bounds.maxWidth;
              final attributeWidth = element.attributes['width'];
              final widthValue =
                  styles['width'] ??
                  (attributeWidth == null ? null : '${attributeWidth}px');
              final heightValue =
                  styles['height'] ??
                  (element.attributes['height'] == null
                      ? null
                      : '${element.attributes['height']}px');
              final height = ebookLength(heightValue, em);
              final width = ebookLength(
                widthValue,
                em,
                fallback: height > 0 ? height * aspect : natural,
                percent: bounds.maxWidth,
              );
              final maximum = ebookLength(
                styles['max-width'],
                em,
                fallback: bounds.maxWidth,
                percent: bounds.maxWidth,
              );
              var fitted = width
                  .clamp(1.0, bounds.maxWidth.clamp(1.0, double.infinity))
                  .toDouble();
              fitted = fitted
                  .clamp(1.0, maximum.clamp(1.0, double.infinity))
                  .toDouble();
              if (bounds.maxHeight.isFinite) {
                fitted = fitted
                    .clamp(
                      1.0,
                      (bounds.maxHeight * aspect).clamp(1.0, double.infinity),
                    )
                    .toDouble();
              }
              return Align(
                alignment: Alignment.center,
                heightFactor: 1,
                child: SizedBox(
                  width: fitted,
                  height: fitted / aspect,
                  child: artwork,
                ),
              );
            },
          );
  }

  String get _modeKey => 'ebook.display.${widget.annotations.documentId}';
  GlobalKey? _imageKey(EpubSection chapter, dom.Element element, int column) {
    final id = element.id;
    return id.isEmpty
        ? null
        : _imageKeys.putIfAbsent('${chapter.path}:$id:$column', GlobalKey.new);
  }

  Future<void> showDisplayModes() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mode in ['Single page', 'Dual page', 'Continuous'])
              ListTile(
                title: Text(mode),
                selected: mode == displayMode,
                leading: Icon(
                  mode == 'Continuous'
                      ? Icons.view_day_outlined
                      : mode == 'Dual page'
                      ? Icons.menu_book_outlined
                      : Icons.article_outlined,
                ),
                onTap: () => Navigator.pop(sheet, mode),
              ),
          ],
        ),
      ),
    );
    if (selected == null || !mounted || selected == displayMode) {
      return;
    }
    final fraction = bookmarkFraction;
    bookPages.ready = false;
    setState(() => displayMode = selected);
    await widget.preferences.store?.setString(_modeKey, selected);
    if (!mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (displayMode == 'Continuous' && scroll.hasClients) {
        scroll.jumpTo(fraction * scroll.position.maxScrollExtent);
      } else {
        bookPages.restore(fraction);
      }
    });
  }

  void _bookPageChanged() {
    if (mounted) {
      // Page position changes repaint the existing chapter; only its footer
      // listens for UI updates. Rebuilding every paragraph here causes jank.
      _reportProgress();
    }
  }

  Future<void> _followLink(
    EpubDocumentData book,
    EpubSection source,
    String url,
  ) async {
    final uri = Uri.tryParse(url);
    if (uri != null && isExternalDocumentUrl(uri)) {
      final opened = await openDocumentUrl(uri);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')),
        );
      }
      return;
    }
    var navigationBook = book;
    var resolved = resolveEbookLink(book, source.path, url);
    // Footnote files can be packaged outside the EPUB reading spine.
    if (resolved == null &&
        uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority) {
      try {
        final path = epubResourcePath(source.path, url);
        final resource = book.resources[path];
        if (resource != null &&
            RegExp(
              r'\.(xhtml|html|htm)$',
              caseSensitive: false,
            ).hasMatch(path)) {
          final markup = utf8.decode(resource, allowMalformed: true);
          final title =
              html.parse(markup).querySelector('h1,h2,title')?.text.trim() ??
              'Linked section';
          navigationBook = EpubDocumentData(
            book.title,
            [...book.sections, EpubSection(path, title, markup)],
            book.resources,
            coverPath: book.coverPath,
          );
          if (mounted) {
            setState(() => _navigationDocument = navigationBook);
          }
          resolved = (
            section: navigationBook.sections.length - 1,
            fragment: Uri.decodeComponent(uri.fragment),
          );
        }
      } on FormatException {
        // The unavailable-target message below handles malformed references.
      }
    }
    final target = resolved;
    if (target == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This link target is unavailable.')),
        );
      }
      return;
    }
    showSection(target.section);
    if (target.fragment.isEmpty) {
      return;
    }
    final chapter = navigationBook.sections[target.section];
    final tree = html.parse(
      prepareSelectableMarkup(
        chapter.html,
        path: chapter.path,
        resources: navigationBook.resources,
      ),
    );
    final element = tree
        .querySelectorAll('[id], a[name]')
        .where(
          (element) =>
              element.id == target.fragment ||
              element.attributes['name'] == target.fragment,
        )
        .firstOrNull;
    dom.Element? block = element;
    while (block != null && !block.attributes.containsKey('data-qr-block')) {
      block = block.parent;
    }
    block ??= element?.querySelector('[data-qr-block]');
    block ??= element?.nextElementSibling;
    final id = block?.attributes['data-qr-block'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final key = id == null
          ? _imageKeys['${chapter.path}:${target.fragment}:0']
          : _searchKeys['${chapter.path}:$id:0'];
      final context = key?.currentContext;
      if (context == null) {
        return;
      }
      if (displayMode == 'Continuous') {
        Scrollable.ensureVisible(
          context,
          alignment: 0,
          duration: const Duration(milliseconds: 180),
        );
      } else {
        final render = context.findRenderObject();
        if (render != null) {
          bookPages.reveal(render);
        }
      }
    });
  }

  double _mediaHeight(double? pageHeight, TextStyle style) {
    if (pageHeight == null) {
      return double.infinity;
    }
    // Inline pictures inherit a line box around their placeholder. Reserve one
    // scaled line so its baseline/leading cannot crop the bottom of the artwork.
    final line =
        MediaQuery.textScalerOf(context).scale(style.fontSize ?? 20) *
        (style.height ?? 1);
    return (pageHeight - line - 2).clamp(1.0, double.infinity).toDouble();
  }

  final _markupLayouts = <String, Object>{};
  String _responsiveMarkup(
    EpubDocumentData book,
    EpubSection chapter,
    double width,
    TextStyle style,
    TextScaler scaler,
  ) {
    final layout = (width, style, scaler);
    if (_markupLayouts[chapter.path] != layout) {
      _markup[chapter.path] = prepareSelectableMarkup(
        chapter.html,
        path: chapter.path,
        resources: book.resources,
        availableWidth: width,
        readerStyle: style,
        textScaler: scaler,
        frameInk: (style.color ?? Colors.black)
            .toARGB32()
            .toRadixString(16)
            .padLeft(8, '0')
            .substring(2),
      );
      _markupLayouts[chapter.path] = layout;
    }
    return _markup[chapter.path]!;
  }

  Widget _chapterContent(
    EpubDocumentData book,
    EpubSection chapter,
    TextStyle bodyStyle,
    String ink,
    int column, {
    double? pageHeight,
  }) => LayoutBuilder(
    builder: (context, bounds) => Stack(
      children: [
        HtmlWidget(
          _responsiveMarkup(
            book,
            chapter,
            bounds.maxWidth,
            bodyStyle,
            MediaQuery.textScalerOf(context),
          ),
          key: ValueKey(chapter.path),
          // Page counts must use the complete, non-lazy chapter tree. The HTML
          // renderer otherwise switches long chapters to asynchronous building.
          buildAsync: displayMode == 'Continuous' ? null : false,
          renderMode: RenderMode.column,
          enableCaching: true,
          rebuildTriggers: [
            displayMode,
            pageHeight,
            MediaQuery.textScalerOf(context),
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
            ...ebookFrameTheme(element, ink),
            if (displayMode != 'Continuous' &&
                ['img', 'svg', 'image'].contains(element.localName))
              'max-height':
                  '${pageHeight == null ? MediaQuery.sizeOf(context).height * .7 : _mediaHeight(pageHeight, bodyStyle)}px',
          },
          customWidgetBuilder: (element) {
            final block = element.attributes['data-qr-block'];
            if (block != null) {
              final alignment = ebookAlignment(
                element,
                widget.preferences.alignment.textAlign,
              );
              _searchPrefixes['${chapter.path}:$block'] =
                  ebookLength(
                            ebookStyle(element)['text-indent'],
                            bodyStyle.fontSize ?? 20,
                          ) >
                          0 &&
                      alignment != TextAlign.center
                  ? 1
                  : 0;
              return AnnotatedParagraph(
                key: _searchKeys.putIfAbsent(
                  '${chapter.path}:$block:$column',
                  GlobalKey.new,
                ),
                searchQuery: _query,
                searchOffset:
                    _matches.isNotEmpty &&
                        _matches[_match].block == '${chapter.path}:$block'
                    ? _matches[_match].offset
                    : null,
                element: element,
                fallbackWidth:
                    double.tryParse(
                      element.attributes['data-book-cell-width'] ?? '',
                    ) ??
                    bounds.maxWidth,
                block: '${chapter.path}:$block',
                anchor: 'chapter:${section + 1}',
                store: widget.annotations,
                color: widget.color,
                activeTool: widget.activeTool,
                onAnnotate: widget.onAnnotate,
                gestureSession: gestures,
                style: bodyStyle,
                textAlign: widget.preferences.alignment.textAlign,
                onSelection: (action) => _selectionAction = action,
                onLink: (url) => _followLink(book, chapter, url),
              );
            }
            if (element.localName == 'svg') {
              try {
                return BookAtomic(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: _mediaHeight(pageHeight, bodyStyle),
                    ),
                    child: SvgPicture.string(
                      key: _imageKey(chapter, element, column),
                      epubSvgMarkup(book, chapter.path, element.outerHtml),
                      semanticsLabel: element.attributes['aria-label'],
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              } catch (_) {
                return const Text('Image could not be displayed.');
              }
            }
            if (!['img', 'image', 'object'].contains(element.localName)) {
              return null;
            }
            final source =
                element.attributes['src'] ??
                element.attributes['href'] ??
                element.attributes['xlink:href'] ??
                element.attributes['data'] ??
                '';
            final resource = epubImageResource(book, chapter.path, source);
            if (resource == null) {
              return Text(
                element.attributes['alt'] ?? 'Image is missing from this book.',
              );
            }
            if (resource.path.toLowerCase().endsWith('.svg')) {
              try {
                return BookAtomic(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: _mediaHeight(pageHeight, bodyStyle),
                    ),
                    child: SvgPicture.string(
                      key: _imageKey(chapter, element, column),
                      epubSvgMarkup(
                        book,
                        resource.path,
                        utf8.decode(resource.bytes),
                      ),
                      semanticsLabel: element.attributes['alt'],
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              } catch (_) {
                return const Text('Image could not be displayed.');
              }
            }
            return BookAtomic(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _mediaHeight(pageHeight, bodyStyle),
                ),
                child: _rasterArtwork(chapter, element, column, resource),
              ),
            );
          },
          onTapUrl: (url) async {
            await _followLink(book, chapter, url);
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
              font: widget.insertText?.font ?? 'sans-serif',
              fontSize: widget.insertText?.size ?? 24,
            ),
          ),
        ),
      ],
    ),
  );

  List<double> _sectionWeights = [];
  List<double> _sectionStarts = [];
  double _totalWeight = 0;
  @override
  void initState() {
    super.initState();
    scroll.addListener(_reportProgress);
    final savedMode = widget.preferences.store?.getString(_modeKey);
    if (['Single page', 'Dual page', 'Continuous'].contains(savedMode)) {
      displayMode = savedMode!;
    }
    bookPages.addListener(_bookPageChanged);
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
    if (!mounted || _sectionWeights.isEmpty) return;
    if (displayMode != 'Continuous') {
      if (section < _sectionWeights.length && _totalWeight > 0) {
        final within = ((bookPages.page + bookPages.columns) / bookPages.count)
            .clamp(0.0, 1.0);
        widget.onProgress?.call(
          (_sectionStarts[section] + within * _sectionWeights[section]) /
              _totalWeight,
        );
      }
      return;
    }
    if (!scroll.hasClients) {
      return;
    }
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
  bool _turningPage = false;
  int? _queuedPageDirection;
  Future<void> turnSection(int direction) async {
    if (_turningPage) {
      // Retain one follow-up intent, without accumulating a runaway turn queue.
      _queuedPageDirection = direction;
      return;
    }
    _turningPage = true;
    var nextDirection = direction;
    try {
      while (mounted) {
        _queuedPageDirection = null;
        await _turnSection(nextDirection);
        final queued = _queuedPageDirection;
        if (queued == null) {
          break;
        }
        nextDirection = queued;
      }
    } finally {
      _turningPage = false;
      _queuedPageDirection = null;
    }
  }

  Future<void> _turnSection(int direction) async {
    final book = _navigationDocument ?? await document;
    if (!mounted) return;
    if (displayMode != 'Continuous') {
      if (!bookPages.ready) {
        return;
      }
      final canTurn = direction > 0
          ? bookPages.page + bookPages.columns < bookPages.count
          : bookPages.page > 0;
      if (canTurn) {
        if (pageTurn.currentState != null) {
          await pageTurn.currentState!.turn(
            direction,
            () => bookPages.turn(direction),
          );
        } else {
          bookPages.turn(direction);
        }
        return;
      }
    }
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
          if (displayMode != 'Continuous') {
            bookPages.restore(1);
          }
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
  final _searchPrefixes = <String, int>{};
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
      final target = _searchKeys['${hit.block}:0']?.currentContext;
      if (target != null) {
        if (displayMode != 'Continuous') {
          final render = target.findRenderObject();
          if (render != null) {
            bookPages.reveal(
              render,
              textOffset: hit.offset + (_searchPrefixes[hit.block] ?? 0),
            );
          }
          return;
        }
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
      final book = _navigationDocument ?? await document;
      if (!mounted) return;
      final blocks = <({int chapter, String block, String text})>[];
      for (int chapter = 0; chapter < book.sections.length; chapter++) {
        final source = book.sections[chapter];
        for (final element
            in html
                .parse(
                  prepareSelectableMarkup(
                    source.html,
                    path: source.path,
                    resources: book.resources,
                  ),
                )
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

  double get bookmarkFraction => displayMode != 'Continuous'
      ? bookPages.fraction
      : scroll.hasClients && scroll.position.maxScrollExtent > 0
      ? (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1)
      : 0;
  void restoreBookmark(int chapter, double fraction) {
    showSection(chapter);
    if (displayMode != 'Continuous') {
      bookPages.restore(fraction);
      return;
    }
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
    bookPages.removeListener(_bookPageChanged);
    bookPages.dispose();
    scroll.dispose();
    super.dispose();
  }

  void showSection(int index) {
    bookPages.ready = false;
    setState(() => section = index);
    _selectionAction = null;
    bookPages.restore(0);
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
      final book = _navigationDocument ?? snapshot.data!;
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
                child: BookPaper(
                  paper: paper,
                  enabled: widget.paperTexture,
                  columns: displayMode == 'Dual page' ? 2 : 1,
                  child: displayMode != 'Continuous'
                      ? BookViewport(
                          key: ValueKey('$section-$displayMode'),
                          controller: bookPages,
                          columns: displayMode == 'Dual page' ? 2 : 1,
                          paper: paper,
                          layoutToken: (
                            section,
                            bodyStyle,
                            widget.preferences.alignment,
                            MediaQuery.textScalerOf(context),
                          ),
                          builder: (column, height) => _chapterContent(
                            book,
                            chapter,
                            bodyStyle,
                            ink,
                            column,
                            pageHeight: height,
                          ),
                        )
                      : Padding(
                          padding: EdgeInsets.only(
                            top: ebookPageInsets(
                              MediaQuery.sizeOf(context),
                              1,
                              MediaQuery.paddingOf(context),
                            ).top,
                            bottom: 64 + MediaQuery.paddingOf(context).bottom,
                          ),
                          child: SingleChildScrollView(
                            controller: scroll,
                            physics: widget.activeTool == MarkTool.browse
                                ? null
                                : const NeverScrollableScrollPhysics(),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 720,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    28,
                                    16,
                                    28,
                                    24,
                                  ),
                                  child: _chapterContent(
                                    book,
                                    chapter,
                                    bodyStyle,
                                    ink,
                                    0,
                                  ),
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
            top: 12,
            right: 72,
            child: PageNotesButton(
              store: widget.annotations,
              anchor: 'chapter:${section + 1}',
            ),
          ),
          if (!widget.annotationMode)
            Positioned.fill(
              child: ListenableBuilder(
                listenable: bookPages,
                builder: (context, _) => ReaderBottomBar(
                  pageInk: pageInk,
                  preferences: widget.preferences,
                  label: displayMode == 'Continuous'
                      ? '${section + 1} / ${book.sections.length}'
                      : !bookPages.ready
                      ? '${chapter.title} · …'
                      : '${chapter.title} · ${bookPages.page + 1}${bookPages.columns == 2 && bookPages.page + 1 < bookPages.count ? '–${bookPages.page + 2}' : ''} / ${bookPages.count}',
                  onPrevious: () => turnSection(-1),
                  onNext: () => turnSection(1),
                ),
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
