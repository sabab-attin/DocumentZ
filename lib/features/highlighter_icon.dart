import 'package:flutter/material.dart';

/// A chisel-tip marker, rather than Material's flashlight-shaped highlight icon.
class HighlighterIcon extends StatelessWidget {
  const HighlighterIcon({super.key, this.size, this.color});
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final extent = size ?? theme.size ?? 24;
    return SizedBox.square(
      dimension: extent,
      child: CustomPaint(
        painter: _HighlighterPainter(
          color ?? theme.color ?? Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _HighlighterPainter extends CustomPainter {
  const _HighlighterPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(8, 14)
        ..lineTo(16, 4)
        ..quadraticBezierTo(17, 3, 18, 4)
        ..lineTo(21, 7)
        ..quadraticBezierTo(22, 8, 21, 9)
        ..lineTo(13, 17)
        ..close(),
      stroke,
    );
    canvas.drawPath(
      Path()
        ..moveTo(8, 14)
        ..lineTo(5, 17)
        ..lineTo(5, 20)
        ..lineTo(10, 20)
        ..lineTo(13, 17)
        ..close(),
      Paint()..color = color,
    );
    canvas.drawLine(const Offset(2, 22), const Offset(16, 22), stroke);
  }

  @override
  bool shouldRepaint(covariant _HighlighterPainter old) => old.color != color;
}

class ReaderToolIcon extends StatelessWidget {
  const ReaderToolIcon(this.icon, {super.key, this.size, this.color});
  final IconData? icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) => icon == Icons.border_color
      ? HighlighterIcon(size: size, color: color)
      : Icon(icon, size: size, color: color);
}
