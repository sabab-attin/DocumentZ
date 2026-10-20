import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// At best fit, each page's visible viewport remains inside its own slot.
PdfPageLayout desktopSinglePdfLayout(Iterable<Size> source, Size viewport) {
  final pages = source.toList();
  if (pages.isEmpty) {
    return PdfPageLayout(pageLayouts: const [], documentSize: Size.zero);
  }
  final aspect = viewport.width / math.max(1, viewport.height);
  final slot =
      pages.fold<double>(
        0,
        (value, page) =>
            math.max(value, math.max(page.width, page.height * aspect)),
      ) +
      32;
  final height = pages.fold<double>(
    0,
    (value, page) => math.max(value, page.height),
  );
  return PdfPageLayout(
    pageLayouts: [
      for (var i = 0; i < pages.length; i++)
        Rect.fromLTWH(
          i * slot + (slot - pages[i].width) / 2,
          (height - pages[i].height) / 2,
          pages[i].width,
          pages[i].height,
        ),
    ],
    documentSize: Size(slot * pages.length, height),
  );
}
