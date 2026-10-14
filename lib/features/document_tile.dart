import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/book.dart';
import 'document_cover.dart';

/// Both document shelves use one geometry, including reserved title and progress space.
class DocumentTileLayout {
  DocumentTileLayout(
    double availableWidth,
    TextScaler scaler, {
    int? preferredColumns,
    double minimumCover = 150,
    double maximumCover = 300,
  }) {
    final available = (availableWidth - 32).clamp(0.0, double.infinity);
    columns = scaler.scale(14) > 21 || available < 300
        ? 1
        : available >= 760
        ? 4
        : available >= 540
        ? 3
        : 2;
    if (preferredColumns != null && scaler.scale(14) <= 21) {
      columns = preferredColumns.clamp(
        1,
        ((available + 16) / 168).floor().clamp(1, 6),
      );
    }
    final width = (available - (columns - 1) * 16) / columns;
    coverHeight = ((width - 24) * 1.28).clamp(minimumCover, maximumCover);
    titleHeight = (scaler.scale(14) * 1.35 * 2).ceilToDouble() + 2;
    progressHeight = (scaler.scale(11) * 1.4).ceilToDouble() + 2;
    extent = (coverHeight + titleHeight + progressHeight + 96).ceilToDouble();
  }
  late int columns;
  late final double coverHeight, titleHeight, progressHeight, extent;
}

class DocumentTile extends StatefulWidget {
  const DocumentTile({
    super.key,
    required this.title,
    required this.format,
    required this.cover,
    required this.layout,
    required this.onOpen,
    this.onOptions,
    this.onSelected,
    this.selectable = false,
    this.selected = false,
    this.progress = 0,
  });
  final String title;
  final BookFormat format;
  final Future<Uint8List?> cover;
  final DocumentTileLayout layout;
  final VoidCallback? onOpen, onOptions;
  final ValueChanged<bool>? onSelected;
  final bool selected, selectable;
  final double progress;
  @override
  State<DocumentTile> createState() => _DocumentTileState();
}

class _DocumentTileState extends State<DocumentTile> {
  bool pressed = false;
  void _press(bool value) {
    if (pressed != value) setState(() => pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = widget.progress.clamp(0.0, 1.0);
    return AnimatedScale(
      scale: pressed ? .985 : 1,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 100),
      curve: Curves.easeOutCubic,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: widget.selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: widget.selected
                ? scheme.primary
                : scheme.outlineVariant.withValues(alpha: .55),
            width: widget.selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onOpen,
          onTapDown: widget.onOpen == null ? null : (_) => _press(true),
          onTapUp: (_) => _press(false),
          onTapCancel: () => _press(false),
          onLongPress: widget.onOptions == null
              ? null
              : () {
                  _press(false);
                  widget.onOptions!();
                },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                RepaintBoundary(
                  child: DocumentCover(
                    format: widget.format,
                    width: double.infinity,
                    height: widget.layout.coverHeight,
                    cover: widget.cover,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: widget.layout.titleHeight,
                  child: Text(
                    widget.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              widget.format.name.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(fontSize: 10, letterSpacing: .6),
                            ),
                          ),
                        ),
                      ),
                      if (widget.selectable)
                        SizedBox(
                          width: 48,
                          child: Checkbox(
                            value: widget.selected,
                            semanticLabel: 'Select ${widget.title}',
                            onChanged: widget.onSelected == null
                                ? null
                                : (value) => widget.onSelected!(value ?? false),
                          ),
                        ),
                      if (widget.onOptions != null)
                        IconButton(
                          tooltip: 'Document options',
                          icon: const Icon(Icons.more_vert, size: 20),
                          onPressed: widget.onOptions,
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: widget.layout.progressHeight,
                  child: Text(
                    'Progress ${(fraction * 100).round()}%',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 11,
                      height: 1.4,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fraction,
                    minHeight: 3,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
