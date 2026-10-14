import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/continuous_pdf_layout.dart';

void main() {
  test('mixed portrait and landscape pages meet both edges without distortion or gutters', () {
    final pages = [
      const Size(595, 842),
      const Size(842, 595),
      const Size(300, 900),
    ];
    final layout = continuousPdfLayout(pages);
    for (var i = 0; i < pages.length; i++) {
      final rect = layout.pageLayouts[i];
      expect(rect.left, 0);
      expect(rect.right, layout.documentSize.width);
      expect(
        rect.width / rect.height,
        closeTo(pages[i].width / pages[i].height, .000001),
      );
      if (i == 0) {
        expect(rect.top, 0);
      } else {
        expect(rect.top, layout.pageLayouts[i - 1].bottom);
      }
    }
    expect(layout.pageLayouts.last.bottom, layout.documentSize.height);
  });
  test('empty document layout has no artificial padding', () {
    final layout = continuousPdfLayout([]);
    expect(layout.pageLayouts, isEmpty);
    expect(layout.documentSize, Size.zero);
  });
}
