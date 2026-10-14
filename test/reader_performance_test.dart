import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/reading_progress.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/features/library.dart';
import 'package:documentz/features/reader_controls.dart';

class _LargeLibrary extends MemoryLibrary implements ImportableLibrary {
  @override
  bool get persistsFiles => false;
  @override
  Future<List<Book>> listBooks() async => List.generate(
    200,
    (i) => Book(id: 'book-$i', title: 'Document $i', format: BookFormat.pdf),
  );
  @override
  Future<Book> importDocument(String name, Stream<List<int>> contents) =>
      throw UnimplementedError();
  @override
  Future<Uint8List> readDocument(Book book) => throw UnimplementedError();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ReadingProgress.instance.resetForTests();
  });
  testWidgets(
    'large libraries load covers near the viewport rather than every document',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final loaded = <String>{};
      final preferences = ReaderPreferences();
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryScreen(
              repository: _LargeLibrary(),
              preferences: preferences,
              coverLoader: (book, _) async {
                loaded.add(book.id);
                return null;
              },
            ),
          ),
        ),
      );
      await tester.runAsync(() => ReadingProgress.instance.load());
      await tester.pumpAndSettle();
      expect(loaded, isNotEmpty);
      expect(loaded.length, lessThan(20));
      final before = loaded.length;
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(loaded.length, greaterThan(before));
      expect(loaded.length, lessThan(40));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'reader menu mounts only when opened and retains document geometry',
    (tester) async {
      final open = ValueNotifier(false);
      addTearDown(open.dispose);
      var menuBuilds = 0;
      const pageKey = ValueKey('page');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderControlsScope(
              expanded: open,
              child: ReaderControlsOverlay(
                controls: Builder(
                  builder: (context) {
                    menuBuilds++;
                    return const Text('Test menu');
                  },
                ),
                child: const SizedBox.expand(key: pageKey),
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byKey(pageKey));
      expect(menuBuilds, 0);
      open.value = true;
      await tester.pumpAndSettle();
      expect(menuBuilds, 1);
      expect(tester.getSize(find.byKey(pageKey)), size);
      open.value = false;
      await tester.pumpAndSettle();
      expect(find.text('Test menu', skipOffstage: false), findsNothing);
      expect(tester.getSize(find.byKey(pageKey)), size);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
