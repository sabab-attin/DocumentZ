import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// Give every page the same display width without cropping or stretching it.
/// Overlays continue to use the page's normalized coordinates.
PdfPageLayout continuousPdfLayout(Iterable<Size> pageSizes) {
  final sizes = pageSizes.toList();
  if (sizes.isEmpty) {
    return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
  }
  final width = sizes.fold<double>(
    0,
    (value, page) => page.width > value ? page.width : value,
  );
  var top = 0.0;
  final rectangles = <Rect>[];
  for (final size in sizes) {
    final height = width * size.height / size.width;
    rectangles.add(Rect.fromLTWH(0, top, width, height));
    top += height;
  }
  return PdfPageLayout(pageLayouts: rectangles, documentSize: Size(width, top));
}
