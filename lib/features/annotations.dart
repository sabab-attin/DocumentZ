import 'dart:convert';
import 'package:flutter/material.dart';
import 'reader_gestures.dart';
import 'package:pdfrx/pdfrx.dart' show PdfOverlayInteractionRegion;
import 'package:shared_preferences/shared_preferences.dart';

enum MarkTool { browse, pen, highlight, underline, strikethrough, signature, note, bookmark, eraser, arrow, rectangle, callout }

class DocumentMark {
  DocumentMark({required this.anchor, required this.tool, this.points = const [], this.text = '', this.group = '',
    this.rects = const [], this.quote = '', this.block = '', this.start = 0, this.end = 0,
    this.color, this.width, this.rotation = 0, this.geometryVersion = 1});
  final int geometryVersion;
  final int rotation;
  final int? color;
  final double? width;
  final String anchor;
  final MarkTool tool;
  final List<Offset> points;
  final String text;
  final String group;
  final List<Rect> rects;
  final String quote;
  final String block;
  final int start;
  final int end;
  Map<String, dynamic> toJson() => {
    'anchor': anchor, 'tool': tool.name, 'text': text, 'group': group,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
    'rects': rects.map((r) => [r.left, r.top, r.right, r.bottom]).toList(),
    'quote': quote, 'block': block, 'start': start, 'end': end,
    'color': color, 'width': width, 'rotation': rotation, 'geometryVersion': geometryVersion,
  };
  factory DocumentMark.fromJson(Map<String, dynamic> json) => DocumentMark(
    anchor: json['anchor'] as String, tool: MarkTool.values.byName(json['tool'] as String),
    text: json['text'] as String,
    group: json['group'] as String? ?? '',
    quote: json['quote'] as String? ?? '', block: json['block'] as String? ?? '',
    start: json['start'] as int? ?? 0, end: json['end'] as int? ?? 0,
    color: json['color'] as int?, width: (json['width'] as num?)?.toDouble(),
    rotation: json['rotation'] as int? ?? 0,
    geometryVersion: json['geometryVersion'] as int? ?? 0,
    rects: (json['rects'] as List? ?? []).map((r) => Rect.fromLTRB((r[0] as num).toDouble(), (r[1] as num).toDouble(), (r[2] as num).toDouble(), (r[3] as num).toDouble())).toList(),
    points: (json['points'] as List).map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList(),
  );
}

/// Correct saved marks from the old square-target conversion without changing
/// the original document or repeatedly rewriting annotation storage.
Rect displayedMarkRect(DocumentMark mark, Rect rect, Size pageSize) {
  if (mark.geometryVersion >= 1 || pageSize.isEmpty) return rect;
  final x = pageSize.height > pageSize.width ? pageSize.height / pageSize.width : 1.0;
  final y = pageSize.width > pageSize.height ? pageSize.width / pageSize.height : 1.0;
  return Rect.fromLTRB(rect.left * x, rect.top * y, rect.right * x, rect.bottom * y);
}

/// Separate app annotations; the imported document remains usable by other readers.
class AnnotationStore extends ChangeNotifier {
  AnnotationStore(this.documentId);
  final String documentId;
  final List<DocumentMark> _marks = [];
  final List<({Set<String> anchors, List<DocumentMark> before, List<DocumentMark> after})> _history = [];
  void _remember(Set<String> anchors) {
    _history.add((anchors: anchors, before: List.of(_marks), after: []));
    if (_history.length > 100) {
      _history.removeAt(0);
    }
  }
  void _rememberResult() => _history.last.after.addAll(_marks);
  bool canUndo(String anchor) => _history.any((h) => h.anchors.contains(anchor)) ||
    _marks.any((m) => m.anchor == anchor && m.tool != MarkTool.bookmark);
  List<DocumentMark> get marks => List.unmodifiable(_marks);
  List<DocumentMark> get entries {
    final groups = <String>{};
    return _marks.where((m) => m.group.isEmpty || groups.add(m.group)).toList();
  }
  bool loaded = false;
  bool saveFailed = false;
  bool loadFailed = false;
  Future<void> _pending = Future.value();
  String get _key => 'annotations.v1.$documentId';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null) {
        final parsed = (jsonDecode(raw) as List).map((j) => DocumentMark.fromJson(j as Map<String, dynamic>)).toList();
        _marks.addAll(parsed);
      }
    } catch (_) { loadFailed = true; }
    loaded = true;
    notifyListeners();
  }

  Future<void> add(DocumentMark mark) {
    if (!loaded || loadFailed) return Future.value();
    if (mark.tool != MarkTool.bookmark) _remember({mark.anchor});
    _marks.add(mark);
    if (mark.tool != MarkTool.bookmark) _rememberResult();
    notifyListeners();
    return _save();
  }

  Future<void> addMany(List<DocumentMark> marks) {
    if (!loaded || loadFailed) return Future.value();
    if (marks.isEmpty) return Future.value();
    _remember(marks.map((m) => m.anchor).toSet());
    _marks.addAll(marks);
    _rememberResult();
    notifyListeners();
    return _save();
  }

  Future<void> remove(DocumentMark mark) {
    if (!loaded || loadFailed) return Future.value();
    if (mark.tool != MarkTool.bookmark) {
      _remember(_marks.where((m) => identical(m, mark) || (mark.group.isNotEmpty && m.group == mark.group)).map((m) => m.anchor).toSet());
    }
    if (mark.group.isEmpty) { _marks.remove(mark); }
    else { _marks.removeWhere((m) => m.group == mark.group); }
    if (mark.tool != MarkTool.bookmark) _rememberResult();
    notifyListeners();
    return _save();
  }

  Future<void> undo(String anchor) {
    if (!loaded || loadFailed) return Future.value();
    final historyIndex = _history.lastIndexWhere((h) => h.anchors.contains(anchor));
    if (historyIndex >= 0) {
      final change = _history.removeAt(historyIndex);
      final added = change.after.where((m) => !change.before.contains(m) && m.tool != MarkTool.bookmark).toSet();
      _marks.removeWhere(added.contains);
      for (int i = 0; i < change.before.length; i++) {
        final mark = change.before[i];
        if (mark.tool != MarkTool.bookmark && !change.after.contains(mark) && !_marks.contains(mark)) {
          _marks.insert(i.clamp(0, _marks.length), mark);
        }
      }
      notifyListeners();
      return _save();
    }
    final index = _marks.lastIndexWhere((m) => m.anchor == anchor && m.tool != MarkTool.bookmark);
    if (index < 0) return Future.value();
    final mark = _marks[index];
    if (mark.group.isEmpty) { _marks.removeAt(index); }
    else { _marks.removeWhere((m) => m.group == mark.group); }
    notifyListeners();
    return _save();
  }

  Future<void> eraseStroke(String anchor, List<Offset> points, Size size, double radius) {
    if (!loaded || loadFailed || points.isEmpty) return Future.value();
    final hits = _marks.where((m) => m.anchor == anchor && m.tool != MarkTool.bookmark &&
      strokeHitsMark(m, points, size, radius)).toSet();
    if (hits.isEmpty) return Future.value();
    final groups = hits.where((m) => m.group.isNotEmpty).map((m) => m.group).toSet();
    final erased = _marks.where((m) => hits.contains(m) || groups.contains(m.group)).toSet();
    _remember(erased.map((m) => m.anchor).toSet());
    _marks.removeWhere(erased.contains);
    _rememberResult();
    notifyListeners();
    return _save();
  }

  Future<void> _save() {
    final data = jsonEncode(_marks.map((m) => m.toJson()).toList());
    _pending = _pending.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        saveFailed = !await prefs.setString(_key, data);
      } catch (_) { saveFailed = true; }
      notifyListeners();
    });
    return _pending;
  }

  // Pending writes may outlive the reader route.
  bool _disposed = false;
  @override
  void notifyListeners() { if (!_disposed) super.notifyListeners(); }
  @override
  void dispose() { _disposed = true; super.dispose(); }
}

Future<String?> editNote(BuildContext context) async {
  return showDialog<String>(context: context, builder: (_) => const _NoteDialog());
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog();
  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}
class _NoteDialogState extends State<_NoteDialog> {
  final input = TextEditingController();
  @override
  void dispose() { input.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Note'),
    content: TextField(controller: input, autofocus: true, maxLines: 5, maxLength: 2000,
      decoration: const InputDecoration(hintText: 'Write a note')),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () {
        if (input.text.trim().isNotEmpty) Navigator.pop(context, input.text.trim());
      }, child: const Text('Save')),
    ],
  );
}

class PageMarks extends StatefulWidget {
  const PageMarks({super.key, required this.store, required this.anchor, required this.tool,
    required this.dark, required this.onTouched, this.signature = const [], this.color, this.width = .0035,
    this.eraserRadius = .025, this.shapeText = '', this.gestureSession, this.onTextStroke, this.onTextPreview, this.onTextCancel});
  final ReaderGestureSession? gestureSession;
  final Future<bool> Function(List<Offset> points, Size size)? onTextStroke;
  final void Function(List<Offset> points, Size size)? onTextPreview;
  final VoidCallback? onTextCancel;
  final String shapeText;
  final int? color;
  final double width, eraserRadius;
  final AnnotationStore store;
  final String anchor;
  final MarkTool tool;
  final bool dark;
  final VoidCallback onTouched;
  final List<List<Offset>> signature;
  @override
  State<PageMarks> createState() => _PageMarksState();
}

class _PageMarksState extends State<PageMarks> {
  final List<Offset> draft = [];
  Offset normalized(Offset p, Size size) => Offset((p.dx / size.width).clamp(0, 1), (p.dy / size.height).clamp(0, 1));
  @override
  void didUpdateWidget(covariant PageMarks oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool != widget.tool) draft.clear();
  }
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final size = constraints.biggest;
    final active = widget.tool != MarkTool.browse && widget.tool != MarkTool.bookmark && widget.store.loaded && !widget.store.loadFailed;
    final marks = widget.store.marks.where((m) => m.anchor == widget.anchor).toList();
    return Stack(children: [
      Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: MarkPainter(
        marks: marks, draft: draft, tool: widget.tool, dark: widget.dark, color: widget.color,
        width: widget.width, eraserRadius: widget.eraserRadius)))),
      for (final mark in marks.where((m) => m.tool == MarkTool.note && (m.points.isNotEmpty || m.rects.isNotEmpty)))
        Positioned(left: ((mark.rects.isNotEmpty ? displayedMarkRect(mark, mark.rects.first, size).right : mark.points.first.dx) * size.width).clamp(0, (size.width - 48).clamp(0, double.infinity)),
          top: ((mark.rects.isNotEmpty ? displayedMarkRect(mark, mark.rects.first, size).top : mark.points.first.dy) * size.height).clamp(0, (size.height - 48).clamp(0, double.infinity)),
          child: PdfOverlayInteractionRegion(child: IconButton.filled(tooltip: mark.text, icon: const Icon(Icons.sticky_note_2_outlined),
            onPressed: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
              title: const Text('Note'), content: SingleChildScrollView(child: SelectableText('${mark.quote.isEmpty ? '' : '${mark.quote}\n\n'}${mark.text}')),
              actions: [TextButton(onPressed: () { widget.store.remove(mark); Navigator.pop(context); }, child: const Text('Delete')),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
            ))))),
      if (active) Positioned.fill(child:
        Semantics(label: 'Drag to mark; use two fingers to scroll', child: ImmediateMarkSurface(
          session: widget.gestureSession,
          onStart: (p) => _start(p, size), onUpdate: (p) => _update(p, size),
          onEnd: () => _finish(size),
          onCancel: () { setState(draft.clear); widget.onTextCancel?.call(); },
        ))),
    ]);
  });

  void _start(Offset point, Size size) {
    widget.onTouched();
    setState(() { draft.clear(); draft.add(normalized(point, size)); });
  }
  void _update(Offset point, Size size) {
    setState(() => draft.add(normalized(point, size)));
    widget.onTextPreview?.call(List.of(draft), size);
  }
  Future<void> _finish(Size size) async {
    final stroke = List<Offset>.of(draft);
    setState(draft.clear);
    if (stroke.isNotEmpty) {
      if (widget.onTextStroke != null && await widget.onTextStroke!(stroke, size)) return;
      if (!mounted) return;
      if (widget.tool == MarkTool.signature) {
        final left = stroke.first.dx.clamp(0.0, .7), top = stroke.first.dy.clamp(0.0, .88);
        final group = DateTime.now().microsecondsSinceEpoch.toString();
        widget.store.addMany(widget.signature.map((line) => DocumentMark(anchor: widget.anchor, tool: MarkTool.signature,
          group: group, color: widget.color, width: widget.width,
          points: line.map((p) => Offset(left + p.dx * .3, top + p.dy * .12)).toList())).toList());
        return;
      }
      if (widget.tool == MarkTool.note) {
        final note = widget.shapeText.isEmpty ? await editNote(context) : widget.shapeText;
        if (note != null && mounted) widget.store.add(DocumentMark(anchor: widget.anchor, tool: MarkTool.note, points: [stroke.first], text: note));
        return;
      }
      if (widget.tool == MarkTool.eraser) {
        widget.store.eraseStroke(widget.anchor, stroke, size, widget.eraserRadius * size.width);
      } else {
        widget.store.add(DocumentMark(anchor: widget.anchor, tool: widget.tool, color: widget.color, width: widget.width,
          text: widget.tool == MarkTool.callout ? widget.shapeText : '',
          points: widget.tool == MarkTool.underline || widget.tool == MarkTool.strikethrough
            || widget.tool == MarkTool.arrow || widget.tool == MarkTool.rectangle || widget.tool == MarkTool.callout
            ? [stroke.first, widget.tool == MarkTool.underline || widget.tool == MarkTool.strikethrough
              ? Offset(stroke.last.dx, stroke.first.dy) : stroke.last] : stroke));
      }
    }
  }
}

class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final List<List<Offset>> strokes = [];
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Signature'),
    content: SizedBox(width: 420, height: 180, child: LayoutBuilder(builder: (context, constraints) {
      Offset point(Offset p) => Offset((p.dx / constraints.maxWidth).clamp(0, 1), (p.dy / constraints.maxHeight).clamp(0, 1));
      return ColoredBox(color: Colors.white, child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (d) => setState(() => strokes.add([point(d.localPosition)])),
        onPanUpdate: (d) => setState(() { if (strokes.isNotEmpty) strokes.last.add(point(d.localPosition)); }),
        child: Semantics(label: 'Draw your signature', child: CustomPaint(painter: MarkPainter(
          marks: strokes.map((s) => DocumentMark(anchor: '', tool: MarkTool.signature, points: s)).toList()), child: const SizedBox.expand())),
      ));
    })),
    actions: [
      TextButton(onPressed: () => setState(strokes.clear), child: const Text('Clear')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: strokes.isEmpty ? null : () => Navigator.pop(context, strokes.map((s) => List<Offset>.of(s)).toList()), child: const Text('Use signature')),
    ],
  );
}

class MarkPainter extends CustomPainter {
  MarkPainter({required this.marks, this.draft = const [], this.tool = MarkTool.pen, this.dark = false,
    this.color, this.width = .0035, this.eraserRadius = .025});
  final int? color;
  final double width, eraserRadius;
  final List<DocumentMark> marks;
  final List<Offset> draft;
  final MarkTool tool;
  final bool dark;
  @override
  void paint(Canvas canvas, Size size) {
    for (final mark in [...marks, if (draft.isNotEmpty && tool != MarkTool.eraser)
      DocumentMark(anchor: '', tool: tool, points: draft, color: color, width: width)]) {
      for (final stored in mark.rects) {
        final normalized = displayedMarkRect(mark, stored, size);
        final rect = Rect.fromLTRB(normalized.left * size.width, normalized.top * size.height,
          normalized.right * size.width, normalized.bottom * size.height);
        final base = mark.color == null ? (mark.tool == MarkTool.highlight ? const Color(0xffffcc00) : const Color(0xff29b6f6)) : Color(mark.color!);
        final paint = Paint()..color = mark.tool == MarkTool.highlight ? base.withValues(alpha: .35) : base
          ..strokeWidth = (size.width * (mark.width ?? .0025)).clamp(1, 12);
        if (mark.tool == MarkTool.highlight) { canvas.drawRect(rect, paint); }
        else if (mark.tool == MarkTool.underline || mark.tool == MarkTool.note) {
          switch (mark.rotation % 4) {
            case 1: canvas.drawLine(rect.topLeft, rect.bottomLeft, paint);
            case 2: canvas.drawLine(rect.topLeft, rect.topRight, paint);
            case 3: canvas.drawLine(rect.topRight, rect.bottomRight, paint);
            default: canvas.drawLine(rect.bottomLeft, rect.bottomRight, paint);
          }
        } else if (mark.tool == MarkTool.strikethrough) {
          if (mark.rotation.isOdd) {
            canvas.drawLine(Offset(rect.center.dx, rect.top), Offset(rect.center.dx, rect.bottom), paint);
          } else {
            canvas.drawLine(Offset(rect.left, rect.center.dy), Offset(rect.right, rect.center.dy), paint);
          }
        }
      }
      if (mark.tool == MarkTool.note || mark.points.isEmpty) continue;
      final highlight = mark.tool == MarkTool.highlight;
      final base = mark.color == null ? (highlight ? const Color(0xffffcc00) : dark ? Colors.white : const Color(0xff153d8a)) : Color(mark.color!);
      final paint = Paint()..color = highlight ? base.withValues(alpha: .35) : base
        ..style = PaintingStyle.stroke..strokeWidth = size.width * (mark.width ?? (highlight ? .025 : .0035))
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round;
      if ([MarkTool.arrow, MarkTool.rectangle, MarkTool.callout].contains(mark.tool) && mark.points.length >= 2) {
        final a = Offset(mark.points.first.dx * size.width, mark.points.first.dy * size.height);
        final b = Offset(mark.points.last.dx * size.width, mark.points.last.dy * size.height);
        if (mark.tool == MarkTool.arrow) {
          canvas.drawLine(a, b, paint);
          final delta = b - a;
          if (delta.distance > 0) {
            final unit = delta / delta.distance;
            final perpendicular = Offset(-unit.dy, unit.dx);
            final length = (paint.strokeWidth * 4).clamp(10.0, 30.0);
            canvas.drawLine(b, b - unit * length + perpendicular * length / 2, paint);
            canvas.drawLine(b, b - unit * length - perpendicular * length / 2, paint);
          }
        } else {
          final box = Rect.fromPoints(a, b);
          canvas.drawRect(box, paint);
          if (mark.tool == MarkTool.callout && mark.text.isNotEmpty && box.width > 12 && box.height > 12) {
            final label = TextPainter(text: TextSpan(text: mark.text, style: TextStyle(color: base, fontSize: (size.width * .025).clamp(12.0, 28.0))),
              textDirection: TextDirection.ltr, ellipsis: '…', maxLines: (box.height / (size.width * .035)).floor().clamp(1, 30));
            label.layout(maxWidth: box.width - 8);
            canvas.save(); canvas.clipRect(box); label.paint(canvas, box.topLeft + const Offset(4, 4)); canvas.restore(); label.dispose();
          }
        }
        continue;
      }
      final path = smoothStrokePath(mark.points, size);
      if (mark.points.length == 1) {
        canvas.drawCircle(Offset(mark.points.first.dx * size.width, mark.points.first.dy * size.height), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      } else { canvas.drawPath(path, paint); }
    }
    if (tool == MarkTool.eraser && draft.isNotEmpty) {
      final cursor = Paint()
        ..color = (dark ? Colors.white : Colors.black)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(Offset(draft.last.dx * size.width, draft.last.dy * size.height), size.width * eraserRadius, cursor);
    }
  }
  @override
  bool shouldRepaint(covariant MarkPainter oldDelegate) => true;
}

/// Hit-test entire segments so quick eraser movements cannot skip thin strokes.
bool strokeHitsMark(DocumentMark mark, List<Offset> eraser, Size size, double radius) {
  Offset scale(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
  final points = eraser.map(scale).toList();
  final tolerance = radius + (mark.width ?? .0035) * size.width / 2;
  double distance(Offset p, Offset a, Offset b) {
    final delta = b - a;
    final t = delta.distanceSquared == 0 ? 0.0 :
      (((p.dx - a.dx) * delta.dx + (p.dy - a.dy) * delta.dy) / delta.distanceSquared).clamp(0.0, 1.0);
    return (p - (a + delta * t)).distance;
  }
  bool near(Offset a, Offset b) {
    for (int i = 0; i < points.length; i++) {
      if (distance(points[i], a, b) <= tolerance) return true;
      if (i > 0 && (distance(a, points[i - 1], points[i]) <= tolerance ||
          distance(b, points[i - 1], points[i]) <= tolerance ||
          _segmentsCross(a, b, points[i - 1], points[i]))) {
        return true;
      }
    }
    return false;
  }
  if ([MarkTool.rectangle, MarkTool.callout].contains(mark.tool) && mark.points.length >= 2) {
    final box = Rect.fromPoints(scale(mark.points.first), scale(mark.points.last));
    return near(box.topLeft, box.topRight) || near(box.topRight, box.bottomRight) ||
      near(box.bottomRight, box.bottomLeft) || near(box.bottomLeft, box.topLeft);
  }
  final ink = <Offset>[];
  if (mark.points.length == 1) {
    ink.add(scale(mark.points.single));
  } else {
    for (final metric in smoothStrokePath(mark.points, size).computeMetrics()) {
      for (double offset = 0; offset < metric.length; offset += 4) {
        ink.add(metric.getTangentForOffset(offset)!.position);
      }
      final end = metric.getTangentForOffset(metric.length);
      if (end != null) {
        ink.add(end.position);
      }
    }
  }
  for (int i = 0; i < ink.length; i++) {
    if (near(ink[i], i == 0 ? ink[i] : ink[i - 1])) return true;
  }
  for (final stored in mark.rects) {
    final r = displayedMarkRect(mark, stored, size);
    final rect = Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height).inflate(radius);
    if (points.any(rect.contains) || near(rect.topLeft, rect.topRight) || near(rect.topRight, rect.bottomRight) ||
        near(rect.bottomRight, rect.bottomLeft) || near(rect.bottomLeft, rect.topLeft)) {
      return true;
    }
  }
  return false;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  double cross(Offset u, Offset v) => u.dx * v.dy - u.dy * v.dx;
  final denominator = cross(b - a, d - c);
  if (denominator.abs() < .000001) return false;
  final t = cross(c - a, d - c) / denominator;
  final u = cross(c - a, b - a) / denominator;
  return t >= 0 && t <= 1 && u >= 0 && u <= 1;
}

/// Quadratic midpoint interpolation keeps strokes smooth without moving endpoints.
Path smoothStrokePath(List<Offset> points, Size size) {
  final path = Path();
  if (points.isEmpty) return path;
  Offset scaled(Offset p) => Offset(p.dx * size.width, p.dy * size.height);
  final first = scaled(points.first);
  path.moveTo(first.dx, first.dy);
  for (int i = 1; i < points.length; i++) {
    final previous = scaled(points[i - 1]);
    final current = scaled(points[i]);
    final midpoint = (previous + current) / 2;
    path.quadraticBezierTo(previous.dx, previous.dy, midpoint.dx, midpoint.dy);
  }
  final last = scaled(points.last);
  path.lineTo(last.dx, last.dy);
  return path;
}

