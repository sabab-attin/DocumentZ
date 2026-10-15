import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

class PdfThumbnail extends StatefulWidget {
  const PdfThumbnail({super.key, required this.page, this.renderWidth = 160});
  final PdfPage page;
  final double renderWidth;
  @override
  State<PdfThumbnail> createState() => _PdfThumbnailState();
}

class _PdfThumbnailState extends State<PdfThumbnail> {
  ui.Image? picture;
  late final Future<void> loading = _load();
  Future<void> _load() async {
    final raster = await widget.page.render(
      fullWidth: widget.renderWidth,
      fullHeight: widget.renderWidth * widget.page.height / widget.page.width,
    );
    if (raster == null) return;
    try {
      final image = await raster.createImage();
      if (!mounted) {
        image.dispose();
        return;
      }
      picture = image;
    } finally {
      raster.dispose();
    }
  }

  @override
  void dispose() {
    picture?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
    future: loading,
    builder: (context, snapshot) =>
        snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                picture == null)
        ? const Icon(Icons.broken_image_outlined)
        : picture == null
        ? const Center(child: CircularProgressIndicator())
        : RawImage(image: picture, fit: BoxFit.contain),
  );
}

// Keep pages at least 250 logical pixels wide when space allows.
int pdfPreviewColumns(double width) =>
    (width / 250).floor().clamp(1, 6).toInt();

Future<void> showPdfPagePreview(BuildContext context, PdfPage page) async {
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: Text('Page ${page.pageNumber}')),
        body: SafeArea(
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: Center(
              child: AspectRatio(
                aspectRatio: page.width / page.height,
                child: PdfThumbnail(page: page, renderWidth: 1600),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class PdfSearchHit {
  const PdfSearchHit(this.page, this.start, this.end, this.snippet);
  final int page, start, end;
  final String snippet;
}

class PdfTextIndex {
  final Map<int, Future<String>> _pages = {};
  Future<String> pageText(PdfPage page) => _pages.putIfAbsent(
    page.pageNumber,
    () async => (await page.loadText())?.fullText ?? '',
  );
  Stream<PdfSearchHit> search(
    List<PdfPage> pages,
    String query,
    bool Function() canceled,
  ) async* {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return;
    for (final page in pages) {
      if (canceled()) return;
      final text = await pageText(page);
      for (final match in RegExp(
        RegExp.escape(query.trim()),
        caseSensitive: false,
      ).allMatches(text)) {
        if (canceled()) return;
        final offset = match.start, end = match.end;
        yield PdfSearchHit(
          page.pageNumber,
          offset,
          end,
          text
              .substring(
                (offset - 40).clamp(0, text.length),
                (end + 80).clamp(0, text.length),
              )
              .replaceAll(RegExp(r'\s+'), ' '),
        );
      }
    }
  }
}

class PdfFindSession {
  const PdfFindSession(this.query, this.hits, this.active);
  final String query;
  final List<PdfSearchHit> hits;
  final int active;
  PdfFindSession withIndex(int index) => PdfFindSession(query, hits, index);
}

class PdfNavigationScreen extends StatefulWidget {
  const PdfNavigationScreen({
    super.key,
    required this.controller,
    required this.index,
    this.initialFind,
  });
  final PdfViewerController controller;
  final PdfTextIndex index;
  final PdfFindSession? initialFind;
  @override
  State<PdfNavigationScreen> createState() => _PdfNavigationScreenState();
}

class _PdfNavigationScreenState extends State<PdfNavigationScreen> {
  final input = TextEditingController();
  late final outline = widget.controller.document.loadOutline();
  final hits = <PdfSearchHit>[];
  @override
  void initState() {
    super.initState();
    final initial = widget.initialFind;
    if (initial != null) {
      input.text = initial.query;
      hits.addAll(initial.hits);
    }
  }

  Timer? debounce;
  int generation = 0;
  bool searching = false;
  String? error;
  @override
  void dispose() {
    generation++;
    debounce?.cancel();
    input.dispose();
    super.dispose();
  }

  Future<void> search(String value) async {
    final token = ++generation;
    setState(() {
      hits.clear();
      error = null;
      searching = value.trim().isNotEmpty;
    });
    try {
      if (!widget.controller.textSelectionDelegate.isCopyAllowed) {
        setState(() => error = 'This PDF restricts text extraction.');
        return;
      }
      await for (final hit in widget.index.search(
        widget.controller.pages,
        value,
        () => !mounted || token != generation,
      )) {
        if (!mounted || token != generation) return;
        setState(() => hits.add(hit));
      }
    } catch (_) {
      if (mounted && token == generation) {
        setState(() => error = 'Could not search this document.');
      }
    } finally {
      if (mounted && token == generation) setState(() => searching = false);
    }
  }

  void go(int page) {
    Navigator.pop(context);
    widget.controller.goToPage(pageNumber: page);
  }

  Widget node(PdfOutlineNode item) => item.children.isEmpty
      ? ListTile(
          title: Text(item.title),
          onTap: item.dest == null ? null : () => go(item.dest!.pageNumber),
        )
      : ExpansionTile(
          title: Text(item.title),
          children: [
            if (item.dest != null)
              ListTile(
                title: const Text('Go to section'),
                onTap: () => go(item.dest!.pageNumber),
              ),
            for (final child in item.children) node(child),
          ],
        );
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Navigate'),
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Search'),
            Tab(text: 'Contents'),
            Tab(text: 'Pages'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: input,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Find in document',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    generation++;
                    setState(() {
                      hits.clear();
                      searching = value.trim().isNotEmpty;
                    });
                    debounce?.cancel();
                    debounce = Timer(
                      const Duration(milliseconds: 250),
                      () => search(value),
                    );
                  },
                  onSubmitted: (value) {
                    debounce?.cancel();
                    search(value);
                  },
                ),
              ),
              if (searching) const LinearProgressIndicator(),
              if (input.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${hits.length} matches${searching ? ' · searching…' : ''}',
                  ),
                ),
              if (error != null) Text(error!),
              Expanded(
                child: hits.isEmpty
                    ? Center(
                        child: Text(
                          searching
                              ? 'Searching…'
                              : input.text.isEmpty
                              ? 'Enter a keyword'
                              : 'No matches',
                        ),
                      )
                    : ListView.builder(
                        itemCount: hits.length,
                        itemBuilder: (context, i) => ListTile(
                          title: Text('Page ${hits[i].page}'),
                          subtitle: Text(hits[i].snippet),
                          onTap: searching
                              ? null
                              : () => Navigator.pop(
                                  context,
                                  PdfFindSession(
                                    input.text.trim(),
                                    List.unmodifiable(hits),
                                    i,
                                  ),
                                ),
                        ),
                      ),
              ),
            ],
          ),
          FutureBuilder<List<PdfOutlineNode>>(
            future: outline,
            builder: (context, snapshot) => snapshot.hasError
                ? const Center(child: Text('Could not load contents.'))
                : !snapshot.hasData
                ? const Center(child: CircularProgressIndicator())
                : snapshot.data!.isEmpty
                ? const Center(child: Text('This PDF has no outline.'))
                : ListView(children: snapshot.data!.map(node).toList()),
          ),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: pdfPreviewColumns(constraints.maxWidth),
                childAspectRatio: .65,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: widget.controller.pageCount,
              itemBuilder: (context, i) => InkWell(
                onTap: () => go(i + 1),
                child: Column(
                  children: [
                    Expanded(
                      child: PdfThumbnail(
                        page: widget.controller.pages[i],
                        renderWidth: 700,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text('Page ${i + 1}'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
