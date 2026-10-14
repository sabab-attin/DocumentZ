import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/app.dart';
import 'package:documentz/data/recent_documents.dart';
import 'package:documentz/data/reading_progress.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/core/themes.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/reader.dart';
import 'package:documentz/features/device_library.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/data/local_library_web.dart';

// Native folder scans can complete only while the real event loop is running.
// Keep checking readiness instead of skipping or extending a failed assertion.
Future<void> settleApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (true) {
      await tester.pump(const Duration(milliseconds: 16));
      final circular = find
          .byType(CircularProgressIndicator)
          .evaluate()
          .any(
            (element) =>
                (element.widget as CircularProgressIndicator).value == null,
          );
      final linear = find
          .byType(LinearProgressIndicator)
          .evaluate()
          .any(
            (element) =>
                (element.widget as LinearProgressIndicator).value == null,
          );
      if (!circular && !linear) break;
      if (DateTime.now().isAfter(deadline)) {
        throw TestFailure('The visible app screen did not finish loading.');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecentDocuments.instance.resetForTests();
    ReadingProgress.instance.resetForTests();
  });
  testWidgets(
    'Merge offers Library and local storage after choosing the action',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ReaderApp(
          preferences: ReaderPreferences(),
          repository: BrowserLibrary(),
        ),
      );
      await settleApp(tester);
      await tester.tap(find.text('Edit'));
      await settleApp(tester);
      await tester.tap(find.text('Merge'));
      await settleApp(tester);
      expect(find.text('Select from library'), findsOneWidget);
      expect(find.text('Local storage'), findsOneWidget);
      expect(find.text('Existing PDF password (if needed)'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Recent, Library and Edit sit in the bottom navigation on mobile',
    (tester) async {
      addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ReaderApp(preferences: ReaderPreferences(), repository: _TestLibrary()),
      );
      await settleApp(tester);
      final navigation = tester.widget<NavigationBar>(
        find.byType(NavigationBar),
      );
      expect(
        navigation.destinations.cast<NavigationDestination>().map(
          (item) => item.label,
        ),
        ['Recent', 'Library', 'Edit'],
      );
      // The storage scanner is not even mounted until its tab is visited.
      expect(
        find.byType(DeviceLibraryScreen, skipOffstage: false),
        findsNothing,
      );
      await tester.tap(find.text('Library'));
      await settleApp(tester);
      expect(find.byType(DeviceLibraryScreen), findsOneWidget);
      await tester.tap(find.text('Recent'));
      await settleApp(tester);
      expect(
        TickerMode.valuesOf(
          tester.element(find.byType(DeviceLibraryScreen, skipOffstage: false)),
        ).enabled,
        isFalse,
      );
      await tester.tap(find.text('Edit'));
      await settleApp(tester);
      expect(find.text('Choose PDF'), findsNothing);
      expect(find.text('Merge'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Signature'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(IndexedStack),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(find.text('Signature'), findsOneWidget);
      expect(find.text('Redact'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reading size updates on an already open route', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final preferences = ReaderPreferences();
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderScreen(
          book: const Book(
            id: 'text',
            title: 'Test',
            format: BookFormat.txt,
            text: 'Sample text',
          ),
          preferences: preferences,
        ),
      ),
    );
    expect(find.byType(SelectableText), findsOneWidget);
    final viewport = tester.getSize(find.byType(SelectableText));
    expect(viewport.height, greaterThan(0));
    await tester.tap(find.byTooltip('Open reading menu'));
    await settleApp(tester);
    expect(tester.getSize(find.byType(SelectableText)), viewport);
    await tester.tap(find.byTooltip('Close reading menu'));
    await settleApp(tester);
    expect(tester.getSize(find.byType(SelectableText)), viewport);
    await preferences.setFontSize(30);
    await tester.pump();
    expect(
      tester
          .widget<SelectableText>(find.byType(SelectableText))
          .style!
          .fontSize,
      30,
    );
  });
  testWidgets('search, reader navigation and every theme work', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    final preferences = ReaderPreferences();
    await tester.pumpWidget(
      ReaderApp(preferences: preferences, repository: _TestLibrary()),
    );
    await settleApp(tester);
    await tester.tap(find.text('Library').last);
    await settleApp(tester);
    await tester.tap(find.text('A little room to read'));
    await settleApp(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    await tester.tap(find.byTooltip('Open reading menu'));
    await settleApp(tester);
    await tester.pageBack();
    await settleApp(tester);
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No documents found.'), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await settleApp(tester);
    for (final theme in ReaderTheme.values) {
      await tester.ensureVisible(find.text(theme.label));
      await tester.tap(find.text(theme.label));
      await settleApp(tester);
      expect(preferences.theme, theme);
      expect(tester.takeException(), isNull);
    }
  });

  test('theme foreground pairs exceed WCAG AA contrast', () {
    double contrast(Color a, Color b) {
      final l1 = a.computeLuminance();
      final l2 = b.computeLuminance();
      return l1 > l2 ? (l1 + .05) / (l2 + .05) : (l2 + .05) / (l1 + .05);
    }

    for (final theme in ReaderTheme.values) {
      expect(contrast(theme.background, theme.ink), greaterThanOrEqualTo(4.5));
      expect(
        contrast(theme.background, theme.accent),
        greaterThanOrEqualTo(4.5),
      );
    }
  });

  test('theme and size survive preference reload', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await ReaderPreferences.load();
    await preferences.setTheme(ReaderTheme.dark);
    await preferences.setFontSize(28);
    final restored = await ReaderPreferences.load();
    expect(restored.theme, ReaderTheme.dark);
    expect(restored.fontSize, 28);
    expect(restored.saveFailed, false);
  });

  testWidgets('large text fits a narrow screen', (tester) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReaderApp(
        preferences: ReaderPreferences(fontSize: 32),
        repository: _TestLibrary(),
      ),
    );
    await settleApp(tester);
    await tester.tap(find.byTooltip('Settings'));
    await settleApp(tester);
    expect(tester.takeException(), isNull);
  });
}

class _TestLibrary extends MemoryLibrary {
  @override
  Future<List<Book>> listBooks() async => const [
    Book(
      id: 'text',
      title: 'A little room to read',
      format: BookFormat.txt,
      text: 'Test document',
    ),
  ];
}
