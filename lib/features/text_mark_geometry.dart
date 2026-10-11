import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Persist precisely the rectangles painted by the viewer's selection preview.
List<Rect> selectedPdfLineRects(PdfPageTextRange range, PdfPage page) {
  final rectangles = <Rect>[];
  // Match the viewer's visible selection exactly, including partial fragments.
  // Glyph boxes can have zero height (spaces) or unusual bearings; regrouping
  // them independently made the saved mark differ from the selection preview.
  for (final fragment in range.enumerateFragmentBoundingRects()) {
    final rect = normalizedPdfMarkRect(fragment.bounds, page);
    if (!rect.isEmpty) rectangles.add(rect);
  }
  return rectangles;
}

Rect normalizedPdfMarkRect(PdfRect bounds, PdfPage page) {
  // toRect preserves aspect ratio with a uniform scale. A 1x1 target therefore
  // compresses portrait-page X coordinates. Convert at the real page size first.
  final rect = bounds.toRect(page: page, scaledPageSize: Size(page.width, page.height));
  return Rect.fromLTRB(rect.left / page.width, rect.top / page.height,
    rect.right / page.width, rect.bottom / page.height);
}

List<Rect> selectedCharacterLines(List<Rect> characters, String text, {bool vertical = false}) {
  final lines = <Rect>[];
  Rect? current;
  Rect? previous;
  void finish() {
    if (current != null) {
      lines.add(current!);
    }
    current = null;
    previous = null;
  }
  for (int i = 0; i < characters.length; i++) {
    if (i < text.length && (text[i] == '\n' || text[i] == '\r')) {
      finish();
      continue;
    }
    final rect = characters[i];
    if (rect.isEmpty) continue;
    if (previous != null) {
      final p = previous!;
      final sameRow = (p.center.dy - rect.center.dy).abs() <= (p.height + rect.height) * .3;
      final sameColumn = (p.center.dx - rect.center.dx).abs() <= (p.width + rect.width) * .3;
      final adjacentAcross = sameRow && (p.center.dx - rect.center.dx).abs() <= (p.width + rect.width) / 2 + (p.height + rect.height) * 2;
      final adjacentDown = sameColumn && (p.center.dy - rect.center.dy).abs() <= (p.height + rect.height) / 2 + (p.width + rect.width) * 2;
      if (!(vertical ? adjacentDown : adjacentAcross)) {
        finish();
      }
    }
    current = current == null ? rect : current!.expandToInclude(rect);
    previous = rect;
  }
  finish();
  return lines;
}
