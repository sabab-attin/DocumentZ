import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/data/readable_document.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/book_viewport.dart';

import 'package:documentz/features/epub_reader.dart';

import 'ebook_content_completeness_test.dart' as completeness;

const title = '''<html><head><style>
body {margin:0 5pt}
.preface {margin:0 2em}
.textbox {font-size:1em; text-align:center; padding:.5em 1em; border:black solid 2px; margin:0 9em 0 2em}
.center {font-size:1em; text-align:center; margin:0 0 0 1px}
.big {font-size:1.41667em}
</style></head><body><div class="preface"><div class="textbox"><p class="center"><span class="big">LETTERS</span><br><br><strong>TO</strong><br><br><span class="big">MILENA</span></p></div></div></body></html>''';

List<Finder> frames(WidgetTester tester) => [
  for (final widget in tester.widgetList<DecoratedBox>(
    find.byType(DecoratedBox),
  ))
    if (widget.decoration is BoxDecoration &&
        (widget.decoration as BoxDecoration).border is Border &&
        ((widget.decoration as BoxDecoration).border! as Border).left.width > 0)
      find.byWidget(widget),
];

void expectWordsIntact(WidgetTester tester, List<String> words) {
  final editable = tester.allRenderObjects
      .whereType<RenderEditable>()
      .firstWhere(
        (object) => words.every(
          (word) => (object.text?.toPlainText() ?? '').contains(word),
        ),
      );
  final text = editable.text!.toPlainText();
  for (final word in words) {
    final start = text.indexOf(word);
    final boxes = editable.getBoxesForSelection(
      TextSelection(baseOffset: start, extentOffset: start + word.length),
    );
    expect(boxes, isNotEmpty);
    for (final box in boxes) {
      expect(
        box.top,
        closeTo(boxes.first.top, .75),
        reason:
            '$word was broken across lines; editable width=${editable.size.width}, text=${editable.text}.',
      );
      expect(box.left, greaterThanOrEqualTo(-.75));
      expect(box.right, lessThanOrEqualTo(editable.size.width + .75));
    }
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('border declarations survive and framed paragraphs retain block IDs', () {
    const original =
        '<p id="notice" style="border:2px solid black;padding:1em;width:50%">Notice <a href="#target">link</a></p><p id="target">Target</p>';
    final tree = html.parse(prepareSelectableMarkup(original));
    final notice = tree.querySelector('#notice')!;
    expect(notice.attributes['data-qr-block'], '0');
    expect(notice.attributes['data-book-framed'], '1');
    expect(notice.parent!.attributes['style'], contains('border:'));
    expect(notice.querySelector('a')!.attributes['href'], '#target');
    expect(tree.querySelector('#target')!.attributes['data-qr-block'], '1');
    expect(tree.body!.text, 'Notice linkTarget');
  });

  test(
    'prepared dark frames use supported side shorthands and preserve accents',
    () {
      final tree = html.parse(
        prepareSelectableMarkup(
          '<div style="border:2px solid black"><p>Neutral</p></div>'
          '<div style="border:3px dashed red"><p>Accent</p></div>',
          frameInk: 'ffffff',
        ),
      );
      final neutral = tree
          .querySelectorAll('div')
          .firstWhere(
            (element) =>
                element.text == 'Neutral' &&
                (element.attributes['style'] ?? '').contains('border:'),
          );
      expect(
        neutral.attributes['style'],
        contains('border-left:2px solid #ffffff'),
      );
      final accent = tree
          .querySelectorAll('div')
          .firstWhere(
            (element) =>
                element.text == 'Accent' &&
                (element.attributes['style'] ?? '').contains('border:'),
          );
      expect(accent.attributes['style'], isNot(contains('#ffffff')));
    },
  );

  for (final format in [BookFormat.html, BookFormat.mhtml]) {
    test('$format preserves head styles and removes active content', () {
      const page =
          '<html><head><style>.notice {border:2px solid black}</style><script>bad()</script></head><body><p class="notice">Notice</p></body></html>';
      final source = format == BookFormat.html
          ? page
          : 'MIME-Version: 1.0\r\nContent-Type: multipart/related; boundary="parts"\r\n\r\n--parts\r\nContent-Type: text/html\r\n\r\n$page\r\n--parts--';
      final book = parseReadableDocument((
        format,
        Uint8List.fromList(utf8.encode(source)),
      ));
      final tree = html.parse(
        prepareSelectableMarkup(book.sections.single.html),
      );
      expect(
        tree.querySelector('.notice')!.parent!.attributes['style'],
        contains('border:'),
      );
      expect(tree.querySelectorAll('script'), isEmpty);
    });
  }

  for (final width in [240.0, 360.0, 600.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'title frame paints and words stay intact at width $width, dark $dark',
        (tester) async {
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
          });
          final store = AnnotationStore('box-$width-$dark');
          await store.load();
          final preferences = ReaderPreferences();
          if (width == 240) {
            preferences.setFontSize(18);
          }
          if (dark) {
            preferences.setPageDark(true);
          }
          final key = GlobalKey<EpubReaderState>();
          await completeness.openChapter(
            tester,
            key,
            store,
            preferences,
            EpubDocumentData('Title', [
              const EpubSection('title.xhtml', 'Title', title),
            ], const {}),
          );
          final borders = frames(tester);
          expect(
            borders,
            isNotEmpty,
            reason: 'The book border must become a painted decoration.',
          );
          final leaf = tester.allRenderObjects
              .whereType<RenderBookLeaf>()
              .first;
          final origin = leaf.localToGlobal(Offset.zero);
          for (final border in borders) {
            final rect = tester.getRect(border);
            expect(rect.left, greaterThanOrEqualTo(origin.dx - 1));
            expect(
              rect.right,
              lessThanOrEqualTo(origin.dx + leaf.size.width + 1),
            );
            final sides =
                ((tester.widget<DecoratedBox>(border).decoration
                            as BoxDecoration)
                        .border!
                    as Border);
            expect(
              sides.left.color.computeLuminance(),
              dark ? greaterThan(.8) : lessThan(.2),
            );
          }
          expectWordsIntact(tester, ['LETTERS', 'MILENA']);
          completeness.expectCompletePageCoverage(tester, key.currentState!);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          preferences.dispose();
        },
      );
    }
  }

  testWidgets(
    'nested frames, a framed paragraph and a table retain complete text with larger type and dual pages',
    (tester) async {
      tester.view.physicalSize = const Size(740, 520);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });
      final store = AnnotationStore('nested-boxes');
      await store.load();
      final preferences = ReaderPreferences();
      final key = GlobalKey<EpubReaderState>();
      final markup =
          '''<style>.outer {border:3px solid black; padding:1em; margin:0 7em}
      .inner {border:1px dashed red; padding:.5em; margin:0 2em}
      .notice {border:2px solid black; width:40%; margin:0 auto; padding:1em; background-color:white}
      td {border:1px solid black; padding:.3em}</style>
      <div class="outer"><div class="inner"><p>Nested box content remains available.</p></div></div>
      <p class="notice" lang="ar" dir="rtl">مرحبا بالعالم</p>
      <table><tr><td>First cell</td><td>Second cell</td></tr></table>
      ${List.filled(35, '<p>Complete paragraph after the framed content.</p>').join()}
      <p>FINAL_BOX_CONTENT</p>''';
      await completeness.openChapter(
        tester,
        key,
        store,
        preferences,
        EpubDocumentData('Boxes', [
          EpubSection('boxes.xhtml', 'Boxes', markup),
        ], const {}),
        scale: 1.3,
      );
      expect(frames(tester).length, greaterThanOrEqualTo(3));
      completeness.expectCompletePageCoverage(tester, key.currentState!);
      await completeness.selectMode(tester, key.currentState!, 'Dual page');
      completeness.expectCompletePageCoverage(tester, key.currentState!);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  final manifest = Platform.environment['DOCUMENTZ_EPUB_FIXTURES'];
  if (manifest != null && manifest.isNotEmpty) {
    testWidgets(
      'actual Letters to Milena title frame paints and title words stay complete',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
        });
        final fixture = await tester.runAsync(() async {
          final paths = (jsonDecode(
            await File(manifest).readAsString(),
          ) as List).cast<String>();
          final path = paths.firstWhere(
            (path) => path.toLowerCase().contains('milena'),
          );
          final book = parseEpub(await File(path).readAsBytes());
          final chapter = book.sections.firstWhere(
            (chapter) =>
                html.parse(chapter.html).querySelector('.textbox') != null,
          );
          return (book, chapter);
        });
        final (book, chapter) = fixture!;
        final store = AnnotationStore('real-milena-box');
        await store.load();
        final preferences = ReaderPreferences();
        final key = GlobalKey<EpubReaderState>();
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: capture,
              child: Scaffold(
                body: EpubReader(
                  key: key,
                  bytes: Future.value(Uint8List(0)),
                  preferences: preferences,
                  annotations: store,
                  parsedDocument: Future.value(
                    EpubDocumentData(book.title, [chapter], book.resources),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(frames(tester), isNotEmpty);
        expectWordsIntact(tester, ['LETTERS', 'MILENA']);
        completeness.expectCompletePageCoverage(tester, key.currentState!);
        final directory = Platform.environment['DOCUMENTZ_BOX_PREVIEWS'];
        if (directory != null && directory.isNotEmpty) {
          final boundary =
              capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            try {
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (bytes == null) {
                throw TestFailure('Could not encode the title-page preview.');
              }
              await Directory(directory).create(recursive: true);
              await File('$directory/milena-title-frame.png').writeAsBytes(
                bytes.buffer.asUint8List(
                  bytes.offsetInBytes,
                  bytes.lengthInBytes,
                ),
              );
            } finally {
              image.dispose();
            }
          });
        }
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        preferences.dispose();
      },
    );
  }
}
