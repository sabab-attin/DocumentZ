import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Shared across every page: a second finger cancels ink even on another page.
class ReaderGestureSession extends ValueNotifier<bool> {
  ReaderGestureSession() : super(false);
}

class ReaderGestureSurface extends StatefulWidget {
  const ReaderGestureSurface({super.key, required this.session, required this.active,
    required this.child, required this.onNavigate, this.onSwipe});
  final ReaderGestureSession session;
  final bool active;
  final Widget child;
  final void Function(Offset delta, Offset focal, double scale) onNavigate;
  final ValueChanged<int>? onSwipe;
  @override
  State<ReaderGestureSurface> createState() => _ReaderGestureSurfaceState();
}

class _ReaderGestureSurfaceState extends State<ReaderGestureSurface> {
  final touches = <int, Offset>{};
  Offset? start;
  bool navigated = false;
  Offset get focal => touches.values.reduce((a, b) => a + b) / touches.length.toDouble();
  double get span => touches.length < 2 ? 0 : (touches.values.first - touches.values.last).distance;
  void down(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.touch) return;
    touches[e.pointer] = e.localPosition;
    if (touches.length == 1) { start = e.localPosition; navigated = false; }
    if (touches.length >= 2) { navigated = true; widget.session.value = true; }
  }
  void move(PointerMoveEvent e) {
    if (!touches.containsKey(e.pointer)) return;
    final oldFocal = focal, oldSpan = span;
    touches[e.pointer] = e.localPosition;
    if (widget.active && touches.length >= 2) {
      widget.onNavigate(focal - oldFocal, focal, oldSpan > 0 ? span / oldSpan : 1);
    }
  }
  void up(PointerEvent e, {bool cancelled = false}) {
    if (!touches.containsKey(e.pointer)) return;
    if (!cancelled && !widget.active && !navigated && touches.length == 1 && start != null) {
      final delta = e.localPosition - start!;
      if (delta.dx.abs() > 60 && delta.dx.abs() > delta.dy.abs() * 1.5) {
        widget.onSwipe?.call(delta.dx < 0 ? 1 : -1);
      }
    }
    touches.remove(e.pointer);
    // Do not resume ink until BOTH fingers are lifted.
    if (touches.isEmpty) widget.session.value = false;
  }
  @override
  Widget build(BuildContext context) => Listener(behavior: HitTestBehavior.translucent,
    onPointerDown: down, onPointerMove: move, onPointerUp: up,
    onPointerCancel: (e) => up(e, cancelled: true), child: widget.child);
}

/// Immediate input, independent of Flutter's long-press and drag thresholds.
class ImmediateMarkSurface extends StatefulWidget {
  const ImmediateMarkSurface({super.key, this.session, required this.onStart,
    required this.onUpdate, required this.onEnd, required this.onCancel});
  final ReaderGestureSession? session;
  final ValueChanged<Offset> onStart, onUpdate;
  final VoidCallback onEnd, onCancel;
  @override
  State<ImmediateMarkSurface> createState() => _ImmediateMarkSurfaceState();
}
class _ImmediateMarkSurfaceState extends State<ImmediateMarkSurface> {
  int? pointer;
  final pointers = <int>{};
  bool blocked = false;
  @override
  void initState() { super.initState(); widget.session?.addListener(cancelForNavigation); }
  @override
  void didUpdateWidget(covariant ImmediateMarkSurface old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session?.removeListener(cancelForNavigation);
      widget.session?.addListener(cancelForNavigation);
    }
  }
  void cancelForNavigation() {
    if (widget.session?.value == true && pointers.isNotEmpty) { blocked = true; pointer = null; widget.onCancel(); }
  }
  @override
  void dispose() { widget.session?.removeListener(cancelForNavigation); super.dispose(); }
  @override
  Widget build(BuildContext context) => RawGestureDetector(behavior: HitTestBehavior.opaque,
    gestures: {EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
      EagerGestureRecognizer.new, (_) {})},
    child: Listener(behavior: HitTestBehavior.opaque,
      onPointerDown: (e) {
        pointers.add(e.pointer);
        if (pointers.length > 1 || widget.session?.value == true) {
          blocked = true; pointer = null; widget.onCancel(); return;
        }
        if (!blocked) { pointer = e.pointer; widget.onStart(e.localPosition); }
      },
      onPointerMove: (e) { if (pointer == e.pointer && !blocked) widget.onUpdate(e.localPosition); },
      onPointerUp: (e) {
        if (pointer == e.pointer && !blocked) widget.onEnd();
        pointers.remove(e.pointer); pointer = null;
        if (pointers.isEmpty) blocked = false;
      },
      onPointerCancel: (e) {
        pointers.remove(e.pointer); pointer = null; widget.onCancel();
        if (pointers.isEmpty) blocked = false;
      },
      child: const SizedBox.expand()));
}
