import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/desktop_platform.dart';
import '../core/reader_shortcuts.dart';
import 'reader_controls.dart';

/// Desktop navigation leaves editing keys and native continuous scrolling alone.
class DesktopPageInput extends StatefulWidget {
  const DesktopPageInput({
    super.key,
    required this.child,
    this.onTurn,
    this.wheelPaging = false,
  });
  final Widget child;
  final Future<void> Function(int)? onTurn;
  final bool wheelPaging;
  @override
  State<DesktopPageInput> createState() => _DesktopPageInputState();
}

class _DesktopPageInputState extends State<DesktopPageInput> {
  final _wheelClock = Stopwatch()..start();
  int _lastWheel = -150;
  double _wheelDelta = 0;
  bool get _menuOpen => ReaderControlsScope.of(context)?.value == true;

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (_menuOpen || readerIsEditingText() || event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final settings = ReaderControlsScope.scopeOf(context)
        ?.preferences
        ?.globalDefaults
        .shortcuts;
    final command = settings?.match(event);
    if (command == ReaderCommand.next || command == ReaderCommand.previous) {
      unawaited(widget.onTurn!(command == ReaderCommand.next ? 1 : -1));
      return KeyEventResult.handled;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final direction =
        ((settings == null && key == LogicalKeyboardKey.pageDown) ||
            key == LogicalKeyboardKey.arrowRight)
        ? 1
        : ((settings == null && key == LogicalKeyboardKey.pageUp) ||
              key == LogicalKeyboardKey.arrowLeft)
        ? -1
        : 0;
    if (direction == 0) return KeyEventResult.ignored;
    unawaited(widget.onTurn!(direction));
    return KeyEventResult.handled;
  }

  void _wheel(PointerSignalEvent event) {
    if (!widget.wheelPaging ||
        _menuOpen ||
        event is! PointerScrollEvent ||
        HardwareKeyboard.instance.isControlPressed ||
        event.scrollDelta.dy == 0) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      final delta = event.scrollDelta.dy;
      if (_wheelDelta.sign != delta.sign) _wheelDelta = 0;
      _wheelDelta += delta;
      final now = _wheelClock.elapsedMilliseconds;
      if (_wheelDelta.abs() >= 40 && now - _lastWheel >= 150) {
        _lastWheel = now;
        final direction = _wheelDelta > 0 ? 1 : -1;
        _wheelDelta = 0;
        unawaited(widget.onTurn!(direction));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!isWindowsDesktop || widget.onTurn == null) return widget.child;
    return Focus(
      autofocus: true,
      onKeyEvent: _key,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _wheel,
        child: widget.child,
      ),
    );
  }
}
