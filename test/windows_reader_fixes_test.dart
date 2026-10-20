import 'dart:async';
import 'dart:io';

import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/features/annotations.dart';
import 'package:documentz/features/annotated_paragraph.dart';
import 'package:documentz/features/desktop_pdf_layout.dart';
import 'package:documentz/features/document_reader.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:flutter/services.dart';
import 'package:documentz/features/pdf_viewport_fit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);
  test('single-page fit never exposes neighbours, including mixed sizes and narrow windows', () {
    const sizes = [
      Size(595, 842),
      Size(1600, 900),
      Size(100, 160),
      Size(500, 500),
    ];
    for (final viewport in [
      const Size(1440, 700),
      const Size(500, 800),
      const Size(900, 400),
    ]) {
      final layout = desktopSinglePdfLayout(sizes, viewport);
      for (var i = 0; i < sizes.length; i++) {
        final page = layout.pageLayouts[i];
        final zoom = pdfFitZoom(page, viewport, widthOnly: false);
        final visible = Rect.fromCenter(
          center: page.center,
          width: viewport.width / zoom,
          height: viewport.height / zoom,
        );
        expect(page.width * zoom, lessThanOrEqualTo(viewport.width + .01));
        expect(page.height * zoom, lessThanOrEqualTo(viewport.height + .01));
        for (var j = 0; j < sizes.length; j++) {
          if (j != i) expect(visible.overlaps(layout.pageLayouts[j]), isFalse);
        }
      }
    }
  });

  testWidgets(
    'Windows mouse marking updates only its preview until the stroke is saved',
    (tester) async {
      final store = AnnotationStore('desktop-mark-drag');
      await store.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnotatedParagraph(
              element: html
                  .parseFragment(
                    '<p>Research selection stays responsive while marking a paragraph.</p>',
                  )
                  .children
                  .single,
              block: 'p0',
              anchor: 'chapter:1',
              store: store,
              style: const TextStyle(fontSize: 22),
              activeTool: MarkTool.highlight,
              onSelection: (_) {},
              onLink: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final original = tester.widget<SelectableText>(
        find.byType(SelectableText),
      );
      final origin = tester.getTopLeft(find.byType(SelectableText));
      final gesture = await tester.startGesture(
        origin + const Offset(3, 12),
        kind: PointerDeviceKind.mouse,
      );
      for (var x = 40.0; x <= 220; x += 20) {
        await gesture.moveTo(origin + Offset(x, 12));
        await tester.pump();
        expect(
          identical(
            original,
            tester.widget<SelectableText>(find.byType(SelectableText)),
          ),
          isTrue,
          reason: 'Mouse movement must not rebuild or relayout the selectable paragraph.',
        );
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(store.marks, hasLength(1));
      expect(store.marks.single.quote, isNotEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      store.dispose();
    },
    variant: windows,
  );

  testWidgets(
    'PDF mouse drag selects actual text with desktop selection handles disabled',
    (tester) async {
      Pdfrx.cacheDirectoryPath = Directory.systemTemp.path;
      await tester.runAsync(() => pdfrxFlutterInitialize());
      final pdf = pw.Document();
      pdf.addPage(
        pw.Page(
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(
            children: [
              pw.Positioned(
                left: 50,
                top: 50,
                child: pw.Text(
                  'Research paper text selection',
                  style: const pw.TextStyle(fontSize: 20),
                ),
              ),
            ],
          ),
        ),
      );
      pdf.addPage(
        pw.Page(build: (_) => pw.Text('Second page for isolated navigation')),
      );
      pdf.addPage(
        pw.Page(build: (_) => pw.Text('Third page for keyboard navigation')),
      );
      final bytes = await pdf.save();
      final library = BrowserLibrary();
      final book = await library.importDocument(
        'research.pdf',
        Stream.value(bytes),
      );
      final preferences = ReaderPreferences();
      final menu = ValueNotifier(false);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReaderControlsScope(
              expanded: menu,
              child: DocumentReader(
                book: book,
                repository: library,
                preferences: preferences,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (true) {
          await tester.pump();
          final widgets = tester.widgetList<PdfViewer>(find.byType(PdfViewer));
          if (widgets.isNotEmpty && widgets.single.controller!.isReady) break;
          if (DateTime.now().isAfter(deadline)) {
            throw TestFailure('PDF viewer did not become ready.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();
      final widget = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(
        widget.params.textSelectionParams!.enableSelectionHandles,
        isFalse,
      );
      final controller = widget.controller!;
      final page = controller.document.pages.first;
      final text = await tester.runAsync(() => page.loadText());
      final first = text!.charRects.first.toRectInDocument(
        page: page,
        pageRect: controller.layout.pageLayouts.first,
      );
      final last = text.charRects[12].toRectInDocument(
        page: page,
        pageRect: controller.layout.pageLayouts.first,
      );
      final origin = tester.getTopLeft(find.byType(PdfViewer));
      Offset position(Offset point) =>
          origin + MatrixUtils.transformPoint(controller.value, point);
      final drag = await tester.startGesture(
        position(first.centerLeft + const Offset(.5, 0)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await drag.moveTo(position(last.centerRight));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await drag.up();
      await tester.pump();
      final selected = await tester.runAsync(
        () => controller.textSelectionDelegate.getSelectedText(),
      );
      expect(selected, contains('Research'));
      await controller.textSelectionDelegate.clearTextSelection();
      await tester.pump(const Duration(milliseconds: 500));
      menu.value = true;
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Display mode'));
      await tester.tap(find.byTooltip('Display mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Single page'));
      await tester.pumpAndSettle();
      menu.value = false;
      await tester.pumpAndSettle();
      final single = tester.widget<PdfViewer>(find.byType(PdfViewer));
      expect(single.params.scrollByMouseWheel, isNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 2);
      final visible = controller.value.calcVisibleRect(controller.viewSize);
      expect(visible.overlaps(controller.layout.pageLayouts[0]), isFalse);
      expect(visible.overlaps(controller.layout.pageLayouts[2]), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 3);
      final area = tester.getCenter(find.byType(PdfViewer));
      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: area, scrollDelta: const Offset(0, -80)),
      );
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 2);
      tester.view.physicalSize = const Size(1200, 500);
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 2);
      final resized = controller.value.calcVisibleRect(controller.viewSize);
      expect(resized.overlaps(controller.layout.pageLayouts[0]), isFalse);
      expect(resized.overlaps(controller.layout.pageLayouts[2]), isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1');
      await tester.tap(find.widgetWithText(FilledButton, 'Go'));
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 1);
      final rail = tester.getRect(find.byType(DesktopPageRail));
      final railDrag = await tester.startGesture(
        rail.topCenter + const Offset(0, 3),
        kind: PointerDeviceKind.mouse,
      );
      await railDrag.moveTo(rail.bottomCenter - const Offset(0, 2));
      await railDrag.up();
      await tester.pumpAndSettle();
      expect(controller.pageNumber, 3);
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
      menu.dispose();
      await tester.pump(const Duration(milliseconds: 100));
    },
    variant: windows,
  );
}
