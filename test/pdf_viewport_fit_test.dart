import 'package:documentz/features/pdf_viewport_fit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'continuous height changes retain the same first visible source line',
    () {
      const width = 600.0, top = 120.0;
      for (final size in [
        const Size(400, 700),
        const Size(400, 500),
        const Size(800, 350),
      ]) {
        final center = pdfWidthFittedCenter(width, size, top);
        final zoom = size.width / width;
        expect(center.dy - size.height / (2 * zoom), closeTo(top, .001));
      }
    },
  );
  test('height only resize refits the entire page below normal controls', () {
    const page = Rect.fromLTWH(0, 0, 600, 900);
    final full = pdfFitZoom(page, const Size(400, 700), widthOnly: false);
    final normal = pdfFitZoom(page, const Size(400, 500), widthOnly: false);
    expect(normal, lessThan(full));
    expect(page.height * normal, closeTo(500, .001));
    expect(page.width * normal, lessThanOrEqualTo(400));
  });

  test('landscape and portrait fit wide slides without clipping', () {
    const slide = Rect.fromLTWH(0, 0, 1600, 900);
    for (final size in [const Size(380, 690), const Size(790, 350)]) {
      final zoom = pdfFitZoom(slide, size, widthOnly: false);
      expect(slide.width * zoom, lessThanOrEqualTo(size.width));
      expect(slide.height * zoom, lessThanOrEqualTo(size.height));
    }
  });

  test('dual page uses both pages and handles an odd last page', () {
    final pages = [
      const Rect.fromLTWH(0, 0, 600, 900),
      const Rect.fromLTWH(600, 0, 700, 800),
      const Rect.fromLTWH(0, 900, 900, 600),
    ];
    final spread = pdfVisiblePageArea(pages, 2, dual: true);
    expect(spread, const Rect.fromLTWH(0, 0, 1300, 900));
    expect(pdfVisiblePageArea(pages, 3, dual: true), pages.last);
    final zoom = pdfFitZoom(spread, const Size(700, 320), widthOnly: false);
    expect(spread.height * zoom, closeTo(320, .001));
    expect(spread.width * zoom, lessThanOrEqualTo(700));
  });

  test('fit width remains a deliberate scrollable view', () {
    const page = Rect.fromLTWH(0, 0, 600, 1200);
    final zoom = pdfFitZoom(page, const Size(400, 300), widthOnly: true);
    expect(page.width * zoom, closeTo(400, .001));
    expect(page.height * zoom, greaterThan(300));
  });
}
