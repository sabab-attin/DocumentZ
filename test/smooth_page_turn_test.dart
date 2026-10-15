import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/page_turn.dart';

import 'ebook_content_completeness_test.dart' as completeness;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'ordinary turns reuse the chapter tree, update the footer and retain line coverage',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AnnotationStore('smooth-turns');
      await store.load();
      final preferences = ReaderPreferences();
      final key = GlobalKey<EpubReaderState>();
      final book = EpubDocumentData('Long chapter', [
        EpubSection(
          'one.xhtml',
          'Long chapter',
          List.generate(
            100,
            (i) =>
                '<p style="text-indent:1em">Paragraph $i contains readable text and a complete ending.</p>',
          ).join(),
        ),
      ], const {});
      await completeness.openChapter(tester, key, store, preferences, book);
      final state = key.currentState!;
      final original = tester.widget<HtmlWidget>(find.byType(HtmlWidget).first);
      for (var i = 1; i <= 3; i++) {
        await state.turnSection(1);
        await tester.pumpAndSettle();
        expect(state.bookPages.page, i);
        expect(
          identical(
            original,
            tester.widget<HtmlWidget>(find.byType(HtmlWidget).first),
          ),
          isTrue,
          reason:
              'A page position update must not rebuild the whole HTML chapter.',
        );
        expect(
          find.text('Long chapter · ${i + 1} / ${state.bookPages.count}'),
          findsOneWidget,
        );
        completeness.expectCompletePageCoverage(tester, state);
      }
      final first = state.turnSection(1);
      final followUp = state.turnSection(1);
      await tester.pumpAndSettle();
      await first;
      await followUp;
      expect(state.bookPages.page, 5);
      final next = state.turnSection(1);
      final pending = state.turnSection(1);
      final reverse = state.turnSection(-1);
      await tester.pumpAndSettle();
      await next;
      await pending;
      await reverse;
      expect(
        state.bookPages.page,
        5,
        reason: 'Only the most recent follow-up direction is retained.',
      );
      preferences.setFontSize(26);
      await tester.pumpAndSettle();
      expect(
        identical(
          original,
          tester.widget<HtmlWidget>(find.byType(HtmlWidget).first),
        ),
        isFalse,
        reason:
            'Typography changes must still rebuild and repaginate the chapter.',
      );
      completeness.expectCompletePageCoverage(tester, state);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
      preferences.dispose();
    },
  );

  testWidgets(
    'animated turn changes the live page without waiting for image readback',
    (tester) async {
      final key = GlobalKey<PageTurnState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PageTurn(
              key: key,
              paper: Colors.white,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var changes = 0;
      final operation = key.currentState!.turn(1, () => changes++);
      expect(changes, 1);
      expect(key.currentState!.snapshot, isNotNull);
      await tester.pumpAndSettle();
      await operation;
      expect(key.currentState!.busy, isFalse);
      expect(key.currentState!.snapshot, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
