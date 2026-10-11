import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The outgoing page is captured once; the live destination remains underneath.
/// A textured cylindrical paper mesh bends the snapshot without rerendering the
/// document on each frame. The underside is paper, rather than a moving curtain.
class PageTurn extends StatefulWidget {
  const PageTurn({super.key, required this.child, required this.paper});
  final Widget child;
  final Color paper;
  @override
  State<PageTurn> createState() => PageTurnState();
}
class PageTurnState extends State<PageTurn> with SingleTickerProviderStateMixin {
  final boundary = GlobalKey();
  late final animation = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  ui.Image? snapshot;
  int direction = 1;
  bool busy = false;
  Future<void> turn(int nextDirection, VoidCallback changePage) async {
    if (busy) return;
    if (MediaQuery.of(context).disableAnimations) { changePage(); return; }
    busy = true;
    try {
      final box = boundary.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (box == null || box.debugNeedsPaint) { changePage(); return; }
      final image = await box.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context).clamp(1, 2));
      if (!mounted) { image.dispose(); return; }
      setState(() { snapshot = image; direction = nextDirection; });
      changePage();
      // Paint the destination under the complete outgoing snapshot before moving.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await animation.forward(from: 0);
    } finally {
      if (mounted) setState(() { snapshot?.dispose(); snapshot = null; });
      busy = false;
    }
  }
  @override
  void dispose() { animation.dispose(); snapshot?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Stack(children: [
    Positioned.fill(child: RepaintBoundary(key: boundary, child: widget.child)),
    if (snapshot != null) Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: animation,
      builder: (context, _) => CustomPaint(painter: _CurlPainter(snapshot!,
        Curves.easeInOutSine.transform(animation.value), direction, widget.paper))))),
  ]);
}
class _CurlPainter extends CustomPainter {
  _CurlPainter(this.image, this.progress, this.direction, this.paper);
  final ui.Image image;
  final double progress;
  final int direction;
  final Color paper;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || progress >= 1) return;
    if (progress <= 0) {
      canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Offset.zero & size, Paint());
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
    final flat = Path()..moveTo(direction > 0 ? 0 : size.width, 0)
      ..lineTo(creaseAt(0), 0)..lineTo(creaseAt(size.height), size.height)
      ..lineTo(direction > 0 ? 0 : size.width, size.height)..close();
    canvas.save();
    canvas.clipPath(flat);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Offset.zero & size, Paint());
    canvas.restore();
    final front = <Offset>[], texture = <Offset>[], back = <Offset>[];
    final frontColors = <Color>[], backColors = <Color>[];
    Offset project(double x, double y) {
      final crease = fold + tilt * (y / size.height - .5);
      final distance = x - crease;
      final mapped = distance <= 0 ? x : crease + radius * math.sin((distance / radius).clamp(0, math.pi));
      return Offset(direction > 0 ? mapped : size.width - mapped, y);
    }
    const columns = 160, rows = 12;
    for (int row = 0; row < rows; row++) {
      for (int col = 0; col < columns; col++) {
        final x0 = col * size.width / columns, x1 = (col + 1) * size.width / columns;
        final y0 = row * size.height / rows, y1 = (row + 1) * size.height / rows;
        final middle = (x0 + x1) / 2 - (fold + tilt * ((y0 + y1) / (2 * size.height) - .5));
        if (middle < -size.width / columns) continue;
        if (middle > math.pi * radius) continue;
        final underside = middle > math.pi * radius / 2;
        for (final p in [Offset(x0, y0), Offset(x1, y0), Offset(x1, y1), Offset(x0, y0), Offset(x1, y1), Offset(x0, y1)]) {
          final angle = ((p.dx - fold - tilt * (p.dy / size.height - .5)) / radius).clamp(0.0, math.pi);
          if (underside) {
            back.add(project(p.dx, p.dy));
            backColors.add(Color.lerp(paper, Colors.grey, .08 + .22 * math.sin(angle).abs())!);
          } else {
            front.add(project(p.dx, p.dy));
            texture.add(Offset((direction > 0 ? p.dx : size.width - p.dx) * image.width / size.width, p.dy * image.height / size.height));
            frontColors.add(Color.lerp(Colors.white, Colors.black, .18 * math.sin(angle).abs())!);
          }
        }
      }
    }
    final shadow = Path();
    for (int row = 0; row <= rows; row++) {
      final y = row * size.height / rows;
      final x = fold + tilt * (y / size.height - .5) + radius;
      final p = Offset(direction > 0 ? x : size.width - x, y);
      if (row == 0) { shadow.moveTo(p.dx, p.dy); } else { shadow.lineTo(p.dx, p.dy); }
    }
    canvas.drawPath(shadow, Paint()..color = Colors.black.withValues(alpha: .18)..style = PaintingStyle.stroke
      ..strokeWidth = radius * .45..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    if (front.isNotEmpty) {
      final mesh = ui.Vertices(ui.VertexMode.triangles, front, textureCoordinates: texture, colors: frontColors);
      final shader = ui.ImageShader(image, TileMode.clamp, TileMode.clamp, Matrix4.identity().storage, filterQuality: FilterQuality.medium);
      canvas.drawVertices(mesh, BlendMode.modulate, Paint()..shader = shader);
      shader.dispose(); mesh.dispose();
    }
    if (back.isNotEmpty) {
      final mesh = ui.Vertices(ui.VertexMode.triangles, back, colors: backColors);
      canvas.drawVertices(mesh, BlendMode.modulate, Paint()..color = Colors.white);
      mesh.dispose();
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(_CurlPainter old) => old.progress != progress || old.image != image || old.direction != direction || old.paper != paper;
}
