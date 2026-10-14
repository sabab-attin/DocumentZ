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
  });
  final Uint8List bytes;
  final String title;
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
      await pdfrxFlutterInitialize();
      final result = await PdfDocument.openData(widget.bytes);
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
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${order.length} pages · Drag to reorder'),
                    ),
                    TextButton.icon(
                      onPressed: choosePages,
                      icon: const Icon(Icons.grid_view),
                      label: const Text('Choose pages'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: order.length,
                  onReorderItem: (from, to) =>
                      setState(() => order.insert(to, order.removeAt(from))),
                  itemBuilder: (context, i) => Card(
                    key: ValueKey(order[i]),
                    child: ListTile(
                      leading: SizedBox(
                        width: 52,
                        height: 72,
                        child: PdfThumbnail(page: document!.pages[order[i]]),
                      ),
                      title: Text('Page ${order[i] + 1}'),
                      subtitle: Text('Position ${i + 1}'),
                      minVerticalPadding: 16,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Move up',
                            onPressed: i == 0
                                ? null
                                : () => setState(
                                    () =>
                                        order.insert(i - 1, order.removeAt(i)),
                                  ),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: 'Remove page',
                            onPressed: () => setState(() => order.removeAt(i)),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
  );
}
