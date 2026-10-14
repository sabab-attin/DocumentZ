import 'highlighter_icon.dart';

import 'package:flutter/material.dart';

import 'annotations.dart';
import 'selection_panel.dart';

class AnnotationToolbar extends StatelessWidget {
  const AnnotationToolbar({
    super.key,
    required this.tool,
    required this.onTool,
    required this.onText,
    required this.onImage,
    required this.onColor,
    required this.onUndo,
    required this.onExit,
  });
  final MarkTool tool;
  final ValueChanged<MarkTool> onTool;
  final VoidCallback onText, onImage, onColor, onExit;
  final VoidCallback? onUndo;
  @override
  Widget build(BuildContext context) => Material(
    color: readerPanelColor,
    elevation: 8,
    borderRadius: BorderRadius.circular(24),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (final entry in const {
            MarkTool.browse: (Icons.pan_tool_outlined, 'Move / select'),
            MarkTool.pen: (Icons.draw_outlined, 'Draw'),
            MarkTool.highlight: (Icons.border_color, 'Highlight'),
            MarkTool.underline: (Icons.format_underlined, 'Underline'),
            MarkTool.strikethrough: (Icons.strikethrough_s, 'Strikethrough'),
            MarkTool.note: (Icons.add_comment_outlined, 'Add note'),
            MarkTool.eraser: (Icons.auto_fix_normal, 'Eraser'),
            MarkTool.rectangle: (Icons.crop_square, 'Rectangle'),
            MarkTool.arrow: (Icons.north_east, 'Arrow'),
          }.entries)
            IconButton(
              tooltip: entry.value.$2,
              color: tool == entry.key
                  ? const Color(0xffffcc00)
                  : readerPanelInk,
              onPressed: () => onTool(entry.key),
              icon: ReaderToolIcon(entry.value.$1),
            ),
          IconButton(
            tooltip: 'Add text',
            color: tool == MarkTool.text
                ? const Color(0xffffcc00)
                : readerPanelInk,
            onPressed: onText,
            icon: const ReaderToolIcon(Icons.text_fields),
          ),
          IconButton(
            tooltip: 'Add image',
            color: tool == MarkTool.image
                ? const Color(0xffffcc00)
                : readerPanelInk,
            onPressed: onImage,
            icon: const ReaderToolIcon(Icons.add_photo_alternate_outlined),
          ),
          IconButton(
            tooltip: 'Color & size',
            color: readerPanelInk,
            onPressed: onColor,
            icon: const ReaderToolIcon(Icons.palette_outlined),
          ),
          IconButton(
            tooltip: 'Undo annotation',
            color: readerPanelInk,
            onPressed: onUndo,
            icon: const ReaderToolIcon(Icons.undo),
          ),
          IconButton(
            tooltip: 'Exit annotation mode',
            color: readerPanelInk,
            onPressed: onExit,
            icon: const ReaderToolIcon(Icons.close),
          ),
        ],
      ),
    ),
  );
}
