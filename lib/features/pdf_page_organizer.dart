import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_navigation.dart';
import 'pdf_page_picker.dart';

class PdfPageOrganizer extends StatefulWidget {
  const PdfPageOrganizer({
    super.key,
    required this.bytes,
    this.title = 'Organize pages',
    this.documentLoader,
  });
  final Uint8List bytes;
  final String title;
  final Future<PdfDocument> Function()? documentLoader;
  @override
  State<PdfPageOrganizer> createState() => _PdfPageOrganizerState();
}

class _PdfPageOrganizerState extends State<PdfPageOrganizer> {
  PdfDocument? document;
  final order = <int>[];
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final PdfDocument result;
      if (widget.documentLoader != null) {
        result = await widget.documentLoader!();
      } else {
        await pdfrxFlutterInitialize();
        result = await PdfDocument.openData(widget.bytes);
      }
      if (!mounted) {
        await result.dispose();
        return;
      }
      setState(() {
        document = result;
        order.addAll(List.generate(result.pages.length, (i) => i));
      });
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load page previews.');
    }
  }

  @override
  void dispose() {
    document?.dispose();
    super.dispose();
  }

  Future<void> choosePages() async {
    final selected = await Navigator.push<List<int>>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfPagePicker(
          bytes: widget.bytes,
          title: 'Preview and select pages',
          multiple: true,
          initialSelection: List.of(order),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      // Retain the chosen ordering; append newly reselected pages at the end.
      final previous = List<int>.of(order);
      order.clear();
      order.addAll(previous.where(selected.contains));
      order.addAll(selected.where((i) => !previous.contains(i)));
    });
  }

  void move(int from, int to) {
    setState(() => order.insert(to, order.removeAt(from)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      actions: [
        IconButton(
          tooltip: 'Preview and select pages',
          onPressed: document == null ? null : choosePages,
          icon: const Icon(Icons.grid_view),
        ),
        TextButton(
          onPressed: order.isEmpty
              ? null
              : () => Navigator.pop(context, List<int>.of(order)),
          child: const Text('Continue'),
        ),
      ],
    ),
    body: error != null
        ? Center(child: Text(error!))
        : document == null
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 16,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${order.length} pages · Drag to reorder'),
                    TextButton.icon(
                      onPressed: choosePages,
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Choose pages'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      buildDefaultDragHandles: false,
                      itemCount: order.length,
                      onReorderItem: move,
                      itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                        key: ValueKey(order[i]),
                        index: i,
                        child: Card(
                          clipBehavior: Clip.antiAlias,
                          margin: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        'Page ${order[i] + 1} · Position ${i + 1}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium,
                                      ),
                                    ),
                                    Wrap(
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        ReorderableDragStartListener(
                                          index: i,
                                          child: Semantics(
                                            label:
                                                'Drag page ${order[i] + 1} to reorder',
                                            child: const Padding(
                                              padding: EdgeInsets.all(12),
                                              child: Icon(Icons.drag_handle),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Move up',
                                          onPressed: i == 0
                                              ? null
                                              : () => move(i, i - 1),
                                          icon: const Icon(Icons.arrow_upward),
                                        ),
                                        IconButton(
                                          tooltip: 'Move down',
                                          onPressed: i == order.length - 1
                                              ? null
                                              : () => move(i, i + 1),
                                          icon: const Icon(
                                            Icons.arrow_downward,
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          tooltip: 'Move page',
                                          onSelected: (value) => move(
                                            i,
                                            value == 'first'
                                                ? 0
                                                : order.length - 1,
                                          ),
                                          itemBuilder: (_) => const [
                                            PopupMenuItem(
                                              value: 'first',
                                              child: Text('Move to beginning'),
                                            ),
                                            PopupMenuItem(
                                              value: 'last',
                                              child: Text('Move to end'),
                                            ),
                                          ],
                                        ),
                                        IconButton(
                                          tooltip: 'Remove page',
                                          onPressed: () =>
                                              setState(() => order.removeAt(i)),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              InkWell(
                                onTap: () => showPdfPagePreview(
                                  context,
                                  document!.pages[order[i]],
                                ),
                                child: Semantics(
                                  label: 'Enlarge page ${order[i] + 1}',
                                  button: true,
                                  child: SizedBox(
                                    height:
                                        (MediaQuery.sizeOf(context).height * .5)
                                            .clamp(220.0, 480.0)
                                            .toDouble(),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: PdfThumbnail(
                                        key: ValueKey('page:${order[i]}'),
                                        page: document!.pages[order[i]],
                                        renderWidth: 800,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
