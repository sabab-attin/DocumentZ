import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/reader_shortcuts.dart';

class KeyboardShortcutsSettings extends StatelessWidget {
  const KeyboardShortcutsSettings({super.key, required this.shortcuts});
  final ReaderShortcuts shortcuts;
  Future<void> _change(BuildContext context, ReaderCommand command) async {
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => Focus(
          autofocus: true,
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent ||
                event.logicalKey == LogicalKeyboardKey.escape) {
              return KeyEventResult.ignored;
            }
            final keyboard = HardwareKeyboard.instance;
            final key = ReaderKey(
              event.logicalKey.keyId,
              control: keyboard.isControlPressed,
              alt: keyboard.isAltPressed,
              shift: keyboard.isShiftPressed,
            );
            if (!key.allowed) return KeyEventResult.handled;
            shortcuts.setBinding(command, key).then((saved) {
              if (!dialog.mounted) return;
              if (saved) {
                Navigator.pop(dialog);
              } else {
                update(
                  () => error = 'That shortcut is already in use. Try another.',
                );
              }
            });
            return KeyEventResult.handled;
          },
          child: AlertDialog(
            title: Text(command.label),
            content: Text(
              error ?? 'Press Ctrl or Alt with a key, a function key, or Page Up / Page Down. Esc cancels.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: shortcuts,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          'Keyboard shortcuts',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Reader shortcuts. Text fields keep their standard editing keys.',
        ),
        for (final command in ReaderCommand.values)
          ListTile(
            title: Text(command.label),
            trailing: OutlinedButton(
              onPressed: () => _change(context, command),
              child: Text(shortcuts.binding(command).label),
            ),
          ),
        TextButton(
          onPressed: shortcuts.reset,
          child: const Text('Restore default shortcuts'),
        ),
        if (shortcuts.saveFailed)
          const Text(
            'Shortcuts could not be saved. Changes apply for this session.',
          ),
      ],
    ),
  );
}
