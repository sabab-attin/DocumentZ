import 'package:flutter/material.dart';

/// Bridge word spaces on one line without joining separate lines or columns.
/// Coordinates must be physical layout coordinates, not aspect-scaled units.
List<Rect> continuousMarkRects(Iterable<Rect> input, {bool vertical = false}) {
  final result = <Rect>[];
  for (final rect in input.where((r) => !r.isEmpty)) {
    var joined = rect;
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = 0; i < result.length; i++) {
        final other = result[i];
        final height = vertical ? joined.width : joined.height;
        final otherHeight = vertical ? other.width : other.height;
        final thickness = height > otherHeight ? height : otherHeight;
        final crossDistance = vertical
            ? (joined.center.dx - other.center.dx).abs()
            : (joined.center.dy - other.center.dy).abs();
        final gap = vertical
            ? (joined.top > other.top
                  ? joined.top - other.bottom
                  : other.top - joined.bottom)
            : (joined.left > other.left
                  ? joined.left - other.right
                  : other.left - joined.right);
        if (crossDistance <= thickness * .35 && gap <= thickness * 2) {
          joined = joined.expandToInclude(other);
          result.removeAt(i);
          changed = true;
          break;
        }
      }
    }
    result.add(joined);
  }
  return result;
}
