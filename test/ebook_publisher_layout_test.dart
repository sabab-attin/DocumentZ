import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/data/mobi_document.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/book_paper.dart';
import 'package:documentz/features/book_viewport.dart';
import 'package:documentz/features/ebook_styles.dart';
import 'package:documentz/features/epub_reader.dart';

import 'ebook_content_completeness_test.dart' as completeness;
import 'mobi_document_test.dart' as mobi;

const source = '''<html lang="cs"><head><link rel="stylesheet" href="../styles/book.css"></head>
<body><h2 class="date"><em>[April 1920]</em></h2>
<p class="signature">With cordial greetings,<br>F Kafka</p>
<p class="indent">First paragraph. Příliš žluťoučký kůň.</p>
<p class="verse">First line\n  Second line<br>Third line</p>
<p dir="rtl" lang="ar">مرحبا بالعالم</p>
<p class="center"><b>LETTERS</b><br>TO<br>MILENA</p></body></html>''';
Map<String, Uint8List> get resources => {
  'styles/book.css': Uint8List.fromList(
    utf8.encode('''
@import "shared.css";
.date {font-size:1em; font-weight:normal; text-align:right; margin:0 1em 0 0}
.signature {text-align:right; margin:0 1em 0 0}
.indent {text-indent:1em; margin:0}
.verse {white-space:pre-wrap}
.center {text-align:center}
'''),
  ),
  'styles/shared.css': Uint8List.fromList(
    utf8.encode('body {text-align:justify}'),
  ),
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'local styles retain dates, signatures, indents, verse and language',
    () {
      final tree = html.parse(
        prepareSelectableMarkup(
          source,
          path: 'text/one.xhtml',
          resources: resources,
        ),
      );
      final date = tree.querySelector('.date')!;
      expect(ebookAlignment(date, TextAlign.left), TextAlign.right);
      final style = ebookTextStyle(
        date,
        const TextStyle(fontSize: 20),
        block: true,
      );
      expect(style.fontSize, 20);
      expect(style.fontWeight, FontWeight.normal);
      expect(
        ebookAlignment(tree.querySelector('.signature')!, TextAlign.left),
        TextAlign.right,
      );
      expect(
        ebookAlignment(tree.querySelector('.center')!, TextAlign.left),
        TextAlign.center,
      );
      expect(ebookStyle(tree.querySelector('.indent')!)['text-indent'], '1em');
      expect(
        paragraphRuns(tree.querySelector('.verse')!).map((r) => r.text).join(),
        'First line\n  Second line\nThird line',
      );
      final arabic = tree.querySelector('[dir=rtl]')!;
      expect(ebookDirection(arabic, TextDirection.ltr), TextDirection.rtl);
      expect(
        ebookTextStyle(arabic, const TextStyle()).locale?.languageCode,
        'ar',
      );
      expect(
        paragraphRuns(tree.querySelector('.indent')!).map((r) => r.text).join(),
        contains('Příliš žluťoučký kůň.'),
      );
      expect(tree.querySelectorAll('[data-qr-block]'), hasLength(6));
      expect(tree.querySelectorAll('script,link,style'), isEmpty);
    },
  );

  test('cascade respects specificity, important and inline styles without clipping', () {
    final markup = prepareSelectableMarkup(
      '''<style>
      #special {text-align:right}
      p {text-align:left!important; height:10px; overflow:hidden}
      p.indent {text-indent:2em}
      .indent {text-indent:1em}
      .unsupported:hover {font-weight:bold}
    </style><p id="special" class="indent" style="text-align:center">Complete text</p>''',
    );
    final paragraph = html.parse(markup).querySelector('p')!;
    expect(ebookAlignment(paragraph, TextAlign.justify), TextAlign.left);
    expect(ebookStyle(paragraph)['text-indent'], '2em');
    expect(paragraph.attributes['style'], isNot(contains('overflow')));
    expect(paragraph.attributes['style'], isNot(contains('height')));
    expect(paragraph.text, 'Complete text');
  });

  test('CSS values retain units and every shorthand component', () {
    final tree = html.parse(
      prepareSelectableMarkup('''<style>
      p {margin:1em 2em 3em 4em; font-size:125%; text-indent:12pt; width:50%; height:12px}
    </style><p>Styled paragraph</p>'''),
    );
    final paragraph = tree.querySelector('p')!;
    final values = ebookStyle(paragraph);
    expect(values['margin'], '1em 2em 3em 4em');
    expect(values['text-indent'], '12pt');
    expect(values['width'], '50%');
    expect(values['height'], '12px');
    expect(
      ebookTextStyle(paragraph, const TextStyle(fontSize: 20)).fontSize,
      25,
    );
    final insets = ebookParagraphInsets(paragraph, 20);
    expect(insets, const EdgeInsets.fromLTRB(80, 20, 40, 60));
    expect(ebookLength(values['text-indent'], 20), 20);
    expect(ebookLength(values['width'], 20, percent: 300), 150);
  });

  test('MOBI retains head styles, body language and legacy alignment', () {
    final book = parseMobi(
      mobi.fixtureMobi(
        '<html lang="cs"><head><style>.sign {text-align:right}</style></head><body><p class="sign">Kafka</p><p align="center">Letters</p></body></html>',
      ),
    );
    final section = book.sections.single;
    final tree = html.parse(
      prepareSelectableMarkup(
        section.html,
        path: section.path,
        resources: book.resources,
      ),
    );
    expect(
      ebookAlignment(tree.querySelector('.sign')!, TextAlign.justify),
      TextAlign.right,
    );
    expect(
      ebookAlignment(tree.querySelector('[align]')!, TextAlign.justify),
      TextAlign.center,
    );
    expect(tree.querySelector('.sign')!.attributes['data-book-lang'], 'cs');
  });

  testWidgets('visual first-line indent retains original annotation offsets', (
    tester,
  ) async {
    final store = AnnotationStore('publisher-indent');
    await store.load();
    final element = html
        .parse(
          prepareSelectableMarkup(
            '<p style="text-indent:1em">First second third</p>',
          ),
        )
        .querySelector('p')!;
    Future<void> Function(MarkTool)? annotate;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotatedParagraph(
            element: element,
            block: 'one:0',
            anchor: 'chapter:1',
            store: store,
            style: const TextStyle(fontSize: 20),
            onSelection: (action) => annotate = action,
            onLink: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.textSpan!.toPlainText(), '\u200aFirst second third');
    text.onSelectionChanged!(
      const TextSelection(baseOffset: 1, extentOffset: 6),
      SelectionChangedCause.longPress,
    );
    await annotate!(MarkTool.highlight);
    await tester.pumpAndSettle();
    expect(store.marks.single.start, 0);
    expect(store.marks.single.end, 5);
    expect(store.marks.single.quote, 'First');
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
    'all lines fit outside chrome before and after viewport and text scaling changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(360, 740);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final store = AnnotationStore('publisher-viewport');
      await store.load();
      final preferences = ReaderPreferences();
      final key = GlobalKey<EpubReaderState>();
      final book = EpubDocumentData('Letters', [
        EpubSection(
          'text/one.xhtml',
          'Letters',
          source +
              List.filled(
                60,
                '<p>Every line remains readable outside fullscreen.</p>',
              ).join(),
        ),
      ], resources);
      await completeness.openChapter(tester, key, store, preferences, book);
      final state = key.currentState!;
      void check() {
        completeness.expectCompletePageCoverage(tester, state);
        final leaf = tester.allRenderObjects.whereType<RenderBookLeaf>().first;
        final rect = tester.getRect(
          find.byWidgetPredicate((w) => w is BookViewport),
        );
        final top = leaf.localToGlobal(Offset.zero).dy;
        expect(top, greaterThanOrEqualTo(rect.top + 64));
        expect(top + leaf.size.height, lessThanOrEqualTo(rect.bottom - 40));
      }

      check();
      tester.view.physicalSize = const Size(740, 360);
      await tester.pumpAndSettle();
      check();
      preferences.setFontSize(28);
      await completeness.openChapter(
        tester,
        key,
        store,
        preferences,
        book,
        scale: 1.5,
      );
      check();
      await completeness.selectMode(tester, state, 'Dual page');
      check();
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'ebook paper is visible and leaves page actions accessible: $dark',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 360,
              height: 740,
              child: BookPaper(
                paper: dark ? Colors.black : Colors.white,
                child: Center(
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('Page link'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Page link'));
        expect(taps, 1);
        expect(find.byType(CustomPaint), findsWidgets);
        expect(tester.takeException(), isNull);
      },
    );
  }

  final manifest = Platform.environment['DOCUMENTZ_EPUB_FIXTURES'];
  if (manifest != null && manifest.isNotEmpty) {
    test(
      'supplied books retain source text and publisher paragraph styles',
      () async {
        final paths = (jsonDecode(await File(manifest).readAsString()) as List)
            .cast<String>();
        var rightAligned = 0, indented = 0, centered = 0;
        for (final path in paths) {
          final book = parseEpub(await File(path).readAsBytes());
          for (final chapter in book.sections) {
            final prepared = html.parse(
              prepareSelectableMarkup(
                chapter.html,
                path: chapter.path,
                resources: book.resources,
              ),
            );
            String plain(String text) => text.replaceAll(RegExp(r'\s+'), '');
            expect(
              plain(prepared.body!.text),
              plain(html.parse(chapter.html).body!.text),
              reason: chapter.path,
            );
            for (final paragraph in prepared.querySelectorAll(
              '[data-qr-block]',
            )) {
              final align = ebookAlignment(paragraph, TextAlign.start);
              if (align == TextAlign.right) {
                rightAligned++;
              }
              if (align == TextAlign.center) {
                centered++;
              }
              if (ebookLength(ebookStyle(paragraph)['text-indent'], 20) > 0) {
                indented++;
              }
            }
          }
        }
        expect(rightAligned, greaterThan(10));
        expect(indented, greaterThan(10));
        expect(centered, greaterThan(10));
      },
    );
  }
}
