import 'package:documentz/core/preferences.dart';
import 'package:documentz/core/reader_shortcuts.dart';
import 'package:documentz/data/epub_document.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/book_viewport.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:documentz/features/selection_panel.dart';
import 'package:documentz/features/keyboard_shortcuts_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ebook_content_completeness_test.dart' as helpers;

void main() {
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> chord(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = true,
  }) async {
    if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
  }

  test('shortcut edits persist, reject conflicts and preserve copy/paste and system keys', () async {
    final prefs = await SharedPreferences.getInstance();
    final keys = ReaderShortcuts(prefs);
    expect(
      await keys.setBinding(
        ReaderCommand.undo,
        const ReaderKey(0x79, control: true),
      ),
      isTrue,
    );
    expect(
      await keys.setBinding(
        ReaderCommand.find,
        keys.binding(ReaderCommand.undo),
      ),
      isFalse,
    );
    expect(
      await keys.setBinding(
        ReaderCommand.find,
        ReaderKey(LogicalKeyboardKey.keyC.keyId, control: true),
      ),
      isFalse,
    );
    expect(
      await keys.setBinding(
        ReaderCommand.find,
        ReaderKey(LogicalKeyboardKey.f4.keyId, alt: true),
      ),
      isFalse,
    );
    final reload = ReaderShortcuts(prefs);
    expect(reload.binding(ReaderCommand.undo).label, 'Ctrl+Y');
    await reload.reset();
    expect(reload.binding(ReaderCommand.undo), ReaderCommand.undo.defaultKey);
    keys.dispose();
    reload.dispose();
  });
  testWidgets(
    'toolbar icons share keyboard undo/save/search, remain usable when hidden, and leave editing alone',
    (tester) async {
      final prefs = ReaderPreferences(
        store: await SharedPreferences.getInstance(),
      );
      final menu = ValueNotifier(false), visible = ValueNotifier(true);
      final store = AnnotationStore('toolbar-shortcuts', deferred: true);
      await store.load();
      final field = FocusNode();
      var searches = 0;
      await store.add(
        DocumentMark(anchor: 'page:1', tool: MarkTool.highlight, quote: 'mark'),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderControlsScope(
              expanded: menu,
              preferences: prefs,
              desktopToolbar: visible,
              child: ReaderControlsOverlay(
                controls: ListenableBuilder(
                  listenable: store,
                  builder: (context, _) => ReaderMenuGrid(
                    children: [
                      ReaderMenuAction(
                        label: 'Undo',
                        icon: Icons.undo,
                        onTap: store.canUndo('page:1')
                            ? () => store.undo('page:1')
                            : null,
                      ),
                      ReaderMenuAction(
                        label: 'Save annotations',
                        icon: Icons.save_outlined,
                        onTap: store.commit,
                      ),
                      ReaderMenuAction(
                        label: 'Find in document',
                        icon: Icons.search,
                        onTap: () => searches++,
                      ),
                    ],
                  ),
                ),
                child: Column(
                  children: [
                    TextField(focusNode: field),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Find in document'), findsNothing);
      await tester.tap(find.byTooltip('Find in document'));
      expect(searches, 1);
      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(store.marks, isEmpty);
      await store.add(
        DocumentMark(anchor: 'page:1', tool: MarkTool.note, text: 'keep'),
      );
      await tester.pump();
      field.requestFocus();
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Note text');
      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(
        store.marks,
        hasLength(1),
        reason: 'Typing undo must not remove an annotation.',
      );
      field.unfocus();
      await tester.pump();
      await chord(tester, LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      final persisted = AnnotationStore('toolbar-shortcuts');
      await persisted.load();
      expect(persisted.marks.single.text, 'keep');
      visible.value = false;
      await tester.pump();
      expect(find.byTooltip('Find in document').hitTestable(), findsNothing);
      await chord(tester, LogicalKeyboardKey.keyF);
      expect(searches, 2);
      await prefs.shortcuts.setBinding(
        ReaderCommand.undo,
        ReaderKey(LogicalKeyboardKey.keyY.keyId, control: true),
      );
      await chord(tester, LogicalKeyboardKey.keyZ);
      expect(store.marks, hasLength(1));
      await chord(tester, LogicalKeyboardKey.keyY);
      expect(store.marks, isEmpty);
      await chord(tester, LogicalKeyboardKey.f9, control: false);
      expect(visible.value, isTrue);
      await tester.pumpWidget(const SizedBox());
      prefs.dispose();
      store.dispose();
      persisted.dispose();
      menu.dispose();
      visible.dispose();
      field.dispose();
    },
    variant: windows,
  );
  testWidgets(
    'shortcut settings capture an edited binding and restore defaults',
    (tester) async {
      final keys = ReaderShortcuts(await SharedPreferences.getInstance());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KeyboardShortcutsSettings(shortcuts: keys),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Ctrl+Z'));
      await tester.pumpAndSettle();
      await chord(tester, LogicalKeyboardKey.keyY);
      await tester.pumpAndSettle();
      expect(find.text('Ctrl+Y'), findsOneWidget);
      await tester.ensureVisible(find.text('Restore default shortcuts'));
      await tester.tap(find.text('Restore default shortcuts'));
      await tester.pumpAndSettle();
      expect(keys.binding(ReaderCommand.undo), ReaderCommand.undo.defaultKey);
      await tester.pumpWidget(const SizedBox());
      keys.dispose();
    },
    variant: windows,
  );
  testWidgets(
    'page entry rejects out-of-range values and scrollbar dragging reaches last page',
    (tester) async {
      int? selected;
      var railPage = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Row(
                children: [
                  TextButton(
                    onPressed: () async {
                      selected = await showReaderPageNumber(
                        context,
                        current: 6,
                        count: 30,
                      );
                    },
                    child: const Text('6 / 30'),
                  ),
                  const Spacer(),
                  DesktopPageRail(
                    current: 0,
                    count: 30,
                    onPage: (p) => railPage = p,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('6 / 30'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '31');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Go'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byType(TextField), '25');
      await tester.pump();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(selected, 25);
      final rect = tester.getRect(find.byType(DesktopPageRail));
      await tester.dragFrom(
        rect.topCenter + const Offset(0, 20),
        Offset(0, rect.height - 25),
      );
      await tester.pump();
      expect(railPage, 29);
      await tester.pumpWidget(const SizedBox());
    },
    variant: windows,
  );
  testWidgets(
    'EPUB page turns reuse chapter layout and preserve every rendered line',
    (tester) async {
      final prefs = ReaderPreferences();
      final store = AnnotationStore('fast-book');
      await store.load();
      final key = GlobalKey<EpubReaderState>();
      final markup = List.generate(
        100,
        (i) =>
            '<p>Paragraph $i: ${'Selectable text and annotation content. ' * 5}</p>',
      ).join();
      await helpers.openChapter(
        tester,
        key,
        store,
        prefs,
        EpubDocumentData('Long book', [
          EpubSection('c.xhtml', 'Chapter', markup),
        ], const {}),
      );
      final state = key.currentState!;
      expect(state.bookPages.count, greaterThan(10));
      final leaf = tester.allRenderObjects.whereType<RenderBookLeaf>().single;
      final paragraph = tester.widget<SelectableText>(
        find.byType(SelectableText).first,
      );
      for (var i = 0; i < 8; i++) {
        expect(state.bookPages.turn(1), isTrue);
        expect(
          leaf.debugNeedsLayout,
          isFalse,
          reason: 'A page turn must not lay out the chapter again.',
        );
        await tester.pumpAndSettle();
        expect(
          identical(
            tester.widget<SelectableText>(find.byType(SelectableText).first),
            paragraph,
          ),
          isTrue,
        );
      }
      helpers.expectCompletePageCoverage(tester, state);
      final jumping = state.goToPage();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        '${state.bookPages.count}',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Go'));
      await tester.pumpAndSettle();
      await jumping;
      expect(state.bookPages.page, state.bookPages.count - 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      prefs.dispose();
      store.dispose();
    },
    variant: windows,
  );
}
