import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/text_alignment_menu.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'alignment persists and invalid stored values fall back to justified',
    () async {
      final preferences = await ReaderPreferences.load();
      await preferences.setAlignment(ReadingAlignment.justify);
      expect(
        (await ReaderPreferences.load()).alignment,
        ReadingAlignment.justify,
      );
      final store = await SharedPreferences.getInstance();
      await store.setString('readingAlignment', 'invalid');
      expect(
        (await ReaderPreferences.load()).alignment,
        ReadingAlignment.justify,
      );
    },
  );

  testWidgets(
    'EPUB has heading hierarchy and all four alignments update text',
    (tester) async {
      final preferences = ReaderPreferences();
      final annotations = AnnotationStore('layout');
      await annotations.load();
      addTearDown(annotations.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: preferences,
              builder: (_, _) => EpubReader(
                bytes: Future.value(Uint8List(0)),
                preferences: preferences,
                annotations: annotations,
                parsedDocument: Future.value(
                  const EpubDocumentData('Book', [
                    EpubSection(
                      'chapter.xhtml',
                      'Chapter',
                      '<h1>A chapter</h1><p>A paragraph with <em>emphasis</em> and room to read.</p>',
                    ),
                  ], {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final text = tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .toList();
      expect(
        text.first.style!.fontSize,
        greaterThan(text.last.style!.fontSize!),
      );
      for (final alignment in ReadingAlignment.values) {
        await preferences.setAlignment(alignment);
        await tester.pumpAndSettle();
        expect(
          tester
              .widgetList<SelectableText>(find.byType(SelectableText))
              .every((t) => t.textAlign == alignment.textAlign),
          isTrue,
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'sideways EPUB turns advance a viewport before changing chapters',
    (tester) async {
      final key = GlobalKey<EpubReaderState>();
      final annotations = AnnotationStore('paging');
      await annotations.load();
      addTearDown(annotations.dispose);
      final longChapter = List.filled(
        50,
        '<p>Words on a page, with enough paragraphs to fill several screens.</p>',
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
                annotations: annotations,
                parsedDocument: Future.value(
                  EpubDocumentData('Book', [
                    EpubSection('one.xhtml', 'One', longChapter),
                    const EpubSection(
                      'two.xhtml',
                      'Two',
                      '<p>Second chapter.</p>',
                    ),
                  ], {}),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState!;
      final viewport = state.scroll.position.viewportDimension;
      await state.turnSection(1);
      await tester.pumpAndSettle();
      expect(state.section, 0);
      expect(state.scroll.offset, closeTo(viewport, 1));
      await state.turnSection(-1);
      await tester.pumpAndSettle();
      expect(state.scroll.offset, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('alignment menu offers all four labeled choices', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextAlignmentMenu(preferences: ReaderPreferences()),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Text alignment'));
    await tester.pumpAndSettle();
    for (final alignment in ReadingAlignment.values) {
      expect(find.text(alignment.label), findsWidgets);
    }
  });
}
