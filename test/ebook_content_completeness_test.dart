import 'package:image/image.dart' as raster;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/book_viewport.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:shared_preferences/shared_preferences.dart';

String normalizedBody(String source) => (html.parse(source).body?.text ?? '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Read only the chapter's first layout tree, excluding app chrome and the
/// object-replacement characters Flutter uses to represent inline pictures.
String renderedChapterText(WidgetTester tester) {
  final leaf = tester.allRenderObjects.whereType<RenderBookLeaf>().firstWhere(
    (view) => view.column == 0,
  );
  final parts = <String>[];
  void visit(RenderObject object) {
    if (object is RenderEditable) {
      parts.add(object.text?.toPlainText(includePlaceholders: false) ?? '');
    } else if (object is RenderParagraph) {
      parts.add(object.text.toPlainText(includePlaceholders: false));
    }
    object.visitChildren(visit);
  }

  visit(leaf.child!);
  return parts.join(' ');
}

/// Independently compare every rendered text line with the union of page clips.
/// Finding a text widget alone does not prove its off-screen lines are readable.
void expectCompletePageCoverage(WidgetTester tester, EpubReaderState state) {
  final leaf = tester.allRenderObjects.whereType<RenderBookLeaf>().firstWhere(
    (view) => view.column == 0,
  );
  final lines = <Rect>[];
  void inspect(RenderObject object) {
    if (object is RenderEditable || object is RenderParagraph) {
      final span = object is RenderEditable
          ? object.text
          : (object as RenderParagraph).text;
      final text = span?.toPlainText() ?? '';
      if (text.isNotEmpty) {
        final range = TextSelection(baseOffset: 0, extentOffset: text.length);
        final boxes = object is RenderEditable
            ? object.getBoxesForSelection(range)
            : (object as RenderParagraph).getBoxesForSelection(range);
        final transform = object.getTransformTo(leaf.child);
        for (final box in boxes) {
          final rect = MatrixUtils.transformRect(transform, box.toRect());
          if (rect.height > .1 && rect.width > .1) {
            lines.add(rect);
          }
        }
      }
      object.visitChildren(inspect);
      return;
    }
    if (object is RenderBookAtomic) {
      final rect = MatrixUtils.transformRect(
        object.getTransformTo(leaf.child),
        Offset.zero & object.size,
      );
      expect(
        rect.height,
        lessThanOrEqualTo(leaf.size.height + .01),
        reason: 'Image exceeds its page height.',
      );
      lines.add(rect);
      return;
    }
    object.visitChildren(inspect);
  }

  inspect(leaf.child!);
  expect(lines, isNotEmpty);
  expect(state.bookPages.count, leaf.starts.length);
  for (final line in lines) {
    var covered = false;
    for (var i = 0; i < leaf.starts.length; i++) {
      final start = leaf.starts[i];
      final end = i + 1 < leaf.starts.length
          ? leaf.starts[i + 1]
          : start + leaf.size.height;
      if (line.top >= start - .75 && line.bottom <= end + .75) {
        covered = true;
        break;
      }
    }
    expect(
      covered,
      isTrue,
      reason:
          'Unreachable or clipped text line at $line; ${leaf.starts.length} pages, viewport ${leaf.size}.',
    );
  }
}

Future<void> openChapter(
  WidgetTester tester,
  GlobalKey<EpubReaderState> key,
  AnnotationStore store,
  ReaderPreferences preferences,
  EpubDocumentData book, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          disableAnimations: true,
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => EpubReader(
              key: key,
              bytes: Future.value(Uint8List(0)),
              parsedDocument: Future.value(book),
              preferences: preferences,
              annotations: store,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> selectMode(
  WidgetTester tester,
  EpubReaderState state,
  String mode,
) async {
  final changing = state.showDisplayModes();
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  if (mode == 'Continuous') {
    // Long continuous chapters parse in a real isolate. Fake-clock settling
    // cannot wait for that work and must not be used as an isolate completion.
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (!state.scroll.hasClients ||
          !state.scroll.position.hasContentDimensions ||
          state.scroll.position.maxScrollExtent <= 0) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('The complete continuous chapter did not load.');
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
  }
  await tester.pumpAndSettle();
  await changing;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final longParagraph in [false, true]) {
    testWidgets(
      'complete long chapter remains reachable, one paragraph: $longParagraph',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final text = List.generate(
          180,
          (i) => 'Complete sentence $i must stay available after a page turn.',
        ).join(' ');
        final body = longParagraph
            ? '<p>$text</p>'
            : List.generate(
                90,
                (i) => '<p>Paragraph $i. ${text.substring(0, 120)}</p>',
              ).join();
        final markup =
            '<div><div><h1>Introduction</h1>$body<p>FINAL_CONTENT_SENTINEL</p></div></div>';
        expect(markup.length, greaterThan(10000));
        expect(
          normalizedBody(prepareSelectableMarkup(markup)),
          normalizedBody(markup),
        );
        final store = AnnotationStore('completeness-$longParagraph');
        await store.load();
        final preferences = ReaderPreferences(autoHideControls: false);
        final key = GlobalKey<EpubReaderState>();
        await openChapter(
          tester,
          key,
          store,
          preferences,
          EpubDocumentData('Complete book', [
            EpubSection('intro.xhtml', 'Introduction', markup),
            const EpubSection(
              'next.xhtml',
              'Next section',
              '<p>NEXT_SECTION</p>',
            ),
          ], const {}),
        );
        final state = key.currentState!;
        expect(state.bookPages.count, greaterThan(3));
        expectCompletePageCoverage(tester, state);
        // Stop on the last page of this chapter before allowing a section change.
        while (state.bookPages.page + 1 < state.bookPages.count) {
          await state.turnSection(1);
          await tester.pump();
          expect(state.section, 0);
        }
        await tester.pumpAndSettle();
        final tail = tester.allRenderObjects
            .whereType<RenderEditable>()
            .firstWhere(
              (r) =>
                  r.text?.toPlainText().contains('FINAL_CONTENT_SENTINEL') ==
                  true,
            );
        final tailRect = tail.localToGlobal(Offset.zero) & tail.size;
        expect(
          tailRect.overlaps(Offset.zero & tester.view.physicalSize),
          isTrue,
        );
        await state.turnSection(1);
        await tester.pumpAndSettle();
        expect(state.section, 1);
        state.showSection(0);
        await tester.pumpAndSettle();
        await selectMode(tester, state, 'Dual page');
        expectCompletePageCoverage(tester, state);
        await preferences.setFontSize(28);
        await tester.pumpAndSettle();
        expectCompletePageCoverage(tester, state);
        tester.view.physicalSize = const Size(740, 420);
        await openChapter(
          tester,
          key,
          store,
          preferences,
          await state.document,
          scale: 1.5,
        );
        expectCompletePageCoverage(tester, state);
        await selectMode(tester, state, 'Continuous');
        expect(state.scroll.position.maxScrollExtent, greaterThan(0));
        state.scroll.jumpTo(state.scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        store.dispose();
        preferences.dispose();
      },
    );
  }

  testWidgets(
    'portrait keeps its full aspect ratio and never splits between pages',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final png = Uint8List.fromList(
        raster.encodePng(raster.Image(width: 240, height: 800)),
      );
      final store = AnnotationStore('whole-portrait');
      await store.load();
      final preferences = ReaderPreferences(autoHideControls: false);
      final key = GlobalKey<EpubReaderState>();
      await openChapter(
        tester,
        key,
        store,
        preferences,
        EpubDocumentData(
          'Portrait',
          [
            EpubSection(
              'picture.xhtml',
              'Picture',
              '<p>${List.filled(70, 'Text before the portrait.').join(' ')}</p><div><span><img src="portrait.png" /></span></div><p>AFTER_PORTRAIT</p>',
            ),
          ],
          {'portrait.png': png},
        ),
      );
      final state = key.currentState!;
      for (final mode in ['Single page', 'Dual page']) {
        if (mode != state.displayMode) {
          await selectMode(tester, state, mode);
        }
        expectCompletePageCoverage(tester, state);
        for (final image in tester.allRenderObjects.whereType<RenderImage>()) {
          expect(image.fit, BoxFit.contain);
          expect(
            image.size.width / image.size.height,
            closeTo(240 / 800, .001),
          );
        }
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  testWidgets(
    'nested aligned transforms paginate without reading sizes during layout',
    (tester) async {
      final pages = BookPageController();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookViewport(
              controller: pages,
              columns: 1,
              paper: Colors.white,
              layoutToken: 'transformed-content',
              builder: (column, height) => Transform.scale(
                scale: 1,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    90,
                    (i) =>
                        Text('Transformed paragraph $i must remain reachable.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(pages.ready, isTrue);
      expect(pages.count, greaterThan(1));
      expect(tester.takeException(), isNull);
      final count = pages.count;
      expect(pages.turn(1), isTrue);
      await tester.pumpAndSettle();
      expect(pages.page, 1);
      expect(pages.count, count);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      pages.dispose();
    },
  );

  final manifestPath = Platform.environment['DOCUMENTZ_EPUB_FIXTURES'];
  final paths = manifestPath == null
      ? <String>[]
      : (jsonDecode(File(manifestPath).readAsStringSync()) as List)
            .cast<String>();
  for (var bookIndex = 0; bookIndex < paths.length; bookIndex++) {
    final path = paths[bookIndex];
    testWidgets(
      'local EPUB $bookIndex preserves chapter text and paginates its long sections completely',
      (tester) async {
        tester.view.physicalSize = const Size(360, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final parsed = (await tester.runAsync(
          () async => parseEpub(await File(path).readAsBytes()),
        ))!;
        expect(parsed.sections, isNotEmpty);
        for (final chapter in parsed.sections) {
          expect(
            normalizedBody(prepareSelectableMarkup(chapter.html)),
            normalizedBody(chapter.html),
            reason: chapter.path,
          );
        }
        final longest = parsed.sections.reduce(
          (a, b) =>
              normalizedBody(a.html).length > normalizedBody(b.html).length
              ? a
              : b,
        );
        final introduction = parsed.sections
            .where((s) => s.html.contains('their bond ran'))
            .firstOrNull;
        final samples = {
          longest,
          ?introduction,
          parsed.sections.last,
          ...parsed.sections
              .where((s) => s.html.contains('<img') || s.html.contains('<svg'))
              .take(2),
        };
        for (final chapter in samples) {
          final expected = normalizedBody(chapter.html);
          if (expected.isEmpty &&
              !chapter.html.contains('<img') &&
              !chapter.html.contains('<svg')) {
            continue;
          }
          final store = AnnotationStore(
            'local-book-$bookIndex-${chapter.path}',
          );
          await store.load();
          final preferences = ReaderPreferences(autoHideControls: false);
          final key = GlobalKey<EpubReaderState>();
          await openChapter(
            tester,
            key,
            store,
            preferences,
            EpubDocumentData(parsed.title, [chapter], parsed.resources),
          );
          final state = key.currentState!;
          await tester.runAsync(() async {
            final deadline = DateTime.now().add(const Duration(seconds: 15));
            while (tester.allRenderObjects.whereType<RenderImage>().any(
              (image) => image.image == null,
            )) {
              if (DateTime.now().isAfter(deadline)) {
                throw TestFailure('Book image failed to decode.');
              }
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
          });
          await tester.pumpAndSettle();
          expectCompletePageCoverage(tester, state);
          final rendered = renderedChapterText(tester);
          final compactExpected = expected.replaceAll(RegExp(r'\s+'), '');
          final tail = compactExpected.substring(
            compactExpected.length > 60 ? compactExpected.length - 60 : 0,
          );
          expect(
            rendered.replaceAll(RegExp(r'\s+'), ''),
            contains(tail),
            reason: 'Chapter ending missing: ${chapter.path}',
          );
          await selectMode(tester, state, 'Dual page');
          expectCompletePageCoverage(tester, state);
          await tester.pumpWidget(const SizedBox.shrink());
          store.dispose();
          preferences.dispose();
        }
        expect(tester.takeException(), isNull);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  }
}
