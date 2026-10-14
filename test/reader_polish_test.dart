import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/reading_progress.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/features/library.dart';
import 'package:documentz/features/page_turn.dart';
import 'package:documentz/features/reader_edit_menu.dart';

class _MenuLibrary extends MemoryLibrary implements ImportableLibrary {
  @override
  bool get persistsFiles => false;
  @override
  Future<Uint8List> readDocument(Book book) async => Uint8List(0);
  @override
  Future<Book> importDocument(String name, Stream<List<int>> contents) =>
      throw UnimplementedError();
}

class _TextLibrary extends MemoryLibrary {
  @override
  Future<List<Book>> listBooks() async => const [
    Book(id: 'layout-progress', title: 'A document', format: BookFormat.txt),
  ];
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('library shows saved progress and fits larger text on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await ReadingProgress.instance.load();
    ReadingProgress.instance.record('layout-progress', .42);
    await ReadingProgress.instance.flush();
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: LibraryScreen(
              repository: _TextLibrary(),
              preferences: ReaderPreferences(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Progress 42%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reader editing commands are grouped in the menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ReaderEditMenu(
              book: const Book(
                id: 'pdf',
                title: 'Document',
                format: BookFormat.pdf,
              ),
              repository: _MenuLibrary(),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit document'));
    await tester.pumpAndSettle();
    for (final label in [
      'Merge',
      'Split',
      'Organize',
      'Rotate',
      'Content',
      'Fill form',
      'Export',
      'Signature',
      'Encrypt',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('repeated page turns reset before the live page changes', (
    tester,
  ) async {
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
    for (final direction in [1, -1]) {
      key.currentState!.animation.value = 1;
      var changed = false;
      final operation = key.currentState!.turn(direction, () {
        expect(key.currentState!.animation.value, 0);
        changed = true;
      });
      final deadline = Stopwatch()..start();
      while (key.currentState!.busy &&
          deadline.elapsed < const Duration(seconds: 10)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(key.currentState!.busy, isFalse);
      await operation;
      expect(changed, isTrue);
      expect(key.currentState!.snapshot, isNull);
    }
  });
}
