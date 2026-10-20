import '../core/desktop_platform.dart';
import 'desktop_page_input.dart';

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The outgoing page is captured once; the live destination remains underneath.
/// A textured cylindrical paper mesh bends the snapshot without rerendering the
/// document on each frame. The underside is paper, rather than a moving curtain.
class PageTurn extends StatefulWidget {
  const PageTurn({
    super.key,
    required this.child,
    required this.paper,
    this.onTurn,
    this.wheelPaging = false,
  });
  final Widget child;
  final Future<void> Function(int)? onTurn;
  final bool wheelPaging;
  final Color paper;
  @override
  State<PageTurn> createState() => PageTurnState();
}

class PageTurnState extends State<PageTurn>
    with SingleTickerProviderStateMixin {
  final boundary = GlobalKey();
  late final animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  ui.Image? snapshot;
  ui.ImageShader? snapshotShader;
  int direction = 1;
  bool busy = false;
  bool _desktopTransition = false;
  Future<void> turn(int nextDirection, VoidCallback changePage) async {
    if (busy) return;
    if (MediaQuery.of(context).disableAnimations) {
      changePage();
      return;
    }
    busy = true;
    if (isWindowsDesktop) {
      try {
        animation.value = 0;
        setState(() {
          direction = nextDirection;
          _desktopTransition = true;
        });
        changePage();
        await animation.animateTo(
          1,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      } finally {
        if (mounted) setState(() => _desktopTransition = false);
        busy = false;
      }
      return;
    }
    try {
      final box =
          boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null || box.debugNeedsPaint) {
        changePage();
        return;
      }
      // Bound texture memory and readback cost on high-density phones/tablets.
      final area = box.size.width * box.size.height;
      final ratio = math.min(
        MediaQuery.devicePixelRatioOf(context),
        math.min(1.5, math.sqrt(900000 / math.max(1.0, area))),
      );
      // Schedule rasterization without waiting for GPU completion before the
      // destination page can move. The image remains owned until animation ends.
      final ui.Image image;
      try {
        image = box.toImageSync(pixelRatio: ratio);
      } catch (_) {
        changePage();
        return;
      }
      if (!mounted) {
        image.dispose();
        return;
      }
      // Reset before replacing the live page: a previous turn ends at 1.
      animation.value = 0;
      setState(() {
        snapshot = image;
        snapshotShader = ui.ImageShader(
          image,
          TileMode.clamp,
          TileMode.clamp,
          Matrix4.identity().storage,
          filterQuality: FilterQuality.medium,
        );
        direction = nextDirection;
      });
      changePage();
      // Paint the destination under the complete outgoing snapshot before moving.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await animation.forward(from: 0);
    } finally {
      if (mounted) {
        setState(() {
          snapshotShader?.dispose();
          snapshotShader = null;
          snapshot?.dispose();
          snapshot = null;
        });
      }
      busy = false;
    }
  }

  @override
  void dispose() {
    animation.dispose();
    snapshotShader?.dispose();
    snapshot?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DesktopPageInput(
    onTurn: widget.onTurn,
    wheelPaging: widget.wheelPaging,
    child: Stack(
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: animation,
            child: RepaintBoundary(key: boundary, child: widget.child),
            builder: (context, child) => !isWindowsDesktop
                ? child!
                : ClipRect(
                    child: ColoredBox(
                      color: widget.paper,
                      child: Transform.translate(
                        offset: Offset(
                          _desktopTransition
                              ? direction * (1 - animation.value) * 64
                              : 0,
                          0,
                        ),
                        child: child,
                      ),
                    ),
                  ),
          ),
        ),
        if (snapshot != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _CurlPainter(
                    snapshot!,
                    snapshotShader!,
                    animation,
                    direction,
                    widget.paper,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _CurlPainter extends CustomPainter {
  _CurlPainter(
    this.image,
    this.shader,
    this.animation,
    this.direction,
    this.paper,
  ) : super(repaint: animation);
  final ui.Image image;
  final ui.ImageShader shader;
  final Animation<double> animation;
  double get progress => Curves.easeOutCubic.transform(animation.value);
  final int direction;
  final Color paper;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress >= 1) return;
    if (progress <= 0) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Offset.zero & size,
        Paint(),
      );
      return;
    }
    final radius = size.width * .075;
    final fold = size.width - progress * (size.width + math.pi * radius);
    final tilt = math.sin(progress * math.pi) * size.width * .10;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    double creaseAt(double y) {
      final x = (fold + tilt * (y / size.height - .5)).clamp(0.0, size.width);
      return direction > 0 ? x : size.width - x;
    }

    // Most of the page is still flat: one image draw, with a small mesh only at
    // the curl. Avoid thousands of textured triangles for unbent paragraphs.
    final flat = Path()
      ..moveTo(direction > 0 ? 0 : size.width, 0)
      ..lineTo(creaseAt(0), 0)
      ..lineTo(creaseAt(size.height), size.height)
      ..lineTo(direction > 0 ? 0 : size.width, size.height)
      ..close();
    canvas.save();
    canvas.clipPath(flat);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint(),
    );
    canvas.restore();
    final front = <Offset>[], texture = <Offset>[], back = <Offset>[];
    final frontColors = <Color>[], backColors = <Color>[];
    Offset project(double x, double y) {
      final crease = fold + tilt * (y / size.height - .5);
      final distance = x - crease;
      final mapped = distance <= 0
          ? x
          : crease + radius * math.sin((distance / radius).clamp(0, math.pi));
      return Offset(direction > 0 ? mapped : size.width - mapped, y);
    }

    const columns = 96, rows = 8;
    for (int row = 0; row < rows; row++) {
      final yMid = (row + .5) * size.height / rows;
      final rowCrease = fold + tilt * (yMid / size.height - .5);
      final firstColumn = ((rowCrease * columns / size.width).floor() - 1)
          .clamp(0, columns)
          .toInt();
      final lastColumn =
          (((rowCrease + math.pi * radius) * columns / size.width).ceil() + 1)
              .clamp(0, columns)
              .toInt();
      for (int col = firstColumn; col < lastColumn; col++) {
        final x0 = col * size.width / columns,
            x1 = (col + 1) * size.width / columns;
        final y0 = row * size.height / rows,
            y1 = (row + 1) * size.height / rows;
        final middle =
            (x0 + x1) / 2 -
            (fold + tilt * ((y0 + y1) / (2 * size.height) - .5));
        if (middle < -size.width / columns) continue;
        if (middle > math.pi * radius) continue;
        final underside = middle > math.pi * radius / 2;
        for (final p in [
          Offset(x0, y0),
          Offset(x1, y0),
          Offset(x1, y1),
          Offset(x0, y0),
          Offset(x1, y1),
          Offset(x0, y1),
        ]) {
          final angle =
              ((p.dx - fold - tilt * (p.dy / size.height - .5)) / radius).clamp(
                0.0,
                math.pi,
              );
          if (underside) {
            back.add(project(p.dx, p.dy));
            backColors.add(
              Color.lerp(
                paper,
                Colors.grey,
                .08 + .22 * math.sin(angle).abs(),
              )!,
            );
          } else {
            front.add(project(p.dx, p.dy));
            texture.add(
              Offset(
                (direction > 0 ? p.dx : size.width - p.dx) *
                    image.width /
                    size.width,
                p.dy * image.height / size.height,
              ),
            );
            frontColors.add(
              Color.lerp(
                Colors.white,
                Colors.black,
                .18 * math.sin(angle).abs(),
              )!,
            );
          }
        }
      }
    }
    final shadow = Path();
    for (int row = 0; row <= rows; row++) {
      final y = row * size.height / rows;
      final x = fold + tilt * (y / size.height - .5) + radius;
      final p = Offset(direction > 0 ? x : size.width - x, y);
      if (row == 0) {
        shadow.moveTo(p.dx, p.dy);
      } else {
        shadow.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Colors.black.withValues(alpha: .18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * .45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    if (front.isNotEmpty) {
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        front,
        textureCoordinates: texture,
        colors: frontColors,
      );

      canvas.drawVertices(mesh, BlendMode.modulate, Paint()..shader = shader);

      mesh.dispose();
    }
    if (back.isNotEmpty) {
      final mesh = ui.Vertices(
        ui.VertexMode.triangles,
        back,
        colors: backColors,
      );
      canvas.drawVertices(
        mesh,
        BlendMode.modulate,
        Paint()..color = Colors.white,
      );
      mesh.dispose();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CurlPainter old) =>
      old.animation != animation ||
      old.image != image ||
      old.direction != direction ||
      old.paper != paper;
}
