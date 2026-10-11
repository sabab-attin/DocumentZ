import 'package:flutter/material.dart';
import '../core/preferences.dart';

class TextAlignmentMenu extends StatelessWidget {
  const TextAlignmentMenu({super.key, required this.preferences});
  final ReaderPreferences preferences;
  @override
  Widget build(BuildContext context) => PopupMenuButton<ReadingAlignment>(
    tooltip: 'Text alignment', initialValue: preferences.alignment,
    onSelected: preferences.setAlignment,
    icon: Icon(switch (preferences.alignment) {
      ReadingAlignment.left => Icons.format_align_left,
      ReadingAlignment.right => Icons.format_align_right,
      ReadingAlignment.center => Icons.format_align_center,
      ReadingAlignment.justify => Icons.format_align_justify,
    }),
    itemBuilder: (_) => ReadingAlignment.values.map((value) => CheckedPopupMenuItem(
      value: value, checked: preferences.alignment == value, child: Text(value.label))).toList(),
  );
}
