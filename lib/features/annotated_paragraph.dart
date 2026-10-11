import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;
import 'annotations.dart';
import 'reader_gestures.dart';

const _blocks = 'p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,td,th,div';

/// Stable IDs tie EPUB ranges to source paragraphs rather than screen coordinates.
String prepareSelectableMarkup(String source) {
  final document = html.parse(source);
  final blocks = document.querySelectorAll(_blocks);
  for (int index = 0; index < blocks.length; index++) {
    final element = blocks[index];
    // Leave image-containing layouts to the HTML renderer so artwork stays intact.
    if (element.querySelector(_blocks) != null || element.querySelector('img,image,svg') != null || element.text.trim().isEmpty) continue;
    element.attributes['data-qr-block'] = '$index';
  }
  return document.body?.innerHtml ?? source;
}

class ParagraphRun {
  const ParagraphRun(this.text, this.style, this.link);
  final String text;
  final TextStyle style;
  final String? link;
}

List<ParagraphRun> paragraphRuns(dom.Element element) {
  final runs = <ParagraphRun>[];
  void visit(dom.Node node, TextStyle style, String? link) {
    if (node is dom.Text) {
      final text = element.localName == 'pre' ? node.data : node.data.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isNotEmpty) runs.add(ParagraphRun(text, style, link));
    } else if (node is dom.Element) {
      if (node.localName == 'br') { runs.add(ParagraphRun('\n', style, link)); return; }
      var next = style;
      if (['b', 'strong'].contains(node.localName)) next = next.copyWith(fontWeight: FontWeight.bold);
      if (['i', 'em'].contains(node.localName)) next = next.copyWith(fontStyle: FontStyle.italic);
      if (['code', 'pre'].contains(node.localName)) next = next.copyWith(fontFamily: 'monospace');
      if (node.localName == 'a') next = next.copyWith(decoration: TextDecoration.underline);
      for (final child in node.nodes) { visit(child, next, node.attributes['href'] ?? link); }
    }
  }
  visit(element, const TextStyle(), null);
  return runs;
}

/// Splits at source-style and annotation boundaries, preserving overlapping marks.
List<TextSpan> markedParagraphSpans(List<ParagraphRun> runs, List<DocumentMark> marks,
    {Map<String, GestureRecognizer> recognizers = const {}}) {
  final text = runs.map((r) => r.text).join();
  final edges = <int>{0, text.length};
  int offset = 0;
  for (final run in runs) { offset += run.text.length; edges.add(offset); }
  for (final mark in marks) {
    if (mark.start < 0 || mark.end > text.length || mark.start >= mark.end) continue;
    // If the publisher content changed, do not decorate unrelated characters.
    if (mark.quote.isNotEmpty && text.substring(mark.start, mark.end) != mark.quote) continue;
    edges.add(mark.start); edges.add(mark.end);
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
    final applied = marks.where((m) => m.start <= start && m.end >= end && m.start >= 0 && m.end <= text.length
      && (m.quote.isEmpty || text.substring(m.start, m.end) == m.quote)).toList();
    var style = run.style;
    final decorations = <TextDecoration>[if (style.decoration != null) style.decoration!];
    if (applied.any((m) => m.tool == MarkTool.highlight)) {
      final highlight = applied.lastWhere((m) => m.tool == MarkTool.highlight);
      final color = Color(highlight.color ?? 0xffffe082);
      style = style.copyWith(backgroundColor: color, color: color.computeLuminance() < .35 ? Colors.white : const Color(0xff202020));
    }
    if (applied.any((m) => m.tool == MarkTool.underline || m.tool == MarkTool.note)) decorations.add(TextDecoration.underline);
    if (applied.any((m) => m.tool == MarkTool.strikethrough)) decorations.add(TextDecoration.lineThrough);
    if (decorations.isNotEmpty) {
      final colored = applied.where((m) => m.color != null && [MarkTool.underline, MarkTool.strikethrough, MarkTool.note].contains(m.tool));
      style = style.copyWith(decoration: TextDecoration.combine(decorations), decorationColor: colored.isEmpty ? null : Color(colored.last.color!));
    }
    spans.add(TextSpan(text: text.substring(start, end), style: style, recognizer: recognizers[run.link]));
  }
  return spans;
}

class AnnotatedParagraph extends StatefulWidget {
  const AnnotatedParagraph({super.key, required this.element, required this.block,
    required this.anchor, required this.store, required this.style, required this.onSelection, required this.onLink, this.color,
    this.activeTool = MarkTool.browse, this.gestureSession, this.textAlign = TextAlign.start});
  final TextAlign textAlign;
  final MarkTool activeTool;
  final ReaderGestureSession? gestureSession;
  final int? color;
  final dom.Element element;
  final String block, anchor;
  final AnnotationStore store;
  final TextStyle style;
  final ValueChanged<Future<void> Function(MarkTool)> onSelection;
  final ValueChanged<String> onLink;
  @override
  State<AnnotatedParagraph> createState() => _AnnotatedParagraphState();
}

class _AnnotatedParagraphState extends State<AnnotatedParagraph> {
  late List<ParagraphRun> runs;
  final Map<String, TapGestureRecognizer> links = {};
  TextSelection selection = const TextSelection.collapsed(offset: -1);
  @override
  void initState() { super.initState(); _prepare(); }
  void _prepare() {
    for (final link in links.values) { link.dispose(); }
    links.clear();
    runs = paragraphRuns(widget.element);
    for (final href in runs.map((r) => r.link).whereType<String>().toSet()) {
      links[href] = TapGestureRecognizer()..onTap = () => widget.onLink(href);
    }
  }
  @override
  void didUpdateWidget(covariant AnnotatedParagraph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block != widget.block || oldWidget.element.outerHtml != widget.element.outerHtml) _prepare();
  }
  @override
  void dispose() { for (final link in links.values) { link.dispose(); } super.dispose(); }

  Future<void> annotate(MarkTool kind) async {
    final selected = selection;
    final text = runs.map((r) => r.text).join();
    if (!mounted || !selected.isValid || selected.isCollapsed || !widget.store.loaded || widget.store.loadFailed) return;
    final start = selected.start, end = selected.end;
    if (end > text.length) return;
    String note = '';
    if (kind == MarkTool.note) {
      final result = await editNote(context);
      if (result == null || !mounted) return;
      note = result;
    }
    await widget.store.add(DocumentMark(anchor: widget.anchor, block: widget.block, tool: kind,
      start: start, end: end, quote: text.substring(start, end), text: note, color: widget.color));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final marks = widget.store.marks.where((m) => m.block == widget.block && m.anchor == widget.anchor).toList();
    final tag = widget.element.localName ?? '';
    final heading = RegExp(r'^h[1-6]$').hasMatch(tag);
    final level = heading ? int.parse(tag.substring(1)) : 0;
    final fontSize = widget.style.fontSize ?? 20;
    final style = heading ? widget.style.copyWith(fontSize: fontSize * (level == 1 ? 1.65 : level == 2 ? 1.35 : 1.15),
      height: 1.3, fontWeight: FontWeight.w600) : tag == 'pre' ? widget.style.copyWith(fontFamily: 'monospace', height: 1.5) : widget.style;
    return Padding(padding: EdgeInsets.only(top: heading ? fontSize * .65 : 0, bottom: fontSize * (heading ? .65 : .6),
      left: tag == 'blockquote' ? 20 : 0), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, constraints) {
        final spans = TextSpan(style: DefaultTextStyle.of(context).style.merge(style), children: markedParagraphSpans(runs, marks, recognizers: links));
        final painter = TextPainter(text: spans, textAlign: widget.textAlign, textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
          ..layout(maxWidth: constraints.maxWidth);
        int position(Offset p) => painter.getPositionForOffset(p).offset;
        final active = [MarkTool.highlight, MarkTool.underline, MarkTool.strikethrough, MarkTool.note].contains(widget.activeTool);
        return Stack(children: [
      IgnorePointer(ignoring: active, child: SelectableText.rich(TextSpan(children: markedParagraphSpans(runs, marks, recognizers: links)),
        style: style, textAlign: widget.textAlign,
        onSelectionChanged: (value, cause) { selection = value; widget.onSelection(annotate); },
        contextMenuBuilder: (context, editable) => AdaptiveTextSelectionToolbar.buttonItems(
          anchors: editable.contextMenuAnchors,
          buttonItems: [
            ...editable.contextMenuButtonItems,
            for (final entry in const {MarkTool.highlight: 'Highlight', MarkTool.underline: 'Underline', MarkTool.strikethrough: 'Strikethrough', MarkTool.note: 'Note'}.entries)
              ContextMenuButtonItem(label: entry.value, onPressed: () { editable.hideToolbar(); annotate(entry.key); }),
          ],
        ),
      )),
      if (active) Positioned.fill(child: ImmediateMarkSurface(session: widget.gestureSession,
        onStart: (p) => setState(() => selection = TextSelection.collapsed(offset: position(p))),
        onUpdate: (p) => setState(() => selection = TextSelection(baseOffset: selection.baseOffset, extentOffset: position(p))),
        onCancel: () => setState(() => selection = const TextSelection.collapsed(offset: -1)),
        onEnd: () async {
          await annotate(widget.activeTool);
          if (mounted) setState(() => selection = const TextSelection.collapsed(offset: -1));
        })),
      if (active && selection.isValid && !selection.isCollapsed) Positioned.fill(child: IgnorePointer(child: CustomPaint(
        painter: _SelectionPreview(painter.getBoxesForSelection(selection).map((box) => box.toRect()).toList(), Theme.of(context).colorScheme.primary)))),
        ]);
      }),
      for (final mark in marks.where((m) => m.tool == MarkTool.note))
        Align(alignment: Alignment.centerRight, child: IconButton(tooltip: mark.text, icon: const Icon(Icons.sticky_note_2_outlined),
          onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
            title: const Text('Note'), content: SingleChildScrollView(child: SelectableText('${mark.quote}\n\n${mark.text}')),
            actions: [TextButton(onPressed: () { widget.store.remove(mark); Navigator.pop(context); }, child: const Text('Delete')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          )))),
    ]));
  });
}

class _SelectionPreview extends CustomPainter {
  _SelectionPreview(this.boxes, this.color);
  final List<Rect> boxes;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    for (final box in boxes) { canvas.drawRect(box, Paint()..color = color.withValues(alpha: .22)); }
  }
  @override
  bool shouldRepaint(_SelectionPreview old) => old.boxes != boxes || old.color != color;
}
