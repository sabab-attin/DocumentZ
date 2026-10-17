import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/features/format_reader.dart';
import 'package:documentz/features/epub_reader.dart';
import 'package:documentz/features/reader.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MethodChannel, MissingPluginException;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/data/recent_documents.dart';
import 'package:documentz/data/reading_progress.dart';
import 'package:documentz/data/device_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    RecentDocuments.instance.resetForTests();
    ReadingProgress.instance.resetForTests();
  });

  test('reader annotations remain pending until Save and Discard restores the original', () async {
    final initial = AnnotationStore('transaction');
    await initial.load();
    await initial.add(
      DocumentMark(anchor: 'page:1', tool: MarkTool.note, text: 'Original'),
    );
    final editing = AnnotationStore('transaction', deferred: true);
    await editing.load();
    await editing.add(
      DocumentMark(anchor: 'page:1', tool: MarkTool.note, text: 'Pending'),
    );
    expect(editing.hasChanges, true);
    final beforeSave = AnnotationStore('transaction');
    await beforeSave.load();
    expect(beforeSave.marks.map((mark) => mark.text), ['Original']);
    editing.discard();
    expect(editing.hasChanges, false);
    expect(editing.marks.single.text, 'Original');
    await editing.add(
      DocumentMark(anchor: 'page:1', tool: MarkTool.note, text: 'Saved'),
    );
    expect(await editing.commit(), true);
    expect(editing.hasChanges, false);
    final afterSave = AnnotationStore('transaction');
    await afterSave.load();
    expect(afterSave.marks.map((mark) => mark.text), ['Original', 'Saved']);
    initial.dispose();
    editing.dispose();
    beforeSave.dispose();
    afterSave.dispose();
  });

  test(
    'Recent persists access timestamps without treating all files as accessed',
    () async {
      final recent = RecentDocuments();
      await recent.load();
      expect(recent.accessed, isEmpty);
      await recent.record('opened-document');
      final restored = RecentDocuments();
      await restored.load();
      expect(restored.accessed.keys, ['opened-document']);
      recent.dispose();
      restored.dispose();
    },
  );

  testWidgets(
    'image movement keeps its identity and Done locks the placement',
    (tester) async {
      final store = AnnotationStore('placement', deferred: true);
      await store.load();
      final bytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 8, height: 8)),
      );
      final mark = DocumentMark(
        anchor: 'page:1',
        tool: MarkTool.image,
        attachments: [base64Encode(bytes)],
        rects: [const Rect.fromLTWH(.1, .1, .4, .4)],
      );
      await store.add(mark);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 600,
              child: ListenableBuilder(
                listenable: store,
                builder: (context, _) => PageMarks(
                  store: store,
                  anchor: 'page:1',
                  dark: false,
                  onTouched: () {},
                  tool: MarkTool.browse,
                  annotationMode: true,
                ),
              ),
            ),
          ),
        ),
      );
      final start = store.marks.single.rects.single;
      await tester.dragFrom(const Offset(150, 200), const Offset(50, 30));
      await tester.pumpAndSettle();
      expect(store.marks.single.id, mark.id);
      expect(store.marks.single.rects.single.left, greaterThan(start.left));
      final moved = store.marks.single.rects.single;
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(store.marks.single.locked, true);
      expect(store.marks.single.rects.single, moved);
      expect(find.text('Done'), findsNothing);
      await tester.dragFrom(const Offset(200, 220), const Offset(50, 30));
      await tester.pumpAndSettle();
      expect(store.marks.single.rects.single, moved);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
  );

  testWidgets(
    'leaving an edited reader offers Save or Discard and preserves only saved changes',
    (tester) async {
      final repository = BrowserLibrary();
      final book = await repository.importDocument(
        'test.txt',
        Stream.value(utf8.encode('Document text')),
      );
      final preferences = ReaderPreferences();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                child: const Text('Open document'),
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
              ),
            ),
          ),
        ),
      );
      for (final choice in ['Discard', 'Save']) {
        await tester.tap(find.text('Open document'));
        // Parsing uses a real isolate. Let it finish outside the fake test clock.
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (find.byType(EpubReader).evaluate().isEmpty) {
            if (DateTime.now().isAfter(deadline)) {
              throw TestFailure('The text reader did not finish loading.');
            }
            await tester.pump(const Duration(milliseconds: 16));
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        final reader = tester.widget<FormatReader>(find.byType(FormatReader));
        final store = reader.annotationStore!;
        await store.add(
          DocumentMark(anchor: 'chapter:0', tool: MarkTool.note, text: choice),
        );
        await tester.pump();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.text('Save changes?'), findsOneWidget);
        // The reader and its persistence queue were created on the real event loop.
        // Complete both dialog dismissal and persistence before checking navigation.
        await tester.runAsync(() async {
          await tester.tap(find.text(choice));
          final deadline = DateTime.now().add(const Duration(seconds: 15));
          while (find.text('Open document').evaluate().isEmpty) {
            await tester.pump(const Duration(milliseconds: 16));
            if (DateTime.now().isAfter(deadline)) {
              throw TestFailure(
                'Reader did not close after $choice; '
                'unsaved changes: ${store.hasChanges}.',
              );
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(find.text('Open document'), findsOneWidget);
        final persisted = AnnotationStore(book.id);
        await tester.runAsync(persisted.load);
        expect(
          persisted.marks.map((mark) => mark.text),
          choice == 'Save' ? ['Save'] : isEmpty,
        );
        persisted.dispose();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    },
  );

  test('folder indexing includes subfolders, excludes unsupported files and deduplicates overlapping roots', () async {
    if (Platform.isAndroid) return;
    final support = await Directory.systemTemp.createTemp(
      'documentz-index-support-',
    );
    const storageChannel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storageChannel, (call) async {
      if (call.method == 'getApplicationSupportDirectory') {
        return support.path;
      }
      throw MissingPluginException(call.method);
    });
    addTearDown(() async {
      messenger.setMockMethodCallHandler(storageChannel, null);
      await support.delete(recursive: true);
    });
    final root = await Directory.systemTemp.createTemp('documentz-index-test-');
    addTearDown(() async {
      await root.delete(recursive: true);
    });
    final child = await Directory('${root.path}/child').create();
    await File('${root.path}/one.pdf').writeAsString('%PDF-1.7');
    await File('${child.path}/two.epub').writeAsString('fixture');
    await File('${child.path}/ignored.exe').writeAsString('fixture');
    SharedPreferences.setMockInitialValues({
      'documentz.deviceFolders.v1': [
        root.path,
        child.path,
        '${root.path}/child/../child',
        if (Platform.isWindows) child.path.toUpperCase().replaceAll('/', '\\'),
      ],
    });
    // Check the complete scan; normal launches can return a cached/quick list.
    final scan = await scanDeviceDocuments(refresh: true);
    expect(scan.errors, isEmpty);
    expect(
      scan.documents.map((document) => document.name),
      unorderedEquals(['one.pdf', 'two.epub']),
    );
    expect(
      scan.documents.map((document) => document.location).toSet(),
      hasLength(2),
    );
  });
}
