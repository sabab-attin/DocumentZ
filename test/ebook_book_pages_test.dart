import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/epub_reader.dart';

Future<void> chooseMode(
  WidgetTester tester,
  EpubReaderState state,
  String mode,
) async {
  final choosing = state.showDisplayModes();
  await tester.pumpAndSettle();
  await tester.tap(find.text(mode).last);
  await tester.pumpAndSettle();
  await choosing;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'single and double ebook pages do not vertically scroll; continuous does',
    (tester) async {
      final store = AnnotationStore('physical-pages');
      await store.load();
      final key = GlobalKey<EpubReaderState>();
      final preferences = ReaderPreferences();
      final content = List.filled(
        40,
        '<p>A printed page keeps each line together and turns one page at a time.</p>',
      ).join();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: EpubReader(
                key: key,
                bytes: Future.value(Uint8List(0)),
                preferences: preferences,
                annotations: store,
                parsedDocument: Future.value(
                  EpubDocumentData('Book', [
                    EpubSection('one.xhtml', 'One', content),
                  ], const {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      expect(state.displayMode, 'Single page');
      expect(state.scroll.hasClients, isFalse);
      expect(state.bookPages.count, greaterThan(2));
      await state.turnSection(1);
      await tester.pumpAndSettle();
      expect(state.bookPages.page, 1);
      await chooseMode(tester, state, 'Dual page');
      expect(state.scroll.hasClients, isFalse);
      expect(state.bookPages.columns, 2);
      final before = state.bookPages.page;
      await state.turnSection(1);
      await tester.pumpAndSettle();
      expect(state.bookPages.page, before + 2);
      await chooseMode(tester, state, 'Continuous');
      expect(state.scroll.hasClients, isTrue);
      expect(state.scroll.position.maxScrollExtent, greaterThan(0));
      final initial = state.scroll.offset;
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -150),
      );
      await tester.pumpAndSettle();
      expect(state.scroll.offset, greaterThan(initial));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );
  testWidgets(
    'tapping an ebook reference reveals the target page and preserves annotations',
    (tester) async {
      final store = AnnotationStore('book-reference');
      await store.load();
      final key = GlobalKey<EpubReaderState>();
      final filler = List.filled(
        45,
        '<p>Filler text before a note on a later page.</p>',
      ).join();
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Scaffold(
              body: EpubReader(
                key: key,
                bytes: Future.value(Uint8List(0)),
                preferences: ReaderPreferences(),
                annotations: store,
                parsedDocument: Future.value(
                  EpubDocumentData('Book', [
                    const EpubSection(
                      'one.xhtml',
                      'One',
                      '<p><a href="notes.xhtml#note-1">Go to note</a></p>',
                    ),
                    EpubSection(
                      'notes.xhtml',
                      'Notes',
                      '$filler<p id="note-1">Footnote destination</p>',
                    ),
                  ], const {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final editable = tester.state<EditableTextState>(
        find.byWidgetPredicate(
          (w) => w is EditableText && w.controller.text == 'Go to note',
        ),
      );
      final render = editable.renderEditable;
      final box = render
          .getBoxesForSelection(
            const TextSelection(baseOffset: 0, extentOffset: 10),
          )
          .first;
      await tester.tapAt(render.localToGlobal(box.toRect().center));
      await tester.pumpAndSettle();
      expect(key.currentState!.section, 1);
      expect(key.currentState!.bookPages.page, greaterThan(0));
      expect(store.marks, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );
}
