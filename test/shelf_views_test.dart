import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/document_shelf.dart';
import 'package:documentz/features/document_tile.dart';
import 'package:documentz/features/shelf_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('Recent and Library keep independent view and sort settings', () async {
    final recent = ShelfPreferences('recent-test', recent: true);
    await recent.load();
    final library = ShelfPreferences('library-test');
    await library.load();
    expect(recent.sort, ShelfSort.opened);
    expect(recent.descending, true);
    await recent.choose(
      view: ShelfView.details,
      sort: ShelfSort.size,
      descending: false,
      groupByType: true,
    );
    expect(library.view, ShelfView.medium);
    expect(library.sort, ShelfSort.name);
    final restored = ShelfPreferences('recent-test');
    await restored.load();
    expect(restored.view, ShelfView.details);
    expect(restored.sort, ShelfSort.size);
    expect(restored.groupByType, true);
    expect(restored.descending, false);
    recent.dispose();
    library.dispose();
    restored.dispose();
  });
  test(
    'date sorting keeps unavailable metadata last in either direction',
    () async {
      final shelf = ShelfPreferences('sort-test');
      final records = [
        const ShelfOrderData(id: 'missing', name: 'Missing', type: 'pdf'),
        const ShelfOrderData(id: 'old', name: 'Old', type: 'txt', modified: 10),
        const ShelfOrderData(id: 'new', name: 'New', type: 'pdf', modified: 20),
      ];
      await shelf.choose(sort: ShelfSort.modified, descending: true);
      records.sort(shelf.compare);
      expect(records.map((v) => v.id), ['new', 'old', 'missing']);
      await shelf.choose(descending: false);
      records.sort(shelf.compare);
      expect(records.map((v) => v.id), ['old', 'new', 'missing']);
      await shelf.choose(groupByType: true);
      records.sort(shelf.compare);
      expect(records.map((v) => v.type), ['pdf', 'pdf', 'txt']);
      shelf.dispose();
    },
  );
  for (final width in [320.0, 900.0]) {
    for (final view in ShelfView.values) {
      testWidgets(
        '${view.label} fits width $width with larger text and file actions',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final shelf = ShelfPreferences('layout-test');
          await shelf.choose(view: view, groupByType: true);
          final cover = Future<Uint8List?>.value(null);
          var options = 0;
          bool? selected;
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1200),
                  textScaler: TextScaler.linear(width == 900 ? 1 : 2),
                ),
                child: Scaffold(
                  body: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.all(16),
                        sliver: DocumentShelfSliver<int>(
                          items: const [1],
                          preferences: shelf,
                          width: width,
                          typeOf: (_) => 'pdf',
                          tileBuilder: (item, layout) => DocumentTile(
                            title: 'A long document title for reading',
                            format: BookFormat.pdf,
                            cover: cover,
                            layout: layout,
                            onOpen: () {},
                            onOptions: () => options++,
                            selectable: true,
                            onSelected: (value) => selected = value,
                            progress: .4,
                          ),
                          rowBuilder: (_) => ShelfDocumentRow(
                            title: 'A long document title for reading',
                            format: BookFormat.pdf,
                            view: view,
                            progress: .4,
                            onOpen: () {},
                            onOptions: () => options++,
                            selectable: true,
                            onSelected: (value) => selected = value,
                            cover: cover,
                            size: 25000,
                            modified: 1700000000000,
                            folder: 'Documents/Books',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip('Document options'));
          await tester.pumpAndSettle();
          expect(options, 1);
          await tester.tap(find.byType(Checkbox));
          await tester.pumpAndSettle();
          expect(selected, true);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          shelf.dispose();
        },
      );
    }
  }
}
