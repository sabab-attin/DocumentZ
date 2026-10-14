import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/continuous_marks.dart';

void main() {
  test('bridges word spaces while preserving lines and separate columns', () {
    final lines = continuousMarkRects([
      const Rect.fromLTWH(0, 0, 20, 12),
      const Rect.fromLTWH(25, 0, 25, 12),
      const Rect.fromLTWH(55, 1, 20, 11),
      const Rect.fromLTWH(0, 24, 25, 12),
      const Rect.fromLTWH(150, 0, 30, 12),
    ]);
    expect(lines.length, 3);
    expect(lines.first, const Rect.fromLTRB(0, 0, 75, 12));
  });
  test('handles reversed RTL ordering and rotated page marks', () {
    expect(
      continuousMarkRects([
        const Rect.fromLTWH(30, 0, 20, 12),
        const Rect.fromLTWH(0, 0, 25, 12),
      ]),
      [const Rect.fromLTRB(0, 0, 50, 12)],
    );
    expect(
      continuousMarkRects([
        const Rect.fromLTWH(0, 0, 12, 20),
        const Rect.fromLTWH(0, 25, 12, 25),
      ], vertical: true),
      [const Rect.fromLTRB(0, 0, 12, 50)],
    );
  });
}
