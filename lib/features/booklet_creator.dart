import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import '../data/document_sharing.dart';
import '../data/pdf_booklet.dart';
import '../domain/services.dart';

class BookletCreator extends StatefulWidget {
  const BookletCreator({
    super.key,
    required this.bytes,
    required this.title,
    required this.repository,
    required this.onSaved,
    this.previewBuilder,
  });
  final Uint8List bytes;
  final String title;
  final ImportableLibrary repository;
  final VoidCallback onSaved;
  final Widget Function(Uint8List bytes)? previewBuilder;
  @override
  State<BookletCreator> createState() => _BookletCreatorState();
}

class _BookletCreatorState extends State<BookletCreator> {
  int perBooklet = 0;
  int selected = 0;
  int side = 0;
  int generation = 0;
  int count = 0;
  List<BookletSignature> plan = [];
  Uint8List? preview;
  String? error;
  bool rendering = true;
  bool exporting = false;
  bool saving = false;
  bool savedToLibrary = false;
  String status = '';
  BookletExport? result;
  @override
  void initState() {
    super.initState();
    try {
      count = PdfBooklet.pageCount(widget.bytes);
      plan = planBooklets(count, perBooklet);
      _preview();
    } catch (_) {
      rendering = false;
      error = 'Could not open this PDF for booklet creation.';
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> _preview() async {
    final ticket = ++generation;
    setState(() {
      rendering = true;
      error = null;
      preview = null;
    });
    try {
      // Yield before starting so controls and progress paint immediately.
      await Future<void>.delayed(Duration.zero);
      if (!mounted || ticket != generation) return;
      final data = await PdfBooklet.preview(widget.bytes, plan[selected], side);
      if (mounted && ticket == generation) {
        setState(() {
          preview = data;
          rendering = false;
        });
      }
    } catch (_) {
      if (mounted && ticket == generation) {
        setState(() {
          rendering = false;
          error = 'Could not render this sheet. Try again or choose another booklet.';
        });
      }
    }
  }

  void _size(int value) {
    setState(() {
      perBooklet = value;
      plan = planBooklets(count, value);
      selected = 0;
      side = 0;
      result = null;
      savedToLibrary = false;
    });
    _preview();
  }

  Widget _printingTip(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(
        Icons.lightbulb_outline,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Text(
          'Printing tip: Choose both sides · Flip on the short edge.\nActual size · One PDF page per sheet side.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ],
  );

  String _page(int? index) => index == null ? 'Blank' : 'Page ${index + 1}';
  String _sideLabel(int index) =>
      'Sheet ${index ~/ 2 + 1} · ${index.isEven ? 'Front' : 'Back'}';

  Future<void> _sourcePage(int index) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Source · Page ${index + 1}')),
          body: PdfViewer.data(
            widget.bytes,
            sourceName: 'booklet-source-${widget.title}',
            initialPageNumber: index + 1,
          ),
        ),
      ),
    );
  }

  Future<void> _create() async {
    if (exporting || saving) return;
    setState(() {
      exporting = true;
      status = 'Creating booklets…';
    });
    try {
      final output =
          result ??
          await PdfBooklet.export(
            widget.bytes,
            widget.title,
            perBooklet,
            onProgress: (done, total) {
              if (mounted) {
                setState(() => status = 'Creating booklet $done / $total');
              }
            },
          );
      if (!mounted) return;
      setState(() {
        result = output;
        exporting = false;
        status = '';
      });
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Booklet ready',
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(output.name),
                  Text(
                    output.isZip
                        ? 'ZIP · Separate booklets'
                        : 'PDF · Ready to print',
                  ),
                  const SizedBox(height: 12),
                  ListTile(
                    leading: const Icon(Icons.save_alt),
                    title: const Text('Save file'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _saveFile(output);
                    },
                  ),
                  if (!output.isZip)
                    ListTile(
                      leading: const Icon(Icons.library_add_outlined),
                      title: Text(
                        savedToLibrary ? 'Saved to library' : 'Save to library',
                      ),
                      onTap: savedToLibrary
                          ? null
                          : () {
                              Navigator.pop(sheet);
                              _saveLibrary(output);
                            },
                    ),
                  ListTile(
                    leading: const Icon(Icons.share_outlined),
                    title: const Text('Share'),
                    onTap: () {
                      Navigator.pop(sheet);
                      _share(output);
                    },
                  ),
                  if (!output.isZip)
                    ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: const Text('Print'),
                      onTap: () {
                        Navigator.pop(sheet);
                        _print(output);
                      },
                    ),
                  const SizedBox(height: 8),
                  _printingTip(sheet),
                ],
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      _message('Could not create the booklet. Your original PDF is unchanged.');
    } finally {
      if (mounted) {
        setState(() {
          exporting = false;
          status = '';
        });
      }
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _saveFile(BookletExport output) async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final path = await FilePicker.saveFile(
        fileName: output.name,
        bytes: output.bytes,
        mimeType: output.isZip ? 'application/zip' : 'application/pdf',
        dialogTitle: 'Save booklet',
      );
      if (path != null) _message('Booklet saved.');
    } catch (_) {
      _message('Could not save the booklet. You can try sharing it instead.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _saveLibrary(BookletExport output) async {
    if (saving || savedToLibrary) return;
    setState(() => saving = true);
    try {
      await widget.repository.importDocument(
        output.name,
        Stream.value(output.bytes),
      );
      widget.onSaved();
      if (mounted) setState(() => savedToLibrary = true);
      _message('Booklet saved to library.');
    } catch (_) {
      _message('Could not save to the library. Try again.');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _share(BookletExport output) async {
    try {
      await shareBytes(context, output.bytes, output.name);
    } catch (_) {
      _message('Could not share the booklet. Try saving the file.');
    }
  }

  Future<void> _print(BookletExport output) async {
    try {
      await Printing.layoutPdf(
        name: output.name,
        onLayout: (_) async => output.bytes,
      );
    } catch (_) {
      _message('Could not open printing. Save the PDF and print it later.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final blocked = exporting || saving;
    final signature = plan.isEmpty ? null : plan[selected];
    final sides = signature?.sides ?? [];
    final current = sides.isEmpty ? null : sides[side];
    return PopScope<void>(
      canPop: !blocked,
      child: Scaffold(
        appBar: AppBar(title: const Text('Create booklet')),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, bounds) => Column(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: bounds.maxHeight * .38,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _printingTip(context),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            key: ValueKey('size-$perBooklet'),
                            initialValue: perBooklet,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Pages per booklet',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: [
                              for (final size in [0, 4, 8, 12, 16, 20, 24])
                                DropdownMenuItem(
                                  value: size,
                                  child: Text(
                                    size == 0
                                        ? 'All pages in one booklet'
                                        : '$size pages',
                                  ),
                                ),
                            ],
                            onChanged: blocked || count == 0
                                ? null
                                : (value) {
                                    if (value != null) _size(value);
                                  },
                          ),
                          const SizedBox(height: 8),
                          if (signature != null) ...[
                            Text(
                              '$count source pages · ${plan.length} booklet${plan.length == 1 ? '' : 's'} · '
                              '${plan.fold<int>(0, (sum, item) => sum + item.sheetCount)} sheets',
                            ),
                            const SizedBox(height: 8),
                            DropdownButtonFormField<int>(
                              key: ValueKey('signature-$perBooklet-$selected'),
                              initialValue: selected,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Preview booklet',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: [
                                for (var i = 0; i < plan.length; i++)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      'Booklet ${i + 1} · Pages ${plan[i].start + 1}–${plan[i].end}',
                                    ),
                                  ),
                              ],
                              onChanged: blocked
                                  ? null
                                  : (value) {
                                      if (value == null) return;
                                      setState(() {
                                        selected = value;
                                        side = 0;
                                      });
                                      _preview();
                                    },
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${signature.sheetCount} sheets · ${signature.blankCount} blank pages added',
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Creates a print copy. Reader notes and drawings are not included.',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (current != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Previous sheet side',
                          onPressed: blocked || side == 0
                              ? null
                              : () {
                                  setState(() => side--);
                                  _preview();
                                },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            value: side,
                            isExpanded: true,
                            items: [
                              for (var i = 0; i < sides.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(_sideLabel(i)),
                                ),
                            ],
                            onChanged: blocked
                                ? null
                                : (value) {
                                    if (value == null) return;
                                    setState(() => side = value);
                                    _preview();
                                  },
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next sheet side',
                          onPressed: blocked || side == sides.length - 1
                              ? null
                              : () {
                                  setState(() => side++);
                                  _preview();
                                },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: rendering
                          ? const Center(child: CircularProgressIndicator())
                          : error != null
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Text(
                                      error!,
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                  if (plan.isNotEmpty)
                                    TextButton(
                                      onPressed: _preview,
                                      child: const Text('Retry preview'),
                                    ),
                                ],
                              ),
                            )
                          : preview == null
                          ? const SizedBox.shrink()
                          : widget.previewBuilder?.call(preview!) ??
                                PdfViewer.data(
                                  preview!,
                                  key: ValueKey(generation),
                                  sourceName: 'booklet-preview-$generation',
                                ),
                    ),
                  ),
                ),
                if (current != null)
                  Wrap(
                    spacing: 16,
                    children: [
                      TextButton(
                        onPressed: blocked || current.left == null
                            ? null
                            : () => _sourcePage(current.left!),
                        child: Text('Left: ${_page(current.left)}'),
                      ),
                      TextButton(
                        onPressed: blocked || current.right == null
                            ? null
                            : () => _sourcePage(current.right!),
                        child: Text('Right: ${_page(current.right)}'),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    children: [
                      if (blocked) ...[
                        const LinearProgressIndicator(),
                        Text(status.isEmpty ? 'Saving…' : status),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('create-booklet'),
                          onPressed:
                              blocked ||
                                  rendering ||
                                  preview == null ||
                                  error != null
                              ? null
                              : _create,
                          icon: const Icon(Icons.menu_book_outlined),
                          label: Text(
                            result == null
                                ? 'Create booklet${plan.length > 1 ? 's' : ''}'
                                : 'Save or share booklet',
                          ),
                        ),
                      ),
                    ],
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
