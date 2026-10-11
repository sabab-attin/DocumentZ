import 'package:flutter/material.dart';

class ReaderControlsScope extends InheritedWidget {
  const ReaderControlsScope({super.key, required this.expanded, required super.child});
  final ValueNotifier<bool> expanded;
  static ValueNotifier<bool>? of(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<ReaderControlsScope>()?.expanded;
  @override
  bool updateShouldNotify(ReaderControlsScope oldWidget) => oldWidget.expanded != expanded;
}

/// Controls float over the document; opening them never changes page geometry.
class ReaderControlsOverlay extends StatelessWidget {
  const ReaderControlsOverlay({super.key, required this.child, required this.controls});
  final Widget child, controls;
  @override
  Widget build(BuildContext context) {
    final expanded = ReaderControlsScope.of(context);
    if (expanded == null) return Stack(children: [Positioned.fill(child: child), Positioned(left: 0, right: 0, bottom: 0, child: controls)]);
    return ValueListenableBuilder<bool>(valueListenable: expanded, builder: (context, open, _) => Stack(children: [
      Positioned.fill(child: child),
      if (open) Positioned(left: 0, right: 0, bottom: 56, child: Material(elevation: 8, child: controls)),
    ]));
  }
}
