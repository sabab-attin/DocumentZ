import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/book_viewport.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/page_turn.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ebook_content_completeness_test.dart' as helpers;

class _LifecycleProbe extends StatefulWidget {
  const _LifecycleProbe(this.onDeactivate);
  final VoidCallback onDeactivate;
  @override
  State<_LifecycleProbe> createState() => _LifecycleProbeState();
}

class _LifecycleProbeState extends State<_LifecycleProbe> {
  @override
  void deactivate() {
    widget.onDeactivate();
    super.deactivate();
  }

  @override
  Widget build(BuildContext context) =>
      const Text('Selectable chapter stays mounted');
}

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Windows turns never deactivate and reactivate the live chapter',
    (tester) async {
      final key = GlobalKey<PageTurnState>();
      var deactivations = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: PageTurn(
            key: key,
            paper: Colors.white,
            child: _LifecycleProbe(() => deactivations++),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final turn = key.currentState!.turn(1, () {});
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(
          deactivations,
          0,
          reason:
              'Animation must not reparent every EditableText in a chapter.',
        );
        await tester.pumpAndSettle();
        await turn;
        expect(deactivations, 0);
      }
      await tester.pumpWidget(const SizedBox());
    },
    variant: windows,
  );

  testWidgets(
    'long EPUB paints and hit-tests only visible paragraphs while all content remains searchable and selectable',
    (tester) async {
      final prefs = ReaderPreferences();
      final store = AnnotationStore('visible-book');
      await store.load();
      final key = GlobalKey<EpubReaderState>();
      final markup = List.generate(
        160,
        (i) =>
            '<p>Paragraph $i: Select these words and keep every annotation.</p>',
      ).join();
      await helpers.openChapter(
        tester,
        key,
        store,
        prefs,
        EpubDocumentData('Large chapter', [
          EpubSection('c.xhtml', 'Chapter', markup),
        ], const {}),
      );
      final state = key.currentState!;
      final views = tester.allRenderObjects
          .whereType<RenderBookVisibility>()
          .toList();
      expect(views, hasLength(160));
      expect(views.where((v) => v.visible).length, lessThan(20));
      helpers.expectCompletePageCoverage(tester, state);
      final first = views.first;
      state.bookPages.jumpToPage(state.bookPages.count - 1);
      await tester.pumpAndSettle();
      expect(first.visible, isFalse);
      expect(views.last.visible, isTrue);
      expect(views.where((v) => v.visible).length, lessThan(20));
      state.bookPages.jumpToPage(state.bookPages.count - 2);
      await tester.pumpAndSettle();
      final paragraph = tester
          .elementList(find.byType(AnnotatedParagraph))
          .firstWhere((element) {
            final candidate = find.descendant(
              of: find.byWidget(element.widget),
              matching: find.byType(SelectableText),
            );
            final box = tester.getRect(candidate);
            return box.top >= 20 && box.bottom <= 520;
          });
      final text = find.descendant(
        of: find.byWidget(paragraph.widget),
        matching: find.byType(SelectableText),
      );
      final rect = tester.getRect(text);
      final original = tester.widget<SelectableText>(text);
      final mouse = await tester.startGesture(
        rect.topLeft + const Offset(4, 14),
        kind: PointerDeviceKind.mouse,
      );
      for (final x in [40.0, 90.0, 140.0, 180.0]) {
        await mouse.moveTo(rect.topLeft + Offset(x, 14));
        await tester.pump();
      }
      await mouse.up();
      await tester.pump();
      expect(identical(tester.widget<SelectableText>(text), original), isTrue);
      final editing = tester
          .state<EditableTextState>(
            find.descendant(of: text, matching: find.byType(EditableText)),
          )
          .textEditingValue;
      expect(editing.selection.isCollapsed, isFalse);
      expect(editing.selection.textInside(editing.text), isNotEmpty);
      expect(tester.takeException(), isNull);
      state.bookPages.jumpToPage(0);
      await tester.pumpAndSettle();
      expect(first.visible, isTrue);
      expect(views.last.visible, isFalse);
      helpers.expectCompletePageCoverage(tester, state);
      await helpers.selectMode(tester, state, 'Continuous');
      final continuous = tester.allRenderObjects
          .whereType<RenderBookVisibility>()
          .toList();
      expect(continuous, hasLength(160));
      expect(continuous.where((v) => v.visible).length, lessThan(20));
      state.scroll.jumpTo(state.scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(continuous.first.visible, isFalse);
      expect(continuous.last.visible, isTrue);
      expect(continuous.where((v) => v.visible).length, lessThan(20));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpWidget(const SizedBox());
      prefs.dispose();
      store.dispose();
    },
    variant: windows,
  );
}
