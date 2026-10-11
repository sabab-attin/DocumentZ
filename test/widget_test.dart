import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/app.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/core/themes.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/reader.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/data/local_library_web.dart';

void main() {
  testWidgets('Merge offers Library and local storage after choosing the action', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReaderApp(preferences: ReaderPreferences(), repository: BrowserLibrary()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merge'));
    await tester.pumpAndSettle();
    expect(find.text('Select from library'), findsOneWidget);
    expect(find.text('Local storage'), findsOneWidget);
    expect(find.text('Existing PDF password (if needed)'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Edit sits between Library and Settings on mobile', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ReaderApp(preferences: ReaderPreferences(), repository: _TestLibrary()));
    await tester.pumpAndSettle();
    final navigation = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(navigation.destinations.cast<NavigationDestination>().map((item) => item.label), ['Library', 'Edit', 'Settings']);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(find.text('Choose PDF'), findsNothing);
    expect(find.text('Merge'), findsOneWidget);
    expect(find.text('Signature'), findsOneWidget);
    expect(find.text('Redact'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('reading size updates on an already open route', (tester) async {
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
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(SelectableText)), viewport);
    await tester.tap(find.text('Hide controls'));
    await tester.pumpAndSettle();
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
    final preferences = ReaderPreferences();
    await tester.pumpWidget(ReaderApp(preferences: preferences, repository: _TestLibrary()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A little room to read'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
      await tester.tap(find.text('Controls'));
      await tester.pumpAndSettle();
      await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No documents found.'), findsOneWidget);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    for (final theme in ReaderTheme.values) {
      await tester.ensureVisible(find.text(theme.label));
      await tester.tap(find.text(theme.label));
      await tester.pumpAndSettle();
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
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ReaderApp(preferences: ReaderPreferences(fontSize: 32), repository: _TestLibrary()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

class _TestLibrary extends MemoryLibrary {
  @override
  Future<List<Book>> listBooks() async => const [Book(id: 'text', title: 'A little room to read', format: BookFormat.txt, text: 'Test document')];
}
