import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Use the actual visible page or spread, not the full document or screen.
Rect pdfVisiblePageArea(List<Rect> pages, int page, {required bool dual}) {
  if (pages.isEmpty) return Rect.zero;
  var index = (page - 1).clamp(0, pages.length - 1).toInt();
  if (dual) index -= index % 2;
  var rect = pages[index];
  if (dual && index + 1 < pages.length) {
    rect = rect.expandToInclude(pages[index + 1]);
  }
  return rect;
}

double pdfFitZoom(Rect area, Size viewport, {required bool widthOnly}) {
  if (area.isEmpty || viewport.isEmpty) return 1;
  final width = viewport.width / area.width;
  return widthOnly ? width : math.min(width, viewport.height / area.height);
}

Offset pdfWidthFittedCenter(
  double documentWidth,
  Size viewport,
  double sourceTop,
) {
  if (documentWidth <= 0 || viewport.isEmpty) return Offset.zero;
  final zoom = viewport.width / documentWidth;
  return Offset(documentWidth / 2, sourceTop + viewport.height / (2 * zoom));
}
