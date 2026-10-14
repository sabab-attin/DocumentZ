import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/features/text_mark_geometry.dart';
import 'package:documentz/features/annotations.dart';

class _Page implements PdfPage {
  _Page({this.width = 600, this.height = 800});
  @override
  final double width;
  @override
  final double height;
  @override
  PdfPageRotation get rotation => PdfPageRotation.values.first;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('page normalization preserves horizontal and vertical coverage on every aspect ratio', () {
    for (final size in const [
      Size(600, 800),
      Size(800, 600),
      Size(400, 1000),
      Size(1000, 400),
    ]) {
      final page = _Page(width: size.width, height: size.height);
      final rect = normalizedPdfMarkRect(
        PdfRect(40, size.height - 60, size.width - 40, size.height - 80),
        page,
      );
      expect(rect.left, closeTo(40 / size.width, .000001));
      expect(rect.right, closeTo(1 - 40 / size.width, .000001));
      expect(rect.top, closeTo(60 / size.height, .000001));
      expect(rect.bottom, closeTo(80 / size.height, .000001));
    }
  });
  test('existing saved text marks correct their aspect ratio once; new marks stay exact', () {
    final legacy = DocumentMark.fromJson({
      'anchor': 'page:1',
      'tool': 'highlight',
      'text': '',
      'points': [],
      'rects': [
        [.075, .1, .6, .12],
      ],
    });
    final fixed = displayedMarkRect(
      legacy,
      legacy.rects.single,
      const Size(600, 800),
    );
    expect(fixed.left, closeTo(.1, .000001));
    expect(fixed.right, closeTo(.8, .000001));
    expect(fixed.top, .1);
    final fresh = DocumentMark(
      anchor: 'page:1',
      tool: MarkTool.highlight,
      rects: [fixed],
    );
    final reloaded = DocumentMark.fromJson(fresh.toJson());
    expect(
      displayedMarkRect(reloaded, reloaded.rects.single, const Size(600, 800)),
      fixed,
    );
    final landscape = displayedMarkRect(
      legacy,
      const Rect.fromLTRB(.1, .075, .2, .6),
      const Size(800, 600),
    );
    expect(landscape.bottom, closeTo(.8, .000001));
    expect(landscape.left, .1);
  });
  test('three selected lines retain their final third and match the viewer selection', () {
    final fragments = <PdfPageTextFragment>[];
    final chars = <PdfRect>[];
    final line = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final content = List.filled(3, line).join('\n');
    for (int row = 0; row < 3; row++) {
      for (int column = 0; column < line.length; column++) {
        // Variable bearings and glyph heights, as found in real embedded fonts.
        chars.add(
          PdfRect(
            40 + column * 12,
            740 - row * 28,
            52 + column * 12,
            726 - row * 28 + (column.isEven ? 2 : 0),
          ),
        );
      }
      if (row < 2) chars.add(PdfRect.empty);
    }
    final text = PdfPageText(
      pageNumber: 1,
      fullText: content,
      charRects: chars,
      fragments: fragments,
    );
    for (int row = 0; row < 3; row++) {
      final start = row * (line.length + 1);
      for (int column = 0; column < line.length; column += 12) {
        final selected = chars.sublist(start + column, start + column + 12);
        fragments.add(
          PdfPageTextFragment(
            pageText: text,
            index: start + column,
            length: 12,
            bounds: PdfRect(
              selected.first.left,
              selected.first.top,
              selected.last.right,
              726 - row * 28,
            ),
            charRects: selected,
            direction: PdfTextDirection.ltr,
          ),
        );
      }
      if (row < 2) {
        fragments.add(
          PdfPageTextFragment(
            pageText: text,
            index: start + line.length,
            length: 1,
            bounds: PdfRect.empty,
            charRects: [PdfRect.empty],
            direction: PdfTextDirection.ltr,
          ),
        );
      }
    }
    final page = _Page();
    for (final range in [
      text.getRangeFromAB(0, content.length - 1),
      text.getRangeFromAB(content.length - 1, 0),
      text.getRangeFromAB(5, content.length - 5),
    ]) {
      final saved = selectedPdfLineRects(range, page);
      final visible = range
          .enumerateFragmentBoundingRects()
          .map((r) {
            final box = r.bounds.toRect(
              page: page,
              scaledPageSize: const Size(600, 800),
            );
            return Rect.fromLTRB(
              box.left / 600,
              box.top / 800,
              box.right / 600,
              box.bottom / 800,
            );
          })
          .where((r) => !r.isEmpty)
          .toList();
      expect(saved.length, 3);
      for (final fragment in visible) {
        expect(
          saved.any(
            (line) =>
                line.left <= fragment.left &&
                line.right >= fragment.right &&
                line.top <= fragment.top &&
                line.bottom >= fragment.bottom,
          ),
          isTrue,
        );
      }
      // The final selected character must remain covered, even in a partial run.
      final last = normalizedPdfMarkRect(chars[range.end - 1], page);
      expect(
        saved.any(
          (r) =>
              r.left <= last.left &&
              r.right >= last.right &&
              r.top <= last.top &&
              r.bottom >= last.bottom,
        ),
        isTrue,
      );
      expect(
        saved
            .where((r) => r.top < .1)
            .map((r) => r.right)
            .reduce((a, b) => a > b ? a : b),
        closeTo((52 + (line.length - 1) * 12) / 600, .00001),
      );
    }
  });
}
