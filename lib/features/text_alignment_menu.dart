import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../core/reader_shortcuts.dart';
import 'reading_typography.dart';

class TextAlignmentMenu extends StatelessWidget {
  const TextAlignmentMenu({super.key, required this.preferences});
  final ReaderPreferences preferences;
  @override
  Widget build(BuildContext context) => PopupMenuButton<ReadingAlignment>(
    tooltip: 'Text alignment',
    initialValue: preferences.alignment,
    onSelected: preferences.setAlignment,
    child: DesktopActionsScope.of(context) != null
        ? Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(alignmentIcon(preferences.alignment), size: 22),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(alignmentIcon(preferences.alignment)),
                const SizedBox(height: 8),
                Text(preferences.alignment.label),
              ],
            ),
          ),
    itemBuilder: (_) => ReadingAlignment.values
        .map(
          (value) => CheckedPopupMenuItem(
            value: value,
            checked: preferences.alignment == value,
            child: Row(
              children: [
                Icon(alignmentIcon(value)),
                const SizedBox(width: 12),
                Text(value.label),
              ],
            ),
          ),
        )
        .toList(),
  );
}
