import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ReaderCommand {
  undo('Undo', LogicalKeyboardKey.keyZ, control: true),
  save('Save annotations', LogicalKeyboardKey.keyS, control: true),
  find('Find in document', LogicalKeyboardKey.keyF, control: true),
  goTo('Go to page', LogicalKeyboardKey.keyG, control: true),
  bookmark('Bookmark page', LogicalKeyboardKey.keyD, control: true),
  highlight('Highlight', LogicalKeyboardKey.keyH, control: true, shift: true),
  underline('Underline', LogicalKeyboardKey.keyU, control: true, shift: true),
  note('Add note', LogicalKeyboardKey.keyN, control: true, shift: true),
  browse('Read / scroll', LogicalKeyboardKey.keyB, control: true, shift: true),
  next('Next page', LogicalKeyboardKey.pageDown),
  previous('Previous page', LogicalKeyboardKey.pageUp),
  fullscreen('Full screen', LogicalKeyboardKey.f11),
  toolbar('Show / hide toolbar', LogicalKeyboardKey.f9);

  const ReaderCommand(
    this.label,
    this.key, {
    this.control = false,
    this.shift = false,
  });
  final String label;
  final LogicalKeyboardKey key;
  final bool control, shift;
  ReaderKey get defaultKey =>
      ReaderKey(key.keyId, control: control, shift: shift);
}

@immutable
class ReaderKey {
  const ReaderKey(
    this.keyId, {
    this.control = false,
    this.alt = false,
    this.shift = false,
  });
  final int keyId;
  final bool control, alt, shift;
  bool matches(KeyEvent event) =>
      event.logicalKey.keyId == keyId &&
      HardwareKeyboard.instance.isControlPressed == control &&
      HardwareKeyboard.instance.isAltPressed == alt &&
      HardwareKeyboard.instance.isShiftPressed == shift &&
      !HardwareKeyboard.instance.isMetaPressed;
  String get label => [
    if (control) 'Ctrl',
    if (alt) 'Alt',
    if (shift) 'Shift',
    LogicalKeyboardKey.findKeyByKeyId(keyId)?.keyLabel ?? 'Key $keyId',
  ].join('+');
  Map<String, Object> toJson() => {
    'key': keyId,
    'ctrl': control,
    'alt': alt,
    'shift': shift,
  };
  bool get allowed {
    final key = LogicalKeyboardKey.findKeyByKeyId(keyId);
    if (alt && key == LogicalKeyboardKey.f4) {
      return false;
    }
    if (control && alt && key == LogicalKeyboardKey.delete) {
      return false;
    }
    if (key == null ||
        LogicalKeyboardKey.isControlCharacter(key.keyLabel) ||
        [
          LogicalKeyboardKey.escape,
          LogicalKeyboardKey.tab,
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altRight,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaRight,
        ].contains(key)) {
      return false;
    }
    if (control &&
        !alt &&
        !shift &&
        [
          LogicalKeyboardKey.keyC,
          LogicalKeyboardKey.keyV,
          LogicalKeyboardKey.keyX,
          LogicalKeyboardKey.keyA,
        ].contains(key)) {
      return false;
    }
    return control ||
        alt ||
        [
          LogicalKeyboardKey.pageUp,
          LogicalKeyboardKey.pageDown,
          LogicalKeyboardKey.f1,
          LogicalKeyboardKey.f2,
          LogicalKeyboardKey.f3,
          LogicalKeyboardKey.f4,
          LogicalKeyboardKey.f5,
          LogicalKeyboardKey.f6,
          LogicalKeyboardKey.f7,
          LogicalKeyboardKey.f8,
          LogicalKeyboardKey.f9,
          LogicalKeyboardKey.f10,
          LogicalKeyboardKey.f11,
          LogicalKeyboardKey.f12,
        ].contains(key);
  }

  @override
  bool operator ==(Object other) =>
      other is ReaderKey &&
      other.keyId == keyId &&
      other.control == control &&
      other.alt == alt &&
      other.shift == shift;
  @override
  int get hashCode => Object.hash(keyId, control, alt, shift);
}

class ReaderShortcuts extends ChangeNotifier {
  ReaderShortcuts(this.store) {
    try {
      final data = jsonDecode(
        store?.getString('desktop.readerShortcuts') ?? '{}',
      ) as Map;
      for (final command in ReaderCommand.values) {
        final value = data[command.name];
        if (value is Map && value['key'] is int) {
          final key = ReaderKey(
            value['key'],
            control: value['ctrl'] == true,
            alt: value['alt'] == true,
            shift: value['shift'] == true,
          );
          if (key.allowed) _keys[command] = key;
        }
      }
      // Reject conflicting saved bindings as a set, preserving reliable defaults.
      if (ReaderCommand.values.map(binding).toSet().length !=
          ReaderCommand.values.length) {
        _keys.clear();
      }
    } catch (_) {
      _keys.clear();
    }
  }
  final SharedPreferences? store;
  final _keys = <ReaderCommand, ReaderKey>{};
  bool saveFailed = false;
  ReaderKey binding(ReaderCommand command) =>
      _keys[command] ?? command.defaultKey;
  ReaderCommand? match(KeyEvent event) {
    for (final command in ReaderCommand.values) {
      if (binding(command).matches(event)) return command;
    }
    return null;
  }

  Future<bool> setBinding(ReaderCommand command, ReaderKey key) async {
    if (!key.allowed ||
        ReaderCommand.values.any((c) => c != command && binding(c) == key)) {
      return false;
    }
    _keys[command] = key;
    await _save();
    return true;
  }

  Future<void> reset() async {
    _keys.clear();
    await _save();
  }

  Future<void> _save() async {
    try {
      saveFailed =
          store != null &&
          !await store!.setString(
            'desktop.readerShortcuts',
            jsonEncode({
              for (final e in _keys.entries) e.key.name: e.value.toJson(),
            }),
          );
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }
}

bool readerIsEditingText() {
  final context = FocusManager.instance.primaryFocus?.context;
  final widget = context?.widget;
  final editable = widget is EditableText
      ? widget
      : context?.findAncestorWidgetOfExactType<EditableText>();
  return editable != null && !editable.readOnly;
}

/// Reuses the toolbar callbacks so keyboard and mouse perform the same action.
class DesktopActionsScope extends InheritedWidget {
  const DesktopActionsScope({
    super.key,
    required this.actions,
    required super.child,
  });
  final Map<String, VoidCallback?> actions;
  static Map<String, VoidCallback?>? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<DesktopActionsScope>()
      ?.actions;
  @override
  bool updateShouldNotify(DesktopActionsScope oldWidget) =>
      oldWidget.actions != actions;
}
