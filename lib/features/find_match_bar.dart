import 'package:flutter/material.dart';

import 'selection_panel.dart';

class FindMatchBar extends StatelessWidget {
  const FindMatchBar({
    super.key,
    required this.current,
    required this.count,
    required this.query,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });
  final int current, count;
  final String query;
  final VoidCallback onPrevious, onNext, onClose;
  @override
  Widget build(BuildContext context) => Material(
    color: readerPanelColor,
    elevation: 8,
    borderRadius: BorderRadius.circular(24),
    child: Row(
      children: [
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            query,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: readerPanelInk),
          ),
        ),
        Text(
          '${current + 1} / $count',
          style: const TextStyle(color: readerPanelInk),
        ),
        IconButton(
          tooltip: 'Previous match',
          color: readerPanelInk,
          onPressed: current > 0 ? onPrevious : null,
          icon: const Icon(Icons.keyboard_arrow_up),
        ),
        IconButton(
          tooltip: 'Next match',
          color: readerPanelInk,
          onPressed: current + 1 < count ? onNext : null,
          icon: const Icon(Icons.keyboard_arrow_down),
        ),
        IconButton(
          tooltip: 'Close find',
          color: readerPanelInk,
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );
}
