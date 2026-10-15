import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/features/pdf_navigation.dart';
import 'package:documentz/features/pdf_page_organizer.dart';

class _Page implements PdfPage {
  _Page(this.pageNumber);
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      invocation.memberName == #render
      ? Future<PdfImage?>.value(null)
      : super.noSuchMethod(invocation);
}

class _Document extends PdfDocument {
  _Document() : super(sourceName: 'organizer-test');
  @override
  final List<PdfPage> pages = List.generate(3, (i) => _Page(i + 1));
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('preview columns keep phone pages large and scale to wider screens', () {
    expect(pdfPreviewColumns(280), 1);
    expect(pdfPreviewColumns(390), 1);
    expect(pdfPreviewColumns(600), 2);
    expect(pdfPreviewColumns(900), 3);
    expect(pdfPreviewColumns(2400), 6);
  });
  for (final width in [280.0, 390.0, 900.0]) {
    testWidgets(
      'organizer has large zoomable pages and preserves order at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        List<int>? result;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async {
                    result = await Navigator.of(context).push<List<int>>(
                      MaterialPageRoute(
                        builder: (_) => PdfPageOrganizer(
                          bytes: Uint8List(0),
                          documentLoader: () async => _Document(),
                        ),
                      ),
                    );
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        final thumbnail = find.byType(PdfThumbnail).first;
        expect(tester.getSize(thumbnail).height, greaterThan(300));
        expect(tester.getSize(thumbnail).width, greaterThan(190));
        expect(find.byType(ReorderableDragStartListener), findsWidgets);
        await tester.tap(thumbnail);
        await tester.pumpAndSettle();
        expect(find.byType(InteractiveViewer), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Move down').first);
        await tester.pumpAndSettle();
        expect(find.text('Page 2 · Position 1'), findsOneWidget);
        await tester.tap(find.byTooltip('Move page').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Move to end'));
        await tester.pumpAndSettle();
        expect(find.text('Page 1 · Position 1'), findsOneWidget);
        await tester.tap(find.byTooltip('Remove page').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(result, [2, 1]);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
