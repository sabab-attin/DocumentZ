import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Cached, offline paper grain. No assets, network requests or animation.
class BookPaper extends StatelessWidget {
  const BookPaper({
    super.key,
    required this.paper,
    this.columns = 1,
    this.enabled = true,
    required this.child,
  });
  final Color paper;
  final int columns;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => !enabled
      ? ColoredBox(color: paper, child: child)
      : Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _PaperPainter(paper, columns)),
                  ),
                ),
              ),
            ),
            child,
          ],
        );
}

class _PaperPainter extends CustomPainter {
  _PaperPainter(this.paper, this.columns);
  final Color paper;
  final int columns;
  static final ui.Picture _light = _tile(false);
  static final ui.Picture _dark = _tile(true);
  static const double tileSize = 192;

  static ui.Picture _tile(bool dark) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, tileSize, tileSize),
    );
    var seed = 731;
    double random() {
      seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
      return seed / 0x80000000;
    }

    final paint = Paint()..strokeCap = StrokeCap.round;
    // Fine mottling, with wrapped fibers so the tile has no visible seam.
    for (var i = 0; i < 2600; i++) {
      paint.color = (i.isEven ? Colors.white : const Color(0xff544737))
          .withValues(alpha: dark ? .045 : .055);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(random() * tileSize, random() * tileSize),
          width: .4 + random() * 2,
          height: .5 + random() * 2.5,
        ),
        paint,
      );
    }
    for (var i = 0; i < 420; i++) {
      final x = random() * tileSize;
      final y = random() * tileSize;
      final delta = Offset(random() * 3 - 1.5, 1 + random() * 7);
      paint
        ..color = (i.isEven ? Colors.white : Colors.black).withValues(
          alpha: dark ? .055 : .035,
        )
        ..strokeWidth = .3 + random() * .5;
      for (final dx in [-tileSize, 0.0, tileSize]) {
        for (final dy in [-tileSize, 0.0, tileSize]) {
          final start = Offset(x + dx, y + dy);
          canvas.drawLine(start, start + delta, paint);
        }
      }
    }
    return recorder.endRecording();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dark = paper.computeLuminance() < .2;
    final base = Color.lerp(
      paper,
      dark ? const Color(0xff292824) : const Color(0xffeae4d7),
      dark ? .78 : .62,
    )!;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    final tile = dark ? _dark : _light;
    for (var y = 0.0; y < size.height; y += tileSize) {
      for (var x = 0.0; x < size.width; x += tileSize) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPicture(tile);
        canvas.restore();
      }
    }
    // A broad, soft paper tone gives depth without a heavy edge or frame.
    final bounds = Offset.zero & size;
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = RadialGradient(
          radius: .95,
          colors: [
            Colors.white.withValues(alpha: dark ? .015 : .04),
            Colors.transparent,
            Colors.black.withValues(alpha: dark ? .035 : .045),
          ],
          stops: const [0, .65, 1],
        ).createShader(bounds),
    );
    if (columns == 2) {
      final gutter = Rect.fromLTWH(size.width / 2 - 10, 0, 20, size.height);
      canvas.drawRect(
        gutter,
        Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: dark ? .12 : .045),
              Colors.transparent,
            ],
          ).createShader(gutter),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PaperPainter oldDelegate) =>
      oldDelegate.paper != paper || oldDelegate.columns != columns;
}
