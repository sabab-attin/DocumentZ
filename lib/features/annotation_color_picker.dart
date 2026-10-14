import 'dart:math' as math;

import 'package:flutter/material.dart';

Future<Color?> pickAnnotationColor(
  BuildContext context, {
  Color initial = Colors.black,
}) => showModalBottomSheet<Color>(
  context: context,
  isScrollControlled: true,
  builder: (_) => _ColorPicker(initial: initial),
);

class _ColorPicker extends StatefulWidget {
  const _ColorPicker({required this.initial});
  final Color initial;
  @override
  State<_ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<_ColorPicker> {
  late HSVColor hsv = HSVColor.fromColor(widget.initial);
  void choose(Offset point, double side) {
    final center = Offset(side / 2, side / 2);
    final delta = point - center;
    final hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
    setState(
      () => hsv = hsv
          .withValue(hsv.value == 0 ? 1 : hsv.value)
          .withHue(hue)
          .withSaturation((delta.distance / (side / 2)).clamp(0, 1)),
    );
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Annotation color',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SizedBox.square(
              dimension: 240,
              child: GestureDetector(
                onPanDown: (event) => choose(event.localPosition, 240),
                onPanUpdate: (event) => choose(event.localPosition, 240),
                child: CustomPaint(painter: _WheelPainter(hsv)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Brightness'),
            Slider(
              value: hsv.value,
              onChanged: (value) => setState(() => hsv = hsv.withValue(value)),
            ),
            Wrap(
              spacing: 12,
              children: [
                for (final color in const [
                  Colors.black,
                  Colors.white,
                  Colors.red,
                  Colors.yellow,
                  Colors.green,
                  Colors.blue,
                  Colors.purple,
                ])
                  Semantics(
                    label: color == Colors.black
                        ? 'Black'
                        : color == Colors.white
                        ? 'White'
                        : 'Color preset',
                    child: InkWell(
                      onTap: () =>
                          setState(() => hsv = HSVColor.fromColor(color)),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '#${hsv.toColor().toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, hsv.toColor()),
              icon: const Icon(Icons.check),
              label: const Text('Use color'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WheelPainter extends CustomPainter {
  const _WheelPainter(this.hsv);
  final HSVColor hsv;
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final bounds = Offset.zero & size;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = SweepGradient(
          colors: [
            for (var i = 0; i <= 12; i++)
              HSVColor.fromAHSV(1, i * 30, 1, hsv.value).toColor(),
          ],
        ).createShader(bounds),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(Colors.black, Colors.white, hsv.value)!,
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(bounds),
    );
    final angle = hsv.hue * math.pi / 180;
    final position =
        center +
        Offset(math.cos(angle), math.sin(angle)) * radius * hsv.saturation;
    canvas.drawCircle(
      position,
      7,
      Paint()
        ..color = Colors.black
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      position,
      7,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _WheelPainter old) => old.hsv != hsv;
}
