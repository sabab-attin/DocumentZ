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
import 'package:html/parser.dart' as html;

List<String> indexEpubText(List<String> chapters) => chapters.map((chapter) => html.parse(chapter).body?.text ?? '').toList();

class EpubReader extends StatefulWidget {
  const EpubReader({super.key, required this.bytes, required this.preferences, required this.annotations, this.onSectionChanged, this.color, this.parsedDocument,
    this.activeTool = MarkTool.browse});
  final MarkTool activeTool;
  final Future<EpubDocumentData>? parsedDocument;
  final int? color;
  final Future<Uint8List> bytes;
  final ReaderPreferences preferences;
  final AnnotationStore annotations;
  final ValueChanged<int>? onSectionChanged;
  @override
  State<EpubReader> createState() => EpubReaderState();
}

class EpubReaderState extends State<EpubReader> {
  late final Future<EpubDocumentData> document = widget.parsedDocument ?? widget.bytes.then((bytes) => compute(parseEpub, bytes));
  final scroll = ScrollController();
  final gestures = ReaderGestureSession();
  final _standaloneControls = ValueNotifier<bool>(true);
  final pageTurn = GlobalKey<PageTurnState>();
  Future<void> turnSection(int direction) async {
    final book = await document;
    if (!mounted) return;
    if (scroll.hasClients) {
      final position = scroll.position;
      final offset = (scroll.offset + direction * position.viewportDimension).clamp(0.0, position.maxScrollExtent);
      if ((offset - scroll.offset).abs() > 1) {
        await pageTurn.currentState?.turn(direction, () => scroll.jumpTo(offset));
        return;
      }
    }
    final next = (section + direction).clamp(0, book.sections.length - 1);
    if (next != section) {
      await pageTurn.currentState?.turn(direction, () {
        showSection(next);
        if (direction < 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scroll.hasClients) scroll.jumpTo(scroll.position.maxScrollExtent);
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
  late final Future<List<String>> searchIndex = document.then((book) => compute(indexEpubText, book.sections.map((s) => s.html).toList()));

  Future<void> searchDocument() async {
    final input = TextEditingController();
    try {
      final book = await document;
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(child: SizedBox(height: MediaQuery.sizeOf(context).height * .75,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(16), child: TextField(controller: input, autofocus: true,
              decoration: const InputDecoration(labelText: 'Search document', prefixIcon: Icon(Icons.search)), onChanged: (_) => update(() {}))),
            Expanded(child: FutureBuilder<List<String>>(future: searchIndex, builder: (context, snapshot) {
              if (snapshot.hasError) return const Center(child: Text('Could not search this EPUB.'));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              final query = input.text.trim().toLowerCase();
              if (query.isEmpty) return const Center(child: Text('Enter a keyword'));
              final matches = <(int, int)>[];
              for (int c = 0; c < snapshot.data!.length; c++) {
                final text = snapshot.data![c].toLowerCase();
                int start = 0;
                while ((start = text.indexOf(query, start)) >= 0) { matches.add((c, start)); start += query.length; }
              }
              return matches.isEmpty ? const Center(child: Text('No matches')) : ListView.builder(itemCount: matches.length, itemBuilder: (context, i) {
                final (chapter, offset) = matches[i];
                final text = snapshot.data![chapter];
                return ListTile(title: Text(book.sections[chapter].title), subtitle: Text(text.substring((offset - 40).clamp(0, text.length),
                  (offset + query.length + 80).clamp(0, text.length)).replaceAll(RegExp(r'\s+'), ' ')), onTap: () {
                    Navigator.pop(context); showSection(chapter);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && scroll.hasClients) scroll.jumpTo((offset / text.length) * scroll.position.maxScrollExtent);
                    });
                  });
              });
            })),
          ])))));
    } finally { input.dispose(); }
  }
  double get bookmarkFraction => scroll.hasClients && scroll.position.maxScrollExtent > 0
    ? (scroll.offset / scroll.position.maxScrollExtent).clamp(0, 1) : 0;
  void restoreBookmark(int chapter, double fraction) {
    showSection(chapter);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) scroll.jumpTo(fraction.clamp(0, 1) * scroll.position.maxScrollExtent);
    });
  }
  Future<void> annotateSelection(MarkTool kind) async {
    if (_selectionAction == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select text first.')));
      return;
    }
    await _selectionAction!(kind);
  }
  @override
  void dispose() { _standaloneControls.dispose(); gestures.dispose(); scroll.dispose(); super.dispose(); }

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
        return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(
          widget.parsedDocument == null ? 'Could not open this EPUB. It may be damaged or DRM-protected. Try another copy.'
            : 'Could not read this document. It may be damaged, encrypted, or too large. Try Windows PDF conversion.', textAlign: TextAlign.center)));
      }
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(semanticsLabel: 'Opening EPUB'));
      final book = snapshot.data!;
      final chapter = book.sections[section];
      final pageInk = widget.preferences.pageDark ? Colors.white : widget.preferences.theme.ink;
      final ink = pageInk.toARGB32().toRadixString(16).padLeft(8, '0').substring(2);
      final paper = widget.preferences.pageDark ? Colors.black : widget.preferences.theme.background;
      final bodyStyle = TextStyle(fontSize: widget.preferences.fontSize, height: 1.65, color: pageInk,
        fontFamily: widget.parsedDocument == null ? 'serif' : null);
      return Stack(children: [
        Positioned.fill(child: PageTurn(key: pageTurn, paper: paper, child: ReaderGestureSurface(session: gestures, active: widget.activeTool != MarkTool.browse,
          onSwipe: turnSection, onNavigate: (delta, focal, scale) {
            if (scroll.hasClients) scroll.jumpTo((scroll.offset - delta.dy).clamp(0, scroll.position.maxScrollExtent));
          }, child: ColoredBox(color: widget.preferences.pageDark ? Colors.black : widget.preferences.theme.background,
          child: SingleChildScrollView(controller: scroll,
            physics: widget.activeTool == MarkTool.browse ? null : const NeverScrollableScrollPhysics(),
          child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(padding: const EdgeInsets.fromLTRB(28, 40, 28, 80),
          child: HtmlWidget(_markup.putIfAbsent(chapter.path, () => prepareSelectableMarkup(chapter.html)),
            key: ValueKey(chapter.path),
            rebuildTriggers: [widget.preferences.alignment, widget.activeTool, widget.color],
            textStyle: bodyStyle,
            customStylesBuilder: (element) => {'color': '#$ink', 'background-color': 'transparent',
              if (['p', 'div', 'li', 'td', 'th', 'blockquote'].contains(element.localName))
                'text-align': widget.preferences.alignment == ReadingAlignment.center ? 'center' : widget.preferences.alignment.name},
            customWidgetBuilder: (element) {
              final block = element.attributes['data-qr-block'];
              if (block != null) {
                return AnnotatedParagraph(
                key: ValueKey('${chapter.path}:$block'), element: element, block: '${chapter.path}:$block',
                anchor: 'chapter:${section + 1}', store: widget.annotations,
                color: widget.color,
                  activeTool: widget.activeTool, gestureSession: gestures,
                style: bodyStyle, textAlign: widget.preferences.alignment.textAlign,
                onSelection: (action) => _selectionAction = action,
                onLink: (url) {
                  final index = book.sections.indexWhere((item) => item.path == epubResourcePath(chapter.path, url));
                  if (index >= 0) showSection(index);
                },
                );
              }
              if (element.localName == 'svg') {
                try {
                  return SvgPicture.string(epubSvgMarkup(book, chapter.path, element.outerHtml),
                    semanticsLabel: element.attributes['aria-label'], fit: BoxFit.contain);
                } catch (_) { return const Text('Image could not be displayed.'); }
              }
              if (!['img', 'image', 'object'].contains(element.localName)) return null;
              final source = element.attributes['src'] ?? element.attributes['href'] ?? element.attributes['xlink:href'] ?? element.attributes['data'] ?? '';
              final resource = epubImageResource(book, chapter.path, source);
              if (resource == null) return Text(element.attributes['alt'] ?? 'Image is missing from this book.');
              if (resource.path.toLowerCase().endsWith('.svg')) {
                try {
                  return SvgPicture.string(epubSvgMarkup(book, resource.path, utf8.decode(resource.bytes)),
                    semanticsLabel: element.attributes['alt'], fit: BoxFit.contain);
                } catch (_) { return const Text('Image could not be displayed.'); }
              }
              return Image.memory(resource.bytes, semanticLabel: element.attributes['alt'],
                errorBuilder: (_, error, stack) => const Text('Image could not be displayed.'));
            },
            onTapUrl: (url) {
              final path = epubResourcePath(chapter.path, url);
              final index = book.sections.indexWhere((item) => item.path == path);
              if (index >= 0) showSection(index);
              return true;
            },
          ),
        )))))))),
        Positioned(top: 56, left: 0, right: 0, child: ValueListenableBuilder<bool>(
          valueListenable: ReaderControlsScope.of(context) ?? _standaloneControls,
          builder: (context, open, _) => open ? Material(elevation: 4, child: Row(children: [
          IconButton(tooltip: 'Previous page', onPressed: () => turnSection(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(child: Text('${section + 1} / ${book.sections.length} · ${chapter.title}', maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center)),
          IconButton(tooltip: _showContents ? 'Hide contents' : 'Table of contents', icon: const Icon(Icons.list), onPressed: toggleContents),
          IconButton(tooltip: 'Next page', onPressed: () => turnSection(1), icon: const Icon(Icons.chevron_right)),
        ])          ) : const SizedBox.shrink())),if (_showContents) Positioned(top: 112, left: 0, right: 0, child: Material(elevation: 8, child: SizedBox(height: MediaQuery.sizeOf(context).height * .26, child: Column(children: [
          ListTile(title: const Text('Table of contents'), trailing: IconButton(tooltip: 'Hide contents',
            onPressed: toggleContents, icon: const Icon(Icons.close))),
          Expanded(child: ListView.builder(itemCount: book.sections.length, itemBuilder: (context, index) => ListTile(
            title: Text(book.sections[index].title), selected: index == section,
            onTap: () { showSection(index); setState(() => _showContents = false); }))),
        ] )))), 
      ]);
    },
  );
}

