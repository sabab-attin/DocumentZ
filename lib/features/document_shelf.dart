import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../domain/book.dart';
import 'document_cover.dart';
import 'document_tile.dart';
import 'shelf_preferences.dart';

DocumentTileLayout shelfTileLayout(
  double width,
  TextScaler scaler,
  ShelfView view,
) {
  final available = (width - 32).clamp(0.0, double.infinity);
  final columns = switch (view) {
    ShelfView.extraLarge => (available / 340).floor().clamp(1, 3),
    ShelfView.large => (available / 260).floor().clamp(1, 4),
    ShelfView.small => ((available + 16) / 168).floor().clamp(1, 6),
    _ => null,
  };
  return DocumentTileLayout(
    width,
    scaler,
    preferredColumns: columns,
    minimumCover: view == ShelfView.small ? 72 : 150,
    maximumCover: view == ShelfView.small
        ? 96
        : view == ShelfView.extraLarge
        ? 420
        : 300,
  );
}

class DocumentShelfSliver<T> extends StatelessWidget {
  const DocumentShelfSliver({
    super.key,
    required this.items,
    required this.preferences,
    required this.width,
    required this.typeOf,
    required this.tileBuilder,
    required this.rowBuilder,
    this.selectionEnabled = false,
  });
  final List<T> items;
  final ShelfPreferences preferences;
  final double width;
  final bool selectionEnabled;
  final String Function(T) typeOf;
  final Widget Function(T, DocumentTileLayout) tileBuilder;
  final Widget Function(T) rowBuilder;
  @override
  Widget build(BuildContext context) {
    final layout = shelfTileLayout(
      width,
      MediaQuery.textScalerOf(context),
      preferences.view,
    );
    Widget section(List<T> entries) {
      final body = preferences.view.grid
          ? SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.columns,
                mainAxisExtent: layout.extent,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => tileBuilder(entries[index], layout),
                childCount: entries.length,
              ),
            )
          : SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: rowBuilder(entries[index]),
                ),
                childCount: entries.length,
              ),
            );
      if (preferences.view != ShelfView.details ||
          width - 56 < 650 ||
          MediaQuery.textScalerOf(context).scale(14) > 21) {
        return body;
      }
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: DefaultTextStyle(
                style: Theme.of(context).textTheme.labelSmall!,
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text('Name')),
                    const SizedBox(width: 12),
                    const SizedBox(width: 52, child: Text('Type')),
                    const SizedBox(width: 80, child: Text('Size')),
                    const SizedBox(width: 100, child: Text('Modified')),
                    const SizedBox(width: 105, child: Text('Progress')),
                    SizedBox(width: selectionEnabled ? 96 : 48),
                  ],
                ),
              ),
            ),
          ),
          body,
        ],
      );
    }

    if (!preferences.groupByType) return section(items);
    final groups = <String, List<T>>{};
    for (final item in items) {
      groups.putIfAbsent(typeOf(item), () => []).add(item);
    }
    return SliverMainAxisGroup(
      slivers: [
        for (final group in groups.entries) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '${group.key.toUpperCase()} · ${group.value.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),
          section(group.value),
        ],
      ],
    );
  }
}

String shelfFileSize(int? bytes) {
  if (bytes == null) return '—';
  if (bytes < 1000) return '$bytes B';
  if (bytes < 1000000) return '${(bytes / 1000).toStringAsFixed(1)} KB';
  return '${(bytes / 1000000).toStringAsFixed(1)} MB';
}

String shelfDate(BuildContext context, int? milliseconds) =>
    milliseconds == null || milliseconds <= 0
    ? '—'
    : MaterialLocalizations.of(context)
          .formatShortDate(DateTime.fromMillisecondsSinceEpoch(milliseconds));

class ShelfDocumentRow extends StatelessWidget {
  const ShelfDocumentRow({
    super.key,
    required this.title,
    required this.format,
    required this.view,
    required this.progress,
    required this.onOpen,
    this.onOptions,
    this.onSelected,
    this.selectable = false,
    this.selected = false,
    this.cover,
    this.size,
    this.modified,
    this.folder,
  });
  final String title;
  final BookFormat format;
  final ShelfView view;
  final double progress;
  final VoidCallback? onOpen, onOptions;
  final ValueChanged<bool>? onSelected;
  final bool selectable, selected;
  final Future<Uint8List?>? cover;
  final int? size, modified;
  final String? folder;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final name = Text(
      title,
      maxLines: view == ShelfView.list ? 1 : 2,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleSmall,
    );
    Widget actions() => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selectable)
          SizedBox(
            width: 48,
            child: Checkbox(
              value: selected,
              semanticLabel: 'Select $title',
              onChanged: onSelected == null
                  ? null
                  : (value) => onSelected!(value ?? false),
            ),
          ),
        if (onOptions != null)
          IconButton(
            tooltip: 'Document options',
            icon: const Icon(Icons.more_vert),
            onPressed: onOptions,
          ),
      ],
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: selected ? scheme.secondaryContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: .4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        onLongPress: onOptions,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (view == ShelfView.details &&
                  constraints.maxWidth >= 650 &&
                  MediaQuery.textScalerOf(context).scale(14) <= 21) {
                return Row(
                  children: [
                    Expanded(flex: 3, child: name),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 52,
                      child: Text(format.name.toUpperCase(), style: textStyle),
                    ),
                    SizedBox(
                      width: 80,
                      child: Text(shelfFileSize(size), style: textStyle),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text(
                        shelfDate(context, modified),
                        style: textStyle,
                      ),
                    ),
                    SizedBox(
                      width: 105,
                      child: Text('Progress $percent%', style: textStyle),
                    ),
                    actions(),
                  ],
                );
              }
              final preview =
                  view == ShelfView.tiles || view == ShelfView.content;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview && cover != null)
                    RepaintBoundary(
                      child: DocumentCover(
                        format: format,
                        cover: cover!,
                        width: view == ShelfView.content ? 84 : 60,
                        height: view == ShelfView.content ? 112 : 80,
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Icon(
                        format == BookFormat.pdf
                            ? Icons.picture_as_pdf_outlined
                            : Icons.description_outlined,
                        size: 28,
                        color: scheme.primary,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            Text(format.name.toUpperCase(), style: textStyle),
                            Text('Progress $percent%', style: textStyle),
                            if (view != ShelfView.list && size != null)
                              Text(shelfFileSize(size), style: textStyle),
                            if ((view == ShelfView.details ||
                                    view == ShelfView.content) &&
                                modified != null)
                              Text(
                                'Modified ${shelfDate(context, modified)}',
                                style: textStyle,
                              ),
                          ],
                        ),
                        if (view == ShelfView.content && folder != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            folder!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (constraints.maxWidth < 360 && selectable)
                    Column(
                      children: [
                        SizedBox(
                          width: 48,
                          child: Checkbox(
                            value: selected,
                            semanticLabel: 'Select $title',
                            onChanged: onSelected == null
                                ? null
                                : (value) => onSelected!(value ?? false),
                          ),
                        ),
                        if (onOptions != null)
                          IconButton(
                            tooltip: 'Document options',
                            icon: const Icon(Icons.more_vert),
                            onPressed: onOptions,
                          ),
                      ],
                    )
                  else
                    actions(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
