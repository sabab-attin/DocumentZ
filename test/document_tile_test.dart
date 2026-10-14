import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/document_tile.dart';

void main() {
  for (final width in [240.0, 320.0, 390.0, 920.0]) {
    for (final textScale in [1.0, 1.3, 2.0, 2.5]) {
      testWidgets(
        'consistent tiles at width $width and text scale $textScale',
        (tester) async {
          tester.view.physicalSize = Size(width, 1200);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final scaler = TextScaler.linear(textScale);
          final layout = DocumentTileLayout(width, scaler);
          final cover = Future<Uint8List?>.value(null);
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 1200),
                  textScaler: scaler,
                ),
                child: Scaffold(
                  body: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: layout.columns,
                      mainAxisExtent: layout.extent,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: 2,
                    itemBuilder: (_, index) => DocumentTile(
                      title: index == 0 ? 'Short' : 'A very long document name that needs multiple lines and remains accessible',
                      format: BookFormat.pdf,
                      cover: cover,
                      layout: layout,
                      onOpen: () {},
                      onOptions: () {},
                      selectable: true,
                      onSelected: (_) {},
                      progress: .37,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final sizes = find
              .byType(DocumentTile)
              .evaluate()
              .map((e) => tester.getSize(find.byWidget(e.widget)))
              .toList();
          expect(sizes.length, 2);
          expect(sizes[0], sizes[1]);
          expect(find.text('Progress 37%'), findsNWidgets(2));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
  testWidgets('open, options, long press and selection remain separate', (
    tester,
  ) async {
    var opened = 0, options = 0;
    bool? selection;
    final layout = DocumentTileLayout(390, TextScaler.noScaling);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 171,
              height: layout.extent,
              child: DocumentTile(
                title: 'Example',
                format: BookFormat.epub,
                cover: Future<Uint8List?>.value(null),
                layout: layout,
                onOpen: () => opened++,
                onOptions: () => options++,
                selectable: true,
                onSelected: (value) => selection = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Example'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    await tester.tap(find.byTooltip('Document options'));
    await tester.pumpAndSettle();
    expect(options, 1);
    expect(opened, 1);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(selection, true);
    expect(opened, 1);
    await tester.longPress(find.text('Example'));
    await tester.pumpAndSettle();
    expect(options, 2);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });
}
