import '../core/desktop_platform.dart';
import 'ebook_box_layout.dart';

import 'dart:typed_data';

import 'ebook_styles.dart';
import 'continuous_marks.dart';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'annotations.dart';
import 'reader_gestures.dart';
import 'selection_panel.dart';

const _blocks = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,td,th,div';

/// Stable IDs tie EPUB ranges to source paragraphs rather than screen coordinates.
String prepareSelectableMarkup(
  String source, {
  String path = '',
  Map<String, Uint8List> resources = const {},
  double? availableWidth,
  String? frameInk,
  TextStyle readerStyle = const TextStyle(fontSize: 20),
  TextScaler textScaler = TextScaler.noScaling,
}) {
  final document = html.parse(source);
  final blocks = document.querySelectorAll(_blocks);
  for (int index = 0; index < blocks.length; index++) {
    final element = blocks[index];
    // Leave image-containing layouts to the HTML renderer so artwork stays intact.
    if (element.querySelector(_blocks) != null ||
        element.querySelector('img,image,svg') != null ||
        element.text.trim().isEmpty) {
      continue;
    }
    element.attributes['data-qr-block'] = '$index';
  }
  applyEbookStyles(document, path, resources);
  prepareEbookBoxes(
    document,
    availableWidth: availableWidth,
    style: readerStyle,
    textScaler: textScaler,
  );
  document.body?.attributes['data-book-root'] = '1';
  if (frameInk != null) {
    applyPreparedFrameTheme(document, frameInk);
  }
  final body = document.body;
  if (body == null) {
    return source;
  }
  final wrapper = dom.Element.tag('div')..attributes.addAll(body.attributes);
  wrapper.attributes['data-book-root'] = '1';
  wrapper.nodes.addAll(body.nodes.toList());
  return wrapper.outerHtml;
}

class ParagraphRun {
  const ParagraphRun(this.text, this.style, this.link);
  final String text;
  final TextStyle style;
  final String? link;
}

List<ParagraphRun> paragraphRuns(
  dom.Element element, [
  TextStyle baseStyle = const TextStyle(fontSize: 20),
]) {
  final runs = <ParagraphRun>[];
  void visit(dom.Node node, TextStyle style, String? link) {
    if (node is dom.Text) {
      final whitespace = ebookStyle(node.parent ?? element)['white-space'];
      final text =
          element.localName == 'pre' ||
              whitespace == 'pre' ||
              whitespace == 'pre-wrap' ||
              whitespace == 'break-spaces'
          ? node.data
          : whitespace == 'pre-line'
          ? node.data.replaceAll(RegExp(r'[ \t\f]+'), ' ')
          : node.data.replaceAll(RegExp(r'[ \t\r\n\f]+'), ' ');
      if (text.isNotEmpty) runs.add(ParagraphRun(text, style, link));
    } else if (node is dom.Element) {
      if (node.localName == 'br') {
        runs.add(ParagraphRun('\n', style, link));
        return;
      }
      var next = style;
      if (['b', 'strong'].contains(node.localName)) {
        next = next.copyWith(fontWeight: FontWeight.bold);
      }
      if (['i', 'em'].contains(node.localName)) {
        next = next.copyWith(fontStyle: FontStyle.italic);
      }
      if (['code', 'pre'].contains(node.localName)) {
        next = next.copyWith(fontFamily: 'monospace');
      }
      if (node.localName == 'a') {
        next = next.copyWith(decoration: TextDecoration.underline);
      }
      next = next.merge(ebookTextStyle(node, baseStyle));
      for (final child in node.nodes) {
        visit(child, next, node.attributes['href'] ?? link);
      }
    }
  }

  visit(element, const TextStyle(), null);
  return runs;
}

/// Splits at source-style and annotation boundaries, preserving overlapping marks.
List<TextSpan> markedParagraphSpans(
  List<ParagraphRun> runs,
  List<DocumentMark> marks, {
  Map<String, GestureRecognizer> recognizers = const {},
  Map<String, GestureRecognizer> noteRecognizers = const {},
  bool paintAnnotations = true,
}) {
  final text = runs.map((r) => r.text).join();
  final edges = <int>{0, text.length};
  int offset = 0;
  for (final run in runs) {
    offset += run.text.length;
    edges.add(offset);
  }
  for (final mark in marks) {
    if (mark.start < 0 || mark.end > text.length || mark.start >= mark.end) {
      continue;
    }
    // If the publisher content changed, do not decorate unrelated characters.
    if (mark.quote.isNotEmpty &&
        text.substring(mark.start, mark.end) != mark.quote) {
      continue;
    }
    edges.add(mark.start);
    edges.add(mark.end);
  }
  final sorted = edges.toList()..sort();
  final spans = <TextSpan>[];
  for (int i = 0; i + 1 < sorted.length; i++) {
    final start = sorted[i], end = sorted[i + 1];
    if (start == end) continue;
    int runStart = 0;
    final run = runs.firstWhere((r) {
      final found = start >= runStart && start < runStart + r.text.length;
      runStart += r.text.length;
      return found;
    });
    final applied = marks
        .where(
          (m) =>
              m.start <= start &&
              m.end >= end &&
              m.start >= 0 &&
              m.end <= text.length &&
              (m.quote.isEmpty || text.substring(m.start, m.end) == m.quote),
        )
        .toList();
    var style = run.style;
    final decorations = <TextDecoration>[
      if (style.decoration != null) style.decoration!,
    ];
    if (applied.any(
      (m) => m.tool == MarkTool.highlight || m.tool == MarkTool.note,
    )) {
      final highlight = applied.lastWhere(
        (m) => m.tool == MarkTool.highlight || m.tool == MarkTool.note,
      );
      final color = Color(highlight.color ?? 0xffffe082);
      style = style.copyWith(
        backgroundColor: paintAnnotations ? color : null,
        color: color.computeLuminance() < .35
            ? Colors.white
            : const Color(0xff202020),
      );
    }
    if (paintAnnotations &&
        applied.any(
          (m) => m.tool == MarkTool.underline || m.tool == MarkTool.note,
        )) {
      decorations.add(TextDecoration.underline);
    }
    if (paintAnnotations &&
        applied.any((m) => m.tool == MarkTool.strikethrough)) {
      decorations.add(TextDecoration.lineThrough);
    }
    if (decorations.isNotEmpty) {
      final colored = applied.where(
        (m) =>
            m.color != null &&
            [
              MarkTool.underline,
              MarkTool.strikethrough,
              MarkTool.note,
            ].contains(m.tool),
      );
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: colored.isEmpty ? null : Color(colored.last.color!),
      );
    }
    spans.add(
      TextSpan(
        text: text.substring(start, end),
        style: style,
        recognizer: applied.where((m) => m.tool == MarkTool.note).isEmpty
            ? recognizers[run.link]
            : noteRecognizers[applied
                      .lastWhere((m) => m.tool == MarkTool.note)
                      .id] ??
                  recognizers[run.link],
      ),
    );
  }
  return spans;
}

class AnnotatedParagraph extends StatefulWidget {
  const AnnotatedParagraph({
    super.key,
    required this.element,
    required this.block,
    required this.anchor,
    required this.store,
    required this.style,
    required this.onSelection,
    required this.onLink,
    this.onAnnotate,
    this.color,
    this.activeTool = MarkTool.browse,
    this.searchQuery = '',
    this.searchOffset,
    this.gestureSession,
    this.textAlign = TextAlign.start,
    this.fallbackWidth,
  });
  final String searchQuery;
  final int? searchOffset;
  final TextAlign textAlign;
  final double? fallbackWidth;
  final MarkTool activeTool;
  final ReaderGestureSession? gestureSession;
  final int? color;
  final dom.Element element;
  final String block, anchor;
  final AnnotationStore store;
  final TextStyle style;
  final ValueChanged<Future<void> Function(MarkTool)> onSelection;
  final ValueChanged<String> onLink;
  final VoidCallback? onAnnotate;
  @override
  State<AnnotatedParagraph> createState() => _AnnotatedParagraphState();
}

class _AnnotatedParagraphState extends State<AnnotatedParagraph> {
  late List<ParagraphRun> runs;
  final _selectionPreview = ValueNotifier(
    const TextSelection.collapsed(offset: -1),
  );
  TextPainter? _cachedPainter;
  Object? _cachedLayout;
  void _updateSelection(TextSelection value) {
    selection = value;
    if (isWindowsDesktop) {
      _selectionPreview.value = value;
    } else {
      setState(() {});
    }
  }

  TextPainter _layoutText(
    TextSpan spans,
    TextAlign align,
    TextDirection direction,
    TextScaler scaler,
    double width,
  ) {
    final signature = (spans, align, direction, scaler, width);
    if (_cachedLayout != signature) {
      _cachedPainter?.dispose();
      _cachedLayout = signature;
      _cachedPainter = TextPainter(
        text: spans,
        textAlign: align,
        textDirection: direction,
        textScaler: scaler,
      )..layout(maxWidth: width);
    }
    return _cachedPainter!;
  }

  String? _revealedQuery;
  int? _revealedOffset;
  final Map<String, TapGestureRecognizer> links = {};
  final Map<String, TapGestureRecognizer> noteLinks = {};
  TextSelection selection = const TextSelection.collapsed(offset: -1);
  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    for (final link in links.values) {
      link.dispose();
    }
    links.clear();
    runs = paragraphRuns(widget.element, widget.style);
    for (final href in runs.map((r) => r.link).whereType<String>().toSet()) {
      links[href] = TapGestureRecognizer()..onTap = () => widget.onLink(href);
    }
  }

  @override
  void didUpdateWidget(covariant AnnotatedParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block ||
        oldWidget.element.outerHtml != widget.element.outerHtml ||
        oldWidget.style != widget.style) {
      _prepare();
    }
  }

  @override
  void dispose() {
    _selectionPreview.dispose();
    _cachedPainter?.dispose();
    for (final link in links.values) {
      link.dispose();
    }
    for (final note in noteLinks.values) {
      note.dispose();
    }
    super.dispose();
  }

  Future<void> annotate(MarkTool kind, {int? color}) async {
    final selected = selection;
    final text = runs.map((r) => r.text).join();
    if (!mounted ||
        !selected.isValid ||
        selected.isCollapsed ||
        !widget.store.loaded ||
        widget.store.loadFailed) {
      return;
    }
    final start = selected.start, end = selected.end;
    if (end > text.length) return;
    String note = '';
    List<String> attachments = [];
    if (kind == MarkTool.note) {
      final result = await editNoteContent(context);
      if (result == null || !mounted) return;
      note = result.text;
      attachments = result.images;
    }
    await widget.store.add(
      DocumentMark(
        anchor: widget.anchor,
        block: widget.block,
        tool: kind,
        start: start,
        end: end,
        quote: text.substring(start, end),
        text: note,
        attachments: attachments,
        color: color ?? widget.color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) {
      final marks = widget.store.marks
          .where((m) => m.block == widget.block && m.anchor == widget.anchor)
          .toList();
      final noteIds = marks
          .where((m) => m.tool == MarkTool.note)
          .map((m) => m.id)
          .toSet();
      for (final id
          in noteLinks.keys.where((id) => !noteIds.contains(id)).toList()) {
        noteLinks.remove(id)?.dispose();
      }
      for (final mark in marks.where((m) => m.tool == MarkTool.note)) {
        noteLinks
            .putIfAbsent(mark.id, () => TapGestureRecognizer())
            .onTap = () =>
            showPageNotes(context, widget.store, widget.anchor, selected: mark);
      }
      if (widget.searchQuery.isNotEmpty) {
        final text = runs.map((run) => run.text).join();
        final query = widget.searchQuery.toLowerCase();
        int offset = 0;
        while ((offset = text.toLowerCase().indexOf(query, offset)) >= 0) {
          marks.add(
            DocumentMark(
              anchor: widget.anchor,
              tool: MarkTool.highlight,
              start: offset,
              end: offset + query.length,
              color: offset == widget.searchOffset ? 0xffffa726 : 0xffffe082,
            ),
          );
          offset += query.length;
        }
      }
      final fontSize = widget.style.fontSize ?? 20;
      final style = ebookTextStyle(widget.element, widget.style, block: true);
      final textAlign = ebookAlignment(widget.element, widget.textAlign);
      final direction = ebookDirection(
        widget.element,
        Directionality.of(context),
      );
      final insets = widget.element.attributes['data-book-framed'] == '1'
          ? EdgeInsets.zero
          : ebookParagraphInsets(widget.element, style.fontSize ?? fontSize);
      final indent = ebookLength(
        ebookStyle(widget.element)['text-indent'],
        style.fontSize ?? fontSize,
      ).clamp(0.0, fontSize * 4).toDouble();
      // A presentation-only space creates the first-line inset. Annotation
      // ranges are translated for display, never changed in storage or sync.
      final prefix = indent > 0 && textAlign != TextAlign.center ? 1 : 0;
      final displayRuns = <ParagraphRun>[
        if (prefix != 0)
          ParagraphRun(
            '\u200a',
            TextStyle(fontSize: .01, letterSpacing: indent),
            null,
          ),
        ...runs,
      ];
      final displayMarks = prefix == 0
          ? marks
          : [
              for (final mark in marks)
                DocumentMark.fromJson({
                  ...mark.toJson(),
                  'start': mark.start + prefix,
                  'end': mark.end + prefix,
                }),
            ];
      final sourceLength = runs.fold<int>(0, (n, r) => n + r.text.length);
      TextSelection sourceSelection(TextSelection value) => !value.isValid
          ? value
          : TextSelection(
              baseOffset: (value.baseOffset - prefix).clamp(0, sourceLength),
              extentOffset: (value.extentOffset - prefix).clamp(
                0,
                sourceLength,
              ),
            );
      final content = Padding(
        padding: insets,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final spans = TextSpan(
                  style: DefaultTextStyle.of(context).style.merge(style),
                  children: markedParagraphSpans(
                    displayRuns,
                    displayMarks,
                    recognizers: links,
                    noteRecognizers: noteLinks,
                    paintAnnotations: false,
                  ),
                );
                final painter = isWindowsDesktop
                    ? _layoutText(
                        spans,
                        textAlign,
                        direction,
                        MediaQuery.textScalerOf(context),
                        constraints.maxWidth,
                      )
                    : (TextPainter(
                        text: spans,
                        textAlign: textAlign,
                        textDirection: direction,
                        textScaler: MediaQuery.textScalerOf(context),
                      )..layout(maxWidth: constraints.maxWidth));
                final searchOffset = widget.searchOffset;
                if (searchOffset == null) {
                  _revealedQuery = null;
                  _revealedOffset = null;
                }
                if (searchOffset != null &&
                    (_revealedQuery != widget.searchQuery ||
                        _revealedOffset != searchOffset)) {
                  _revealedQuery = widget.searchQuery;
                  _revealedOffset = searchOffset;
                  final boxes = painter.getBoxesForSelection(
                    TextSelection(
                      baseOffset: searchOffset + prefix,
                      extentOffset:
                          searchOffset + widget.searchQuery.length + prefix,
                    ),
                  );
                  if (boxes.isNotEmpty) {
                    final rect = boxes.first.toRect();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted || widget.searchOffset != searchOffset) {
                        return;
                      }
                      final render = context.findRenderObject();
                      final viewport = render == null
                          ? null
                          : RenderAbstractViewport.maybeOf(render);
                      final scrollable = Scrollable.maybeOf(context);
                      if (render == null ||
                          viewport == null ||
                          scrollable == null) {
                        return;
                      }
                      final position = scrollable.position;
                      final offset = viewport
                          .getOffsetToReveal(render, .25, rect: rect)
                          .offset;
                      position.animateTo(
                        offset.clamp(
                          position.minScrollExtent,
                          position.maxScrollExtent,
                        ),
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                      );
                    });
                  }
                }
                int position(Offset p) =>
                    (painter.getPositionForOffset(p).offset - prefix).clamp(
                      0,
                      sourceLength,
                    );
                final active = [
                  MarkTool.highlight,
                  MarkTool.underline,
                  MarkTool.strikethrough,
                  MarkTool.note,
                ].contains(widget.activeTool);
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ParagraphMarkPainter(
                            painter,
                            displayMarks,
                            displayRuns.map((r) => r.text).join(),
                            foreground: false,
                          ),
                        ),
                      ),
                    ),
                    _DesktopSelectionBoundary(
                      child: IgnorePointer(
                        ignoring: active,
                        child: SelectableText.rich(
                          TextSpan(
                            children: markedParagraphSpans(
                              displayRuns,
                              displayMarks,
                              recognizers: links,
                              noteRecognizers: noteLinks,
                              paintAnnotations: false,
                            ),
                          ),
                          style: style,
                          textAlign: textAlign,
                          textDirection: direction,
                          onSelectionChanged: (value, cause) {
                            selection = sourceSelection(value);
                            widget.onSelection(annotate);
                          },
                          contextMenuBuilder: (context, editable) =>
                              SelectionPanel(
                                readText: () async => editable
                                    .textEditingValue
                                    .selection
                                    .textInside(editable.textEditingValue.text),
                                onClose: () =>
                                    closeReaderTextSelection(editable),
                                onAnnotate: widget.onAnnotate,
                                onMark: (kind, color) =>
                                    annotate(kind, color: color),
                              ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: ParagraphMarkPainter(
                            painter,
                            displayMarks,
                            displayRuns.map((r) => r.text).join(),
                            foreground: true,
                          ),
                        ),
                      ),
                    ),
                    if (active)
                      Positioned.fill(
                        child: ImmediateMarkSurface(
                          session: widget.gestureSession,
                          onStart: (p) => _updateSelection(
                            TextSelection.collapsed(offset: position(p)),
                          ),
                          onUpdate: (p) => _updateSelection(
                            TextSelection(
                              baseOffset: selection.baseOffset,
                              extentOffset: position(p),
                            ),
                          ),
                          onCancel: () => _updateSelection(
                            const TextSelection.collapsed(offset: -1),
                          ),
                          onEnd: () async {
                            await annotate(widget.activeTool);
                            if (mounted) {
                              _updateSelection(
                                const TextSelection.collapsed(offset: -1),
                              );
                            }
                          },
                        ),
                      ),
                    if (active && isWindowsDesktop)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ValueListenableBuilder<TextSelection>(
                            valueListenable: _selectionPreview,
                            builder: (context, value, _) =>
                                !value.isValid || value.isCollapsed
                                ? const SizedBox.shrink()
                                : CustomPaint(
                                    painter: _SelectionPreview(
                                      painter
                                          .getBoxesForSelection(
                                            TextSelection(
                                              baseOffset:
                                                  value.baseOffset + prefix,
                                              extentOffset:
                                                  value.extentOffset + prefix,
                                            ),
                                          )
                                          .map((box) => box.toRect())
                                          .toList(),
                                      Theme.of(context).colorScheme.primary,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    if (active &&
                        !isWindowsDesktop &&
                        selection.isValid &&
                        !selection.isCollapsed)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _SelectionPreview(
                              painter
                                  .getBoxesForSelection(
                                    TextSelection(
                                      baseOffset: selection.baseOffset + prefix,
                                      extentOffset:
                                          selection.extentOffset + prefix,
                                    ),
                                  )
                                  .map((box) => box.toRect())
                                  .toList(),
                              Theme.of(context).colorScheme.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            if (widget.activeTool == MarkTool.note &&
                marks.any((m) => m.tool == MarkTool.note))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  label: const Text('View notes'),
                  onPressed: () =>
                      showPageNotes(context, widget.store, widget.anchor),
                ),
              ),
          ],
        ),
      );
      // Native table layout probes cells with unbounded width before assigning
      // columns. Never pass that infinity into the stretched selectable column.
      return LayoutBuilder(
        builder: (context, bounds) {
          final fallback =
              widget.fallbackWidth ?? MediaQuery.sizeOf(context).width;
          final width = bounds.hasBoundedWidth
              ? bounds.maxWidth
              : fallback.clamp(1.0, double.infinity).toDouble();
          if (widget.element.attributes['data-book-fit-label'] == '1') {
            final label = TextPainter(
              text: TextSpan(
                style: style,
                children: [
                  for (final run in runs)
                    TextSpan(text: run.text, style: run.style),
                ],
              ),
              textDirection: direction,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            final natural = label.maxIntrinsicWidth + insets.horizontal + 12;
            label.dispose();
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width),
              child: Align(
                alignment: Alignment.topCenter,
                heightFactor: 1,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: natural,
                    child: isWindowsDesktop
                        ? RepaintBoundary(child: content)
                        : content,
                  ),
                ),
              ),
            );
          }
          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: width),
            child: isWindowsDesktop ? RepaintBoundary(child: content) : content,
          );
        },
      );
    },
  );
}

class _SelectionPreview extends CustomPainter {
  _SelectionPreview(this.boxes, this.color);
  final List<Rect> boxes;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) {
      canvas.drawRect(box, Paint()..color = color.withValues(alpha: .22));
    }
  }

  @override
  bool shouldRepaint(_SelectionPreview old) =>
      old.boxes != boxes || old.color != color;
}

class ParagraphMarkPainter extends CustomPainter {
  ParagraphMarkPainter(
    this.layout,
    this.marks,
    this.text, {
    required this.foreground,
  });
  final TextPainter layout;
  final List<DocumentMark> marks;
  final String text;
  final bool foreground;
  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in marks) {
      if (mark.start < 0 ||
          mark.end > text.length ||
          mark.start >= mark.end ||
          (mark.quote.isNotEmpty &&
              text.substring(mark.start, mark.end) != mark.quote)) {
        continue;
      }
      final background =
          mark.tool == MarkTool.highlight || mark.tool == MarkTool.note;
      final underline =
          mark.tool == MarkTool.underline || mark.tool == MarkTool.note;
      final strike = mark.tool == MarkTool.strikethrough;
      if (foreground ? (!underline && !strike) : !background) continue;
      final boxes = layout.getBoxesForSelection(
        TextSelection(baseOffset: mark.start, extentOffset: mark.end),
      );
      final rects = continuousMarkRects(boxes.map((b) => b.toRect()));
      final color = Color(mark.color ?? (background ? 0xffffe082 : 0xff29b6f6));
      final paint = Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      for (final rect in rects) {
        if (!foreground) {
          canvas.drawRect(rect, paint);
        } else {
          final y = strike ? rect.center.dy : rect.bottom - 1;
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant ParagraphMarkPainter old) => true;
}

class _DesktopSelectionBoundary extends StatelessWidget {
  const _DesktopSelectionBoundary({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) =>
      isWindowsDesktop ? RepaintBoundary(child: child) : child;
}
