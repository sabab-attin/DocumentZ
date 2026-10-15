import 'dart:convert';

import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/features/book_paper.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/format_reader.dart';
import 'package:documentz/features/reader.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Back closes the reading menu without a false save prompt', (
    tester,
  ) async {
    final repository = BrowserLibrary();
    final book = await repository.importDocument(
      'unchanged.txt',
      Stream.value(utf8.encode('An unchanged book.')),
    );
    final preferences = ReaderPreferences(autoHideControls: false);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    book: book,
                    repository: repository,
                    preferences: preferences,
                  ),
                ),
              ),
              child: const Text('Open book'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open book'));
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (find.byType(EpubReader).evaluate().isEmpty) {
        if (DateTime.now().isAfter(deadline)) {
          throw TestFailure('Reader did not load.');
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    final store = tester
        .widget<FormatReader>(find.byType(FormatReader))
        .annotationStore!;
    expect(store.hasChanges, isFalse);
    final scope = tester.widget<ReaderControlsScope>(
      find.byType(ReaderControlsScope),
    );
    scope.expanded.value = true;
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(scope.expanded.value, isFalse);
    expect(find.text('Save changes?'), findsNothing);
    expect(find.byType(ReaderScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Save changes?'), findsNothing);
    expect(find.text('Open book'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    preferences.dispose();
  });

  for (final dark in [false, true]) {
    testWidgets(
      'paper and footer preserve taps and fit large text in dark mode: $dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preferences = ReaderPreferences(showPageButtons: true);
        var taps = 0, next = 0;
        final ink = dark ? Colors.white : Colors.black;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2.5)),
              child: Scaffold(
                body: BookPaper(
                  paper: dark ? Colors.black : Colors.white,
                  columns: 2,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(
                        child: TextButton(
                          onPressed: () => taps++,
                          child: const Text('Book link'),
                        ),
                      ),
                      ReaderBottomBar(
                        preferences: preferences,
                        pageInk: ink,
                        label: 'A very long chapter heading · 124–125 / 300',
                        onPrevious: () {},
                        onNext: () => next++,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Book link'));
        await tester.tap(find.byTooltip('Next page'));
        expect(taps, 1);
        expect(next, 1);
        expect(tester.takeException(), isNull);
        // Button ink surfaces are separate Materials. Select only the surface
        // that is an ancestor of the page label, inside this reader footer.
        final footer = find.ancestor(
          of: find.text('A very long chapter heading · 124–125 / 300'),
          matching: find.descendant(
            of: find.byType(ReaderBottomBar),
            matching: find.byType(Material),
          ),
        );
        expect(footer, findsOneWidget);
        expect(tester.widget<Material>(footer).elevation, 0);
        expect(tester.widget<Material>(footer).color, Colors.transparent);
        await tester.pumpWidget(const SizedBox.shrink());
        preferences.dispose();
      },
    );
  }
}
