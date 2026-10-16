import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_navigation.dart';

/// Return zero-based page indices. Page numbers shown to readers are one-based.
class PdfPagePicker extends StatefulWidget {
  const PdfPagePicker({
    super.key,
    required this.bytes,
    required this.title,
    this.multiple = false,
    this.confirmLabel,
    this.documentLoader,
    this.initialSelection = const [],
  });
  final Uint8List bytes;
  final String title;
  final bool multiple;
  final String? confirmLabel;
  final Future<PdfDocument> Function()? documentLoader;
  final List<int> initialSelection;
  @override
  State<PdfPagePicker> createState() => _PdfPagePickerState();
}

class _PdfPagePickerState extends State<PdfPagePicker> {
  PdfDocument? document;
  String? error;
  final number = TextEditingController(text: '1');
  final preview = PageController();
  final chosen = <int>{};
  int current = 0;
  bool grid = true;
  @override
  void initState() {
    super.initState();
    chosen.addAll(widget.initialSelection);
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
      setState(() => document = result);
    } catch (_) {
      if (mounted) setState(() => error = 'Could not preview this PDF.');
    }
  }

  @override
  void dispose() {
    number.dispose();
    preview.dispose();
    document?.dispose();
    super.dispose();
  }

  void show(int index) {
    setState(() {
      current = index;
      number.text = '${index + 1}';
      grid = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && preview.hasClients) preview.jumpToPage(index);
    });
  }

  void jump(String text) {
    final page = int.tryParse(text);
    final count = document!.pages.length;
    if (page == null || page < 1 || page > count) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Choose a page from 1 to $count.')),
      );
      number.text = '${current + 1}';
      return;
    }
    FocusScope.of(context).unfocus();
    show(page - 1);
  }

  void toggle(int index) => setState(() {
    if (!chosen.add(index)) chosen.remove(index);
  });
  @override
  Widget build(BuildContext context) {
    final pages = document?.pages;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (pages != null)
            IconButton(
              tooltip: grid ? 'Large preview' : 'All pages',
              icon: Icon(grid ? Icons.zoom_in : Icons.grid_view),
              onPressed: () {
                if (grid) {
                  show(current);
                } else {
                  setState(() => grid = true);
                }
              },
            ),
        ],
      ),
      body: error != null
          ? Center(child: Text(error!))
          : pages == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('Page '),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: number,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onSubmitted: jump,
                        ),
                      ),
                      Text(' / ${pages.length}'),
                      IconButton(
                        tooltip: 'Jump to page',
                        onPressed: () => jump(number.text),
                        icon: const Icon(Icons.arrow_forward),
                      ),
                    ],
                  ),
                ),
                if (widget.multiple)
                  Row(
                    children: [
                      Checkbox(
                        value: chosen.length == pages.length,
                        onChanged: (all) => setState(() {
                          chosen.clear();
                          if (all == true) {
                            chosen.addAll(
                              List.generate(pages.length, (i) => i),
                            );
                          }
                        }),
                      ),
                      const Text('All pages'),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text('${chosen.length} selected'),
                      ),
                    ],
                  ),
                Expanded(
                  child: grid
                      ? LayoutBuilder(
                          builder: (context, constraints) => GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: pdfPreviewColumns(
                                    constraints.maxWidth,
                                  ),
                                  childAspectRatio: .65,
                                  mainAxisSpacing: 12,
                                  crossAxisSpacing: 12,
                                ),
                            itemCount: pages.length,
                            itemBuilder: (context, i) => Card.outlined(
                              child: InkWell(
                                onTap: () => show(i),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: PdfThumbnail(
                                          key: ValueKey(i),
                                          page: pages[i],
                                          renderWidth: 700,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        if (widget.multiple)
                                          Checkbox(
                                            value: chosen.contains(i),
                                            onChanged: (_) => toggle(i),
                                          ),
                                        Text('Page ${i + 1}'),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : PageView.builder(
                          controller: preview,
                          itemCount: pages.length,
                          onPageChanged: (i) => setState(() {
                            current = i;
                            number.text = '${i + 1}';
                          }),
                          itemBuilder: (context, i) => Padding(
                            padding: const EdgeInsets.all(16),
                            child: InteractiveViewer(
                              minScale: 1,
                              maxScale: 5,
                              child: SizedBox.expand(
                                child: PdfThumbnail(
                                  key: ValueKey('preview:$i'),
                                  page: pages[i],
                                  renderWidth: 1600,
                                ),
                              ),
                            ),
                          ),
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      children: [
                        if (!grid && widget.multiple)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Checkbox(
                                value: chosen.contains(current),
                                onChanged: (_) => toggle(current),
                              ),
                              const Text('Select this page'),
                            ],
                          ),
                        FilledButton(
                          onPressed: widget.multiple && chosen.isEmpty
                              ? null
                              : () {
                                  final result = widget.multiple
                                      ? (chosen.toList()..sort())
                                      : [current];
                                  Navigator.pop(context, result);
                                },
                          child: Text(
                            widget.multiple
                                ? widget.confirmLabel == null
                                      ? 'Use selected pages'
                                      : '${widget.confirmLabel} ${chosen.length} pages'
                                : 'Use page ${current + 1}',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
