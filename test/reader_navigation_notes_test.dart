import 'package:documentz/features/reader.dart';
import 'package:documentz/domain/book.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/reader_controls.dart';

void main() {
  testWidgets('the menu can still be tapped after the header hides', (
    tester,
  ) async {
    final preferences = ReaderPreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: const Book(
            id: 'sample',
            title: 'Title',
            format: BookFormat.txt,
            text: 'Document text',
          ),
          preferences: preferences,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    final touch = await tester.startGesture(
      tester.getCenter(find.byTooltip('Open reading menu')),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await touch.up();
    await tester.pump();
    expect(find.byTooltip('Close reading menu'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'idle controls hide, interaction restores them and holding prevents hiding',
    (tester) async {
      final chrome = ReaderChrome();
      addTearDown(chrome.dispose);
      chrome.activity();
      await tester.pump(const Duration(seconds: 4));
      expect(chrome.value, false);
      chrome.activity();
      expect(chrome.value, true);
      chrome.hold();
      await tester.pump(const Duration(seconds: 10));
      expect(chrome.value, true);
    },
  );

  test('reader controls persist independently', () async {
    final preferences = await ReaderPreferences.load();
    await preferences.setReaderControls(
      autoHide: false,
      pageButtons: true,
      pageIndicator: false,
    );
    final restored = await ReaderPreferences.load();
    expect(restored.autoHideControls, false);
    expect(restored.showPageButtons, true);
    expect(restored.showPageIndicator, false);
    preferences.dispose();
    restored.dispose();
  });

  test(
    'image attachments and placed text survive reload and moving can be undone',
    () async {
      final image = prepareNoteImage(
        Uint8List.fromList(img.encodePng(img.Image(width: 3, height: 3))),
      );
      expect(img.decodeImage(base64Decode(image)), isNotNull);
      final store = AnnotationStore('attachments');
      await store.load();
      await store.add(
        DocumentMark(
          anchor: 'page:1',
          tool: MarkTool.note,
          text: 'Image note',
          attachments: [image],
        ),
      );
      final text = DocumentMark(
        anchor: 'page:1',
        tool: MarkTool.text,
        text: 'Placed text',
        font: 'monospace',
        fontSize: 32,
        rects: [const Rect.fromLTWH(.1, .2, .3, .15)],
        color: 0xff1565c0,
      );
      await store.add(text);
      final moved = DocumentMark.fromJson({
        ...text.toJson(),
        'rects': [
          [.2, .3, .5, .45],
        ],
      });
      await store.replace(text, moved);
      expect(store.marks.last.rects.first.left, .2);
      await store.undo('page:1');
      expect(store.marks.last.rects.first.left, .1);
      final restored = AnnotationStore('attachments');
      await restored.load();
      expect(restored.marks.first.attachments, [image]);
      expect(restored.marks.last.font, 'monospace');
      expect(restored.marks.last.fontSize, 32);
      store.dispose();
      restored.dispose();
    },
  );

  test('a grouped note remains discoverable on every affected page', () async {
    final store = AnnotationStore('cross-page');
    await store.load();
    await store.addMany([
      DocumentMark(
        anchor: 'page:1',
        tool: MarkTool.note,
        text: 'Shared note',
        group: 'selection',
      ),
      DocumentMark(
        anchor: 'page:2',
        tool: MarkTool.note,
        text: 'Shared note',
        group: 'selection',
      ),
    ]);
    expect(pageNoteEntries(store, 'page:1'), hasLength(1));
    expect(pageNoteEntries(store, 'page:2'), hasLength(1));
    store.dispose();
  });

  testWidgets('page indicator opens notes with their selected quote and body', (
    tester,
  ) async {
    final store = AnnotationStore('visible-notes');
    await store.load();
    await store.add(
      DocumentMark(
        anchor: 'page:1',
        tool: MarkTool.note,
        text: 'Remember this',
        quote: 'Selected portion',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PageNotesButton(store: store, anchor: 'page:1'),
        ),
      ),
    );
    await tester.tap(find.text('Notes (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Remember this'), findsOneWidget);
    expect(find.text('Selected portion'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
    'find lists every paragraph match and next moves between chapters without saving highlights',
    (tester) async {
      final key = GlobalKey<EpubReaderState>();
      final store = AnnotationStore('find');
      await store.load();
      final preferences = ReaderPreferences(showPageIndicator: false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EpubReader(
              key: key,
              bytes: Future.value(Uint8List(0)),
              preferences: preferences,
              annotations: store,
              parsedDocument: Future.value(
                const EpubDocumentData('Book', [
                  EpubSection(
                    'one.xhtml',
                    'One',
                    '<p>Target first. Target again.</p>',
                  ),
                  EpubSection('two.xhtml', 'Two', '<p>Target elsewhere.</p>'),
                ], {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final searching = key.currentState!.searchDocument();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'target');
      await tester.pumpAndSettle();
      expect(find.text('3 matches'), findsOneWidget);
      await tester.tap(find.text('One').first);
      await tester.pumpAndSettle();
      await searching;
      expect(find.text('1 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect(key.currentState!.section, 1);
      expect(find.text('3 / 3'), findsOneWidget);
      expect(store.marks, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
      store.dispose();
    },
  );
}
