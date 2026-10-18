import 'package:documentz/data/recent_documents.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:documentz/data/pdf_booklet.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/features/booklet_creator.dart';

Future<Uint8List> numberedPdf(int count) async {
  final doc = sf.PdfDocument();
  try {
    doc.pageSettings.size = const Size(200, 300);
    doc.pageSettings.margins.all = 0;
    for (var i = 1; i <= count; i++) {
      doc.pages.add().graphics.drawString(
        'SOURCE_$i',
        sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 12),
        bounds: const Rect.fromLTWH(20, 30, 160, 25),
      );
    }
    return Uint8List.fromList(await doc.save());
  } finally {
    doc.dispose();
  }
}

String sideText(sf.PdfDocument doc, int side) =>
    sf.PdfTextExtractor(doc)
        .extractText(startPageIndex: side, endPageIndex: side)
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('eight pages impose front and back in fold order', () {
    final sides = planBooklets(8, 0).single.sides;
    expect(
      [
        for (final side in sides) [side.left, side.right],
      ],
      [
        [7, 0],
        [1, 6],
        [5, 2],
        [3, 4],
      ],
    );
  });
  test(
    'every supported size places every source page once with safe padding',
    () {
      for (var count = 1; count <= 401; count++) {
        for (final size in [0, 4, 8, 12, 16, 20, 24]) {
          final plan = planBooklets(count, size);
          final seen = <int>[];
          for (final signature in plan) {
            expect(signature.pages.length % 4, 0);
            expect(signature.sides.length, signature.sheetCount * 2);
            for (final side in signature.sides) {
              if (side.left != null) seen.add(side.left!);
              if (side.right != null) seen.add(side.right!);
            }
          }
          expect(seen..sort(), List.generate(count, (i) => i));
        }
      }
      expect(() => planBooklets(0, 16), throwsFormatException);
      expect(() => planBooklets(10, 6), throwsFormatException);
    },
  );
  test('last booklet matches the saved creator full-signature padding', () {
    final plan = planBooklets(17, 16);
    expect(plan.length, 2);
    expect(plan.last.blankCount, 15);
    expect(plan.last.sheetCount, 4);
    expect(plan.last.sides.first.left, null);
    expect(plan.last.sides.first.right, 16);
    expect(planBooklets(5, 16).single.blankCount, 3);
  });
  test(
    'PDF artwork and text occupy correct halves and preview matches export',
    () async {
      final source = await numberedPdf(8);
      final snapshot = Uint8List.fromList(source);
      final output = await PdfBooklet.export(source, 'Example.pdf', 0);
      expect(output.name, 'Example_booklet_pages_1-8.pdf');
      final doc = sf.PdfDocument(inputBytes: output.bytes);
      final preview = sf.PdfDocument(
        inputBytes: await PdfBooklet.preview(
          source,
          planBooklets(8, 0).single,
          0,
        ),
      );
      try {
        expect(doc.pages.count, 4);
        expect(doc.pages[0].size, const Size(400, 300));
        final expected = [
          [8, 1],
          [2, 7],
          [6, 3],
          [4, 5],
        ];
        for (var side = 0; side < expected.length; side++) {
          final lines = sf.PdfTextExtractor(doc)
              .extractTextLines(startPageIndex: side, endPageIndex: side);
          final words = lines.expand((line) => line.wordCollection);
          final left = words
              .where((word) => word.bounds.center.dx < 200)
              .map((word) => word.text)
              .join(' ');
          final right = words
              .where((word) => word.bounds.center.dx > 200)
              .map((word) => word.text)
              .join(' ');
          expect(left, contains('SOURCE_${expected[side][0]}'));
          expect(right, contains('SOURCE_${expected[side][1]}'));
        }
        expect(preview.pages.count, 1);
        expect(sideText(preview, 0), sideText(doc, 0));
        expect(source, snapshot);
      } finally {
        doc.dispose();
        preview.dispose();
      }
    },
  );
  test(
    'multiple booklets export valid PDFs in a ZIP including blank slots',
    () async {
      final source = await numberedPdf(5);
      final progress = <int>[];
      final output = await PdfBooklet.export(
        source,
        'Test',
        4,
        onProgress: (done, total) {
          expect(total, 2);
          progress.add(done);
        },
      );
      expect(output.isZip, true);
      expect(progress, [1, 2]);
      final zip = ZipDecoder().decodeBytes(output.bytes);
      expect(zip.files.map((file) => file.name).toList(), [
        'Test_pages_1-4.pdf',
        'Test_pages_5-5.pdf',
      ]);
      final last = sf.PdfDocument(
        inputBytes: Uint8List.fromList(zip.files.last.content),
      );
      try {
        expect(last.pages.count, 2);
        expect(sideText(last, 0), contains('SOURCE_5'));
        expect(sideText(last, 1), isEmpty);
      } finally {
        last.dispose();
      }
    },
  );
  testWidgets(
    'preview switches front and back before export, then saves a copy',
    (tester) async {
      final bytes = await numberedPdf(4);
      SharedPreferences.setMockInitialValues({});
      RecentDocuments.instance.resetForTests();
      final library = BrowserLibrary();
      var saved = 0;
      var attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: BookletCreator(
            bytes: bytes,
            title: 'Four',
            repository: library,
            onSaved: () => saved++,
            outputWriter: (outputs) async {
              if (++attempts == 1) {
                throw StateError('Storage temporarily unavailable');
              }
              return outputs
                  .map((output) => '/downloads/${output.name}')
                  .toList();
            },
            previewBuilder: (data) =>
                const Center(child: Text('Interactive sheet preview')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<DropdownButtonFormField<int>>(
              find.byType(DropdownButtonFormField<int>).first,
            )
            .initialValue,
        0,
      );
      expect(
        find.textContaining('Printing tip: Choose both sides'),
        findsOneWidget,
      );
      expect(find.text('Left: Page 4'), findsOneWidget);
      expect(find.text('Right: Page 1'), findsOneWidget);
      expect(await library.listBooks(), isEmpty);
      await tester.tap(find.byTooltip('Next sheet side'));
      await tester.pumpAndSettle();
      expect(find.text('Left: Page 2'), findsOneWidget);
      expect(find.text('Right: Page 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('create-booklet')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Could not save the booklet. Check storage and permissions, then retry.',
        ),
        findsOneWidget,
      );
      expect(saved, 0);
      expect(find.byType(SnackBar), findsNothing);
      expect(
        find.byKey(const Key('create-booklet')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('create-booklet')));
      await tester.pumpAndSettle();
      expect(find.text('Save to library'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(RecentDocuments.instance.accessed, hasLength(1));
      await tester.pumpAndSettle();
      expect(saved, 1);
      expect((await library.listBooks()).length, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
