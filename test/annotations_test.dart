import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:html/parser.dart' as html;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/core/themes.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/features/library.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/text_mark_geometry.dart';
import 'package:documentz/features/reader_gestures.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shape erasing hits rectangle edges rather than its diagonal', () {
    final mark = DocumentMark(anchor: 'page:1', tool: MarkTool.rectangle, points: const [Offset(.1, .1), Offset(.9, .9)]);
    expect(strokeHitsMark(mark, const [Offset(.5, .1)], const Size(200, 200), 3), isTrue);
    expect(strokeHitsMark(mark, const [Offset(.5, .5)], const Size(200, 200), 3), isFalse);
  });

  test('selected characters cover full wrapped lines and keep partial endpoints exact', () {
    final rects = selectedCharacterLines(const [
      Rect.fromLTRB(.12, .1, .14, .13),
      Rect.fromLTRB(.14, .1, .16, .13),
      Rect.zero,
      Rect.fromLTRB(.18, .1, .2, .13),
      Rect.zero,
      Rect.fromLTRB(.1, .16, .12, .19),
      Rect.fromLTRB(.12, .16, .14, .19),
    ], 'ab c\nde');
    expect(rects, const [Rect.fromLTRB(.12, .1, .2, .13), Rect.fromLTRB(.1, .16, .14, .19)]);
    final wrapped = selectedCharacterLines(const [
      Rect.fromLTRB(.1, .1, .12, .13), Rect.fromLTRB(.1, .14, .12, .17),
    ], 'ab');
    expect(wrapped, hasLength(2));
    final rtl = selectedCharacterLines(const [
      Rect.fromLTRB(.2, .1, .22, .13), Rect.fromLTRB(.18, .1, .2, .13),
    ], 'ab');
    expect(rtl.single, const Rect.fromLTRB(.18, .1, .22, .13));
  });

  test('stroke eraser hits crossed segments, preserves other pages, and undo restores ink', () async {
    final store = AnnotationStore('erase');
    await store.load();
    await store.add(DocumentMark(anchor: 'page:1', tool: MarkTool.pen,
      color: 0xffc62828, width: .012, points: const [Offset(.1, .5), Offset(.9, .5)]));
    await store.add(DocumentMark(anchor: 'page:2', tool: MarkTool.pen, points: const [Offset(.5, .5)]));
    await store.eraseStroke('page:1', const [Offset(.5, .1), Offset(.5, .9)], const Size(200, 400), 5);
    expect(store.marks.single.anchor, 'page:2');
    await store.undo('page:1');
    final restored = AnnotationStore('erase');
    await restored.load();
    final ink = restored.marks.singleWhere((m) => m.anchor == 'page:1');
    expect(ink.color, 0xffc62828);
    expect(ink.width, .012);
    expect(ink.points, const [Offset(.1, .5), Offset(.9, .5)]);
    await store.undo('page:1');
    expect(store.marks.single.anchor, 'page:2');
  });

  test('undo of a multi-page mark preserves later work on another page', () async {
    final store = AnnotationStore('group-history');
    await store.load();
    await store.addMany([
      DocumentMark(anchor: 'page:1', tool: MarkTool.highlight, group: 'selection'),
      DocumentMark(anchor: 'page:2', tool: MarkTool.highlight, group: 'selection'),
    ]);
    await store.add(DocumentMark(anchor: 'page:2', tool: MarkTool.note, text: 'Keep this note'));
    await store.undo('page:1');
    expect(store.marks.single.text, 'Keep this note');
    await store.undo('page:2');
    expect(store.marks, isEmpty);
  });

  testWidgets('drawing uses chosen color and size and erasing can be undone', (tester) async {
    final store = AnnotationStore('styled-draw');
    await store.load();
    Future<void> show(MarkTool tool) => tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 200, height: 400,
      child: PageMarks(store: store, anchor: 'page:1', tool: tool, color: 0xff7b1fa2, width: .015,
        dark: false, onTouched: () {})))));
    await show(MarkTool.pen);
    final origin = tester.getTopLeft(find.byType(PageMarks));
    final pen = await tester.startGesture(origin + const Offset(20, 200), kind: PointerDeviceKind.stylus);
    await pen.moveTo(origin + const Offset(180, 200));
    await pen.up();
    await tester.pumpAndSettle();
    expect(store.marks.single.color, 0xff7b1fa2);
    expect(store.marks.single.width, .015);
    await show(MarkTool.eraser);
    final eraser = await tester.startGesture(origin + const Offset(100, 100), kind: PointerDeviceKind.stylus);
    await eraser.moveTo(origin + const Offset(100, 300));
    await eraser.up();
    await tester.pumpAndSettle();
    expect(store.marks, isEmpty);
    await store.undo('page:1');
    expect(store.marks.single.color, 0xff7b1fa2);
  });

  test('bookmarks persist and annotation undo does not remove them', () async {
    final store = AnnotationStore('bookmarks');
    await store.load();
    await store.add(DocumentMark(anchor: 'page:4', tool: MarkTool.pen, points: const [Offset(.1, .2)]));
    await store.add(DocumentMark(anchor: 'page:4', tool: MarkTool.bookmark, text: 'Page 4'));
    await store.undo('page:4');
    final restored = AnnotationStore('bookmarks');
    await restored.load();
    expect(restored.marks.single.tool, MarkTool.bookmark);
    expect(restored.marks.single.anchor, 'page:4');
  });

  test('smooth strokes preserve the endpoints', () {
    final path = smoothStrokePath(const [Offset(.1, .1), Offset(.5, .8), Offset(.9, .1)], const Size(100, 100));
    final metric = path.computeMetrics().single;
    expect(metric.getTangentForOffset(0)!.position.dx, closeTo(10, .01));
    expect(metric.getTangentForOffset(metric.length)!.position.dx, closeTo(90, .01));
    expect(metric.getTangentForOffset(metric.length)!.position.dy, closeTo(10, .01));
  });

  testWidgets('freehand highlight marks images without a text selection', (tester) async {
    final store = AnnotationStore('image-highlight');
    await store.load();
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 200, height: 400,
      child: PageMarks(store: store, anchor: 'page:1', tool: MarkTool.highlight, dark: false, onTouched: () {})))));
    final origin = tester.getTopLeft(find.byType(PageMarks));
    final gesture = await tester.startGesture(origin + const Offset(20, 40), kind: PointerDeviceKind.stylus);
    await gesture.moveTo(origin + const Offset(100, 80));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.marks.single.tool, MarkTool.highlight);
    expect(store.marks.single.points.last.dx, closeTo(.5, .01));
  });

  test('annotations persist by document and undo stays on its page', () async {
    final store = AnnotationStore('one');
    await store.load();
    await store.add(DocumentMark(anchor: 'page:1', tool: MarkTool.pen, points: const [Offset(.1, .2), Offset(.3, .4)]));
    await store.add(DocumentMark(anchor: 'page:2', tool: MarkTool.note, text: 'Remember this'));
    await store.undo('page:1');
    final restored = AnnotationStore('one');
    await restored.load();
    expect(restored.marks.single.text, 'Remember this');
    expect(restored.marks.single.anchor, 'page:2');
    final other = AnnotationStore('two');
    await other.load();
    expect(other.marks, isEmpty);
  });

  test('signature stamps undo as a whole; rapid saves retain the latest state', () async {
    final store = AnnotationStore('signature');
    await store.load();
    await store.addMany([
      DocumentMark(anchor: 'page:1', tool: MarkTool.signature, group: 'stamp', points: const [Offset(.1, .1)]),
      DocumentMark(anchor: 'page:1', tool: MarkTool.signature, group: 'stamp', points: const [Offset(.2, .2)]),
    ]);
    await store.undo('page:1');
    final first = store.add(DocumentMark(anchor: 'chapter:1', tool: MarkTool.note, text: 'First'));
    final second = store.add(DocumentMark(anchor: 'chapter:2', tool: MarkTool.note, text: 'Second'));
    await Future.wait([first, second]);
    final restored = AnnotationStore('signature');
    await restored.load();
    expect(restored.marks.map((m) => m.text), ['First', 'Second']);
  });

  test('removed Night preference migrates to Dark and page darkness persists separately', () async {
    SharedPreferences.setMockInitialValues({'theme': 'night'});
    final prefs = await ReaderPreferences.load();
    expect(prefs.theme, ReaderTheme.dark);
    await prefs.setPageDark(true);
    await prefs.setTheme(ReaderTheme.kawaii);
    final restored = await ReaderPreferences.load();
    expect(restored.theme, ReaderTheme.kawaii);
    expect(restored.pageDark, true);
    expect(ReaderTheme.values.length, 4);
  });

  testWidgets('library has no sample or placeholder cards', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: LibraryScreen(
      repository: BrowserLibrary(), preferences: ReaderPreferences()))));
    await tester.pumpAndSettle();
    expect(find.text('Your library is empty.'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.text('Add document'), findsOneWidget);
  });

  testWidgets('drawing saves page coordinates independently of displayed size', (tester) async {
    final store = AnnotationStore('draw');
    await store.load();
    await tester.pumpWidget(MaterialApp(home: Center(child: SizedBox(width: 200, height: 400,
      child: PageMarks(store: store, anchor: 'page:3', tool: MarkTool.pen, dark: false, onTouched: () {})))));
    final top = tester.getTopLeft(find.byType(PageMarks));
    final gesture = await tester.startGesture(top + const Offset(20, 40), kind: PointerDeviceKind.stylus);
    await gesture.moveTo(top + const Offset(100, 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(store.marks.single.anchor, 'page:3');
    expect(store.marks.single.points.last.dx, closeTo(.5, .01));
    expect(store.marks.single.points.last.dy, closeTo(.5, .01));
  });

  testWidgets('one finger draws immediately; two fingers cancel ink and scroll', (tester) async {
    final store = AnnotationStore('scroll');
    await store.load();
    final scroll = ScrollController();
    final session = ReaderGestureSession();
    addTearDown(scroll.dispose);
    addTearDown(session.dispose);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ReaderGestureSurface(session: session, active: true,
      onNavigate: (delta, focal, scale) => scroll.jumpTo((scroll.offset - delta.dy).clamp(0, scroll.position.maxScrollExtent)),
      child: SingleChildScrollView(controller: scroll, physics: const NeverScrollableScrollPhysics(),
        child: SizedBox(height: 1800, child: PageMarks(store: store, anchor: 'page:1', tool: MarkTool.pen,
          gestureSession: session, dark: false, onTouched: () {})))))));
    await tester.dragFrom(const Offset(400, 400), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scroll.offset, 0);
    expect(store.marks, hasLength(1));
    await store.undo('page:1');
    final first = await tester.startGesture(const Offset(300, 400), pointer: 1);
    await first.moveBy(const Offset(0, -20));
    final second = await tester.startGesture(const Offset(450, 400), pointer: 2);
    await first.moveBy(const Offset(0, -100));
    await second.moveBy(const Offset(0, -100));
    await second.up();
    await first.moveBy(const Offset(20, -20));
    await first.up();
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(store.marks, isEmpty);
    await tester.dragFrom(const Offset(400, 400), const Offset(40, -100));
    await tester.pumpAndSettle();
    expect(store.marks, hasLength(1));
  });

  test('line geometry and selected quotes survive save and reload', () async {
    final store = AnnotationStore('lines');
    await store.load();
    await store.add(DocumentMark(anchor: 'page:2', tool: MarkTool.underline, quote: 'Two lines',
      rects: const [Rect.fromLTRB(.1, .2, .8, .23), Rect.fromLTRB(.1, .25, .4, .28)], start: 2, end: 11));
    final restored = AnnotationStore('lines');
    await restored.load();
    expect(restored.marks.single.rects, hasLength(2));
    expect(restored.marks.single.quote, 'Two lines');
    expect(restored.marks.single.rects.last.bottom, .28);
  });

  test('EPUB marks preserve paragraph styles and overlapping exact ranges', () {
    final element = html.parseFragment('<p>Hello <strong>world</strong> again</p>').children.single;
    final runs = paragraphRuns(element);
    final spans = markedParagraphSpans(runs, [
      DocumentMark(anchor: 'chapter:1', block: 'p1', tool: MarkTool.highlight, start: 6, end: 11, quote: 'world'),
      DocumentMark(anchor: 'chapter:1', block: 'p1', tool: MarkTool.underline, start: 6, end: 11, quote: 'world'),
      DocumentMark(anchor: 'chapter:1', block: 'p1', tool: MarkTool.strikethrough, start: 6, end: 11, quote: 'world'),
    ]);
    expect(spans.map((s) => s.text).join(), 'Hello world again');
    final marked = spans.singleWhere((s) => s.text == 'world');
    expect(marked.style!.fontWeight, FontWeight.bold);
    expect(marked.style!.backgroundColor, isNotNull);
    expect(marked.style!.decoration!.contains(TextDecoration.underline), true);
    expect(marked.style!.decoration!.contains(TextDecoration.lineThrough), true);
    final changed = markedParagraphSpans(runs, [DocumentMark(anchor: 'chapter:1', tool: MarkTool.highlight, start: 6, end: 11, quote: 'other')]);
    expect(changed.every((s) => s.style?.backgroundColor == null), true);
  });
}
