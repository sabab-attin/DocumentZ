import 'pdf_extraction_mode.dart';
import 'pdf_compression_screen.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:file_picker/file_picker.dart';
import 'package:archive/archive.dart';

import '../data/edit_output.dart';
import 'pdf_link_preview.dart';

import 'package:signature/signature.dart';

import 'edit_sources.dart';
import 'edit_fields_dialog.dart';
import '../data/pdf_security_worker.dart';
import 'annotation_workspace.dart';
import '../domain/services.dart';
import '../domain/book.dart';
import '../data/pdf_editing.dart';
import '../data/mobile_pdf.dart';
import 'pdf_region_picker.dart';
import 'pdf_page_organizer.dart';
import 'pdf_page_picker.dart';
import 'pdf_forms.dart';
import 'booklet_creator.dart';
import '../data/pdf_export.dart';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.repository,
    required this.onSaved,
    this.initialDocument,
    this.initialAction,
    this.initialDocuments = const [],
  });
  final LibraryRepository repository;
  final VoidCallback onSaved;
  final List<Book> initialDocuments;
  final Book? initialDocument;
  final String? initialAction;
  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  bool _initialConsumed = false;
  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) run(widget.initialAction!);
      });
    }
  }

  bool busy = false;
  String status = '';
  ImportableLibrary get library => widget.repository as ImportableLibrary;

  Future<Uint8List?> _readInput(EditInput input) async {
    final bytes = await input.read();
    try {
      if (await pdfPageCountInBackground(bytes) == 0) {
        throw const FormatException('This PDF has no pages.');
      }
      return bytes;
    } catch (error) {
      if (!RegExp(
        'password|encrypt|decrypt',
        caseSensitive: false,
      ).hasMatch(error.toString())) {
        rethrow;
      }
    }
    while (mounted) {
      final value = await fields(
        'Unlock ${input.title}',
        {'password': 'Password'},
        secret: {'password'},
      );
      if (value == null) return null;
      try {
        return await unlockPdfInBackground(bytes, value['password']!);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not unlock this PDF. Check the password.'),
            ),
          );
        }
      }
    }
    return null;
  }

  bool _running = false;
  bool _savedInRun = false;
  void _didSave() => _savedInRun = true;
  Future<void> run(String action) async {
    if (_running || busy) return;
    _running = true;
    _savedInRun = false;
    try {
      await _run(action);
    } finally {
      _running = false;
      if (_savedInRun && mounted) {
        widget.onSaved();
        editWorkflowCompleted.value++;
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  Future<void> _run(String action) async {
    if (busy) return;
    if (action == 'Annotate') {
      final opened = await openAnnotationWorkspace(
        context,
        widget.repository,
        book: widget.initialDocument,
        books: widget.initialDocuments,
      );
      if (opened) _didSave();
      return;
    }
    if (action == 'Create PDF' || action == 'Scan') {
      await _process(action, []);
      return;
    }
    try {
      final current = widget.initialDocument;
      final List<EditInput> inputs;
      if (widget.initialDocuments.isNotEmpty) {
        _initialConsumed = true;
        if (widget.initialDocuments.any(
          (book) => book.format != BookFormat.pdf,
        )) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Select only PDFs for PDF editing. Other formats can be annotated.',
                ),
              ),
            );
          }
          return;
        }
        inputs = widget.initialDocuments
            .map(
              (book) => EditInput(book.title, () => library.readDocument(book)),
            )
            .toList();
        if (action == 'Merge') {
          final order = await orderMergeInputs(context, inputs);
          if (order == null) return;
          inputs
            ..clear()
            ..addAll(order);
        }
      } else if (!_initialConsumed &&
          current != null &&
          current.format == BookFormat.pdf &&
          action != 'Merge') {
        _initialConsumed = true;
        inputs = [
          EditInput(current.title, () => library.readDocument(current)),
        ];
      } else {
        _initialConsumed = true;
        inputs = await chooseEditSources(context, widget.repository, action);
      }
      if (!mounted || inputs.isEmpty) return;
      final choices = switch (action) {
        'Export' => ['Word (text)', 'Excel (text rows)', 'Page images'],
        'Content' => [
          'Add text',
          'Replace text area',
          'Insert image',
          'Replace image area',
          'Remove area',
        ],
        _ => <String>[],
      };
      if (choices.isNotEmpty) {
        final selected = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final choice in choices)
                  ListTile(
                    title: Text(choice),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, choice),
                  ),
              ],
            ),
          ),
        );
        if (selected == null || !mounted) return;
        action = selected;
      }
      if (action == 'Signature') {
        final kind = await showModalBottomSheet<String>(
          context: context,
          builder: (context) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_outlined),
                  title: const Text('Digital signature'),
                  onTap: () => Navigator.pop(context, 'Digital signature'),
                ),
                ListTile(
                  leading: const Icon(Icons.draw_outlined),
                  title: const Text('Create signature'),
                  onTap: () => Navigator.pop(context, 'Drawn signature'),
                ),
              ],
            ),
          ),
        );
        if (kind == null || !mounted) return;
        action = kind;
      }

      if (action == 'Merge') {
        await _process(action, inputs);
      } else {
        for (final input in inputs) {
          if (!mounted) return;
          await _process(action, [input]);
        }
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not select documents.')),
        );
      }
    }
  }

  Future<Map<String, String>?> fields(
    String title,
    Map<String, String> labels, {
    Set<String> secret = const {},
    Map<String, String> initial = const {},
  }) =>
      showEditFields(context, title, labels, secret: secret, initial: initial);

  Future<Uint8List?> captureSignature() async {
    final controller = SignatureController(
      penStrokeWidth: 3,
      penColor: Colors.black,
      exportBackgroundColor: Colors.transparent,
    );
    try {
      if (!mounted) return null;
      return await showDialog<Uint8List>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Draw signature'),
          content: SizedBox(
            width: 400,
            height: 220,
            child: Signature(
              controller: controller,
              backgroundColor: Colors.white,
            ),
          ),
          actions: [
            TextButton(onPressed: controller.clear, child: const Text('Clear')),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (controller.isEmpty) return;
                final png = await controller.toPngBytes();
                if (context.mounted) Navigator.pop(context, png);
              },
              child: const Text('Use signature'),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _process(String action, List<EditInput> selected) async {
    if (busy || widget.repository is! ImportableLibrary) return;
    setState(() {
      busy = true;
      status = 'Working…';
    });
    try {
      Uint8List? output;
      Uint8List? preview;
      String name = action;
      if (action == 'Create PDF') {
        final values = await fields(action, {'title': 'Title', 'text': 'Text'});
        if (values == null) return;
        name = values['title']!.trim().isEmpty ? 'Document' : values['title']!;
        output = await PdfEditing.create(name, values['text']!);
      } else if (action == 'Scan') {
        output = await scanPdf();
      } else {
        if (selected.isEmpty) {
          throw const FormatException('Choose a PDF first.');
        }
        if (action == 'Merge' && selected.length < 2) {
          throw const FormatException('Choose at least two PDFs to merge.');
        }
        if (action == 'Compress PDF') {
          final original = await selected.first.read();
          if (!mounted) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => PdfCompressionScreen(
                bytes: original,
                title: selected.first.title,
                repository: library,
                onSaved: _didSave,
              ),
            ),
          );
          return;
        }
        final bytes = await _readInput(selected.first);
        if (bytes == null || !mounted) return;
        if (action == 'Create booklet') {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => BookletCreator(
                bytes: bytes,
                title: selected.first.title,
                repository: library,
                onSaved: _didSave,
              ),
            ),
          );
          return;
        }
        if ([
          'Word (text)',
          'Excel (text rows)',
          'Page images',
        ].contains(action)) {
          final result = action == 'Word (text)'
              ? await PdfExport.word(bytes)
              : action == 'Excel (text rows)'
              ? await PdfExport.excel(bytes)
              : await PdfExport.images(bytes, (page) {
                  if (mounted) setState(() => status = 'Exporting page $page…');
                });
          if (!mounted) return;
          final suffix = action == 'Word (text)'
              ? 'docx'
              : action == 'Excel (text rows)'
              ? 'xlsx'
              : 'zip';
          final filename =
              '${selected.first.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.$suffix';
          final outputs = action == 'Page images'
              ? ZipDecoder()
                    .decodeBytes(result)
                    .files
                    .where((file) => file.isFile)
                    .map(
                      (file) => EditedOutput(
                        file.name,
                        Uint8List.fromList(file.content),
                      ),
                    )
                    .toList()
              : [EditedOutput(filename, result)];
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => PdfResultScreen(
                bytes: bytes,
                name: selected.first.title,
                outputs: outputs,
                repository: library,
                onSaved: _didSave,
                message: action == 'Page images'
                    ? 'Each selected output is saved as a PNG image.'
                    : 'Text export. Original page layout may differ.',
              ),
            ),
          );
          return;
        }
        final labels = <String, String>{};
        if (action == 'Rotate') {
          labels['degrees'] = 'Clockwise degrees: 90, 180, or 270';
        }
        if (action == 'Encrypt') {
          labels['open'] = 'Opening password';
          labels['owner'] = 'Owner password';
        }
        if (action == 'Digital signature') {
          labels['certificatePassword'] = 'Certificate password';
        }
        final values = labels.isEmpty
            ? <String, String>{}
            : await fields(
                '$action · ${selected.first.title}',
                labels,
                secret: {'open', 'owner', 'certificatePassword'},
              );
        if (values == null) return;
        const password = '';
        var page = 1;
        if ([
          'Rotate',
          'Redact',
          'Drawn signature',
          'Digital signature',
          'Add text',
          'Replace text area',
          'Insert image',
          'Replace image area',
          'Remove area',
        ].contains(action)) {
          if (!mounted) return;
          final pages = await Navigator.push<List<int>>(
            context,
            MaterialPageRoute(
              builder: (_) => PdfPagePicker(
                bytes: bytes,
                title: 'Choose pages · $action',
                multiple: action == 'Rotate',
              ),
            ),
          );
          if (pages == null || pages.isEmpty || !mounted) return;
          page = pages.first + 1;
          if (action == 'Rotate') {
            values['pages'] = pages.map((i) => '${i + 1}').join(',');
          }
        }
        name = '${selected.first.title} - $action';
        switch (action) {
          case 'Merge':
            final inputs = <Uint8List>[];
            for (final input in selected) {
              final next = identical(input, selected.first)
                  ? bytes
                  : await _readInput(input);
              if (next == null) return;
              inputs.add(next);
            }
            output = await PdfEditing.extract(inputs, password: password);
          case 'Organize':
          case 'Split':
          case 'Extract pages':
          case 'Split into files':
            if (!mounted) return;
            final order = await Navigator.push<List<int>>(
              context,
              MaterialPageRoute(
                builder: (_) => action == 'Organize'
                    ? PdfPageOrganizer(bytes: bytes, title: 'Organize pages')
                    : PdfPagePicker(
                        bytes: bytes,
                        title: action == 'Extract pages'
                            ? 'Select pages to extract'
                            : 'Select pages to split',
                        multiple: true,
                        confirmLabel: 'Continue with',
                      ),
              ),
            );
            if (order == null || !mounted) return;
            if (order.isEmpty) return;
            if (action != 'Organize') {
              final separate = await chooseExtractionMode(
                context,
                order.length,
              );
              if (separate == null || !mounted) return;
              final outputs = <EditedOutput>[];
              if (separate == PdfExtractionMode.separate) {
                for (final index in order) {
                  final part = await PdfEditing.extract(
                    [bytes],
                    pageOrder: [index],
                  );
                  outputs.add(
                    EditedOutput(
                      '${selected.first.title} - Page ${index + 1}.pdf',
                      part,
                    ),
                  );
                }
              } else {
                final part = await PdfEditing.extract([
                  bytes,
                ], pageOrder: order);
                outputs.add(
                  EditedOutput(
                    '${selected.first.title} - Extracted pages.pdf',
                    part,
                  ),
                );
              }
              if (!mounted) return;
              await Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => PdfResultScreen(
                    bytes: outputs.first.bytes,
                    name: selected.first.title,
                    repository: library,
                    onSaved: _didSave,
                    outputs: outputs,
                    autoSave: true,
                  ),
                ),
              );
              return;
            }
            output = await PdfEditing.extract([bytes], pageOrder: order);
          case 'Fill form':
            if (!mounted) return;
            output = await Navigator.push<Uint8List>(
              context,
              MaterialPageRoute(builder: (_) => PdfFormScreen(bytes: bytes)),
            );
          case 'Add text':
          case 'Replace text area':
          case 'Insert image':
          case 'Replace image area':
          case 'Remove area':
            if (!mounted) return;
            final region = await Navigator.push<Rect>(
              context,
              MaterialPageRoute(
                builder: (_) => PdfRegionPicker(
                  bytes: bytes,
                  page: page - 1,
                  title: action,
                ),
              ),
            );
            if (region == null || !mounted) return;
            final initialText = action == 'Replace text area'
                ? PdfEditing.textInArea(bytes, page - 1, region)
                : {'text': '', 'size': '12', 'font': 'Helvetica'};
            var edited = bytes;
            if ([
              'Replace text area',
              'Replace image area',
              'Remove area',
            ].contains(action)) {
              final accepted = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Replace this area?'),
                  content: const Text(
                    'The selected page becomes an image with a white replacement area. Its original searchable text and interactive fields are removed. The original file is kept.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              );
              if (accepted != true) return;
              edited = await PdfEditing.clearArea(bytes, page - 1, region);
            }
            if (!mounted) return;
            if (action.contains('text')) {
              final text = await fields(action, {
                'text': 'Text',
                'size': 'Font size (4–144)',
                'font': initialText['originalFont'] == null
                    ? 'Font: Helvetica, Times, Courier, or TTF'
                    : 'Original: ${initialText['originalFont']} · Choose Helvetica, Times, Courier, or TTF',
              }, initial: initialText);
              if (text == null) return;
              final size = double.tryParse(text['size']!) ?? 12;
              Uint8List? font;
              final familyName = text['font']!.trim().toLowerCase();
              if (familyName == 'ttf') {
                final file = await FilePicker.pickFile(
                  type: FileType.custom,
                  allowedExtensions: ['ttf'],
                );
                if (file == null) return;
                font = await file.readAsBytes();
              }
              final family = switch (familyName) {
                'times' => sf.PdfFontFamily.timesRoman,
                'courier' => sf.PdfFontFamily.courier,
                '' || 'helvetica' || 'ttf' => sf.PdfFontFamily.helvetica,
                _ => throw const FormatException(
                  'Choose Helvetica, Times, Courier, or TTF.',
                ),
              };
              output = await PdfEditing.addText(
                edited,
                page - 1,
                region,
                text['text']!,
                fontSize: size,
                family: family,
                fontBytes: font,
              );
            } else if (action.contains('image')) {
              final picture = await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: ['png', 'jpg', 'jpeg'],
              );
              if (picture == null || !mounted) return;
              final placement = action == 'Insert image'
                  ? region
                  : await Navigator.push<Rect>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdfRegionPicker(
                          bytes: edited,
                          page: page - 1,
                          title: 'Place and resize image',
                        ),
                      ),
                    );
              if (placement == null) return;
              output = await PdfEditing.stamp(
                edited,
                await picture.readAsBytes(),
                page - 1,
                placement,
                '',
              );
            } else {
              output = edited;
            }
          case 'Rotate':
            final degrees = int.tryParse(values['degrees']!);
            if (![90, 180, 270].contains(degrees)) {
              throw const FormatException('Enter 90, 180, or 270.');
            }
            output = await PdfEditing.rotate(
              bytes,
              values['pages']!,
              degrees!,
              password,
            );
          case 'Encrypt':
            if (!mounted) return;
            setState(() => status = 'Encrypting document…');
            output = await encryptPdfInBackground(
              bytes,
              values['open']!,
              values['owner']!,
              password,
            );
            preview = bytes;
          case 'Digital signature':
            final certificate = await FilePicker.pickFile(
              type: FileType.custom,
              allowedExtensions: ['pfx', 'p12'],
            );
            if (certificate == null) return;
            output = await PdfEditing.sign(
              bytes,
              await certificate.readAsBytes(),
              values['certificatePassword']!,
              page - 1,
              password,
            );
          case 'Drawn signature':
            final png = await captureSignature();
            if (png == null || !mounted) return;
            final clean = await PdfEditing.unprotect(bytes, password);
            if (!mounted) return;
            final region = await Navigator.push<Rect>(
              context,
              MaterialPageRoute(
                builder: (_) => PdfRegionPicker(
                  bytes: clean,
                  page: page - 1,
                  title: 'Place signature',
                ),
              ),
            );
            if (region == null) return;
            output = await PdfEditing.stamp(
              bytes,
              png,
              page - 1,
              region,
              password,
            );
          case 'Redact':
            final clean = await PdfEditing.unprotect(bytes, password);
            if (!mounted) return;
            final region = await Navigator.push<Rect>(
              context,
              MaterialPageRoute(
                builder: (_) => PdfRegionPicker(
                  bytes: clean,
                  page: page - 1,
                  title: 'Redact area',
                ),
              ),
            );
            if (region == null) return;
            output = await PdfEditing.redact(clean, page - 1, region);
          case 'OCR':
            output = await recognizePdf(
              await PdfEditing.unprotect(bytes, password),
              (page) {
                if (mounted) setState(() => status = 'Recognizing page $page…');
              },
            );
        }
        if (output != null &&
            password.isNotEmpty &&
            [
              'Rotate',
              'Drawn signature',
              'Digital signature',
            ].contains(action)) {
          preview = await PdfEditing.unprotect(output, password);
        }
      }
      if (output == null || !mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PdfResultScreen(
            bytes: output!,
            previewBytes: preview,
            name: name,
            repository: library,
            onSaved: _didSave,
            message: action == 'Redact'
                ? 'This copy contains flattened images. Text, forms, links, and old annotations are removed.'
                : action == 'Encrypt'
                ? 'Preview before encryption. The saved copy requires your opening password.'
                : action == 'Extract pages'
                ? 'Selected pages copied in original order. DocumentZ annotations remain with the original file.'
                : ['Merge', 'Organize'].contains(action)
                ? 'Page artwork is copied. Forms, links, bookmarks, and app annotations are not transferred.'
                : action == 'OCR'
                ? 'Searchable image copy. Review recognized text for mistakes.'
                : preview != null
                ? 'Unlocked preview. The saved copy keeps its password protection.'
                : null,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message.toString() : 'Could not complete this operation. Check the file and passwords.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Edit', style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 20),
          if (busy) ...[const LinearProgressIndicator(), Text(status)],
          const SizedBox(height: 16),
          _group('Annotations', const {'Annotate': Icons.draw_outlined}),
          _group('Pages', const {
            'Merge': Icons.merge,
            'Split': Icons.call_split,
            'Organize': Icons.dashboard_outlined,
            'Create booklet': Icons.menu_book_outlined,
            'Rotate': Icons.rotate_right,
          }),
          _group('Document', const {
            'Content': Icons.edit_note,
            'Fill form': Icons.list_alt,
            'Export': Icons.ios_share,
            'Compress PDF': Icons.compress,
          }),
          _group('Sign & protect', const {
            'Signature': Icons.gesture,
            'Encrypt': Icons.lock_outline,
          }),
          _group('Create', const {
            'Scan': Icons.document_scanner_outlined,
            'OCR': Icons.text_fields,
          }),
        ],
      ),
    ),
  );

  Widget _group(String title, Map<String, IconData> actions) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Card.filled(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final entry in actions.entries)
                ListTile(
                  minVerticalPadding: 18,
                  leading: Icon(entry.value),
                  title: Text(entry.key),
                  trailing: const Icon(Icons.chevron_right),
                  subtitle:
                      ['Scan', 'OCR'].contains(entry.key) && !mobilePdfSupported
                      ? const Text('Android and iOS')
                      : null,
                  onTap:
                      busy ||
                          widget.repository is! ImportableLibrary ||
                          (['Scan', 'OCR'].contains(entry.key) &&
                              !mobilePdfSupported)
                      ? null
                      : () => run(entry.key),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

class PdfResultScreen extends StatefulWidget {
  const PdfResultScreen({
    super.key,
    required this.bytes,
    required this.name,
    required this.repository,
    required this.onSaved,
    this.previewBytes,
    this.outputs,
    this.autoSave = false,
    this.outputWriter,
    this.previewBuilder,
    this.message,
  });
  final Uint8List bytes;
  final Uint8List? previewBytes;
  final List<EditedOutput>? outputs;
  final bool autoSave;
  final EditOutputWriter? outputWriter;
  final Widget Function(Uint8List bytes)? previewBuilder;
  final String name;
  final String? message;
  final ImportableLibrary repository;
  final VoidCallback onSaved;
  @override
  State<PdfResultScreen> createState() => _PdfResultScreenState();
}

class _PdfResultScreenState extends State<PdfResultScreen> {
  bool saving = false, saved = false, discarded = false, asking = false;
  String? saveError;
  late final saver = EditOutputSaver(
    widget.repository,
    writer: widget.outputWriter,
  );
  late final outputs =
      widget.outputs ?? [EditedOutput('${widget.name}.pdf', widget.bytes)];
  @override
  void initState() {
    super.initState();
    if (widget.autoSave) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _saveCopy();
        }
      });
    }
  }

  Future<void> _saveCopy() async {
    if (saving || saved) return;
    setState(() {
      saving = true;
      saveError = null;
    });
    try {
      await saver.save(outputs);
      if (!mounted) return;
      setState(() => saved = true);
      // Let PopScope rebuild before completing this route.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onSaved();
        Navigator.pop(context);
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => saveError =
              'Save failed. Check storage and permissions, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _confirmExit() async {
    if (asking || saving) return;
    asking = true;
    try {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Discard this edit?'),
          content: const Text('The original file is unchanged.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard == true && mounted) {
        setState(() => discarded = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    } finally {
      asking = false;
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: saved || discarded,
    onPopInvokedWithResult: (didPop, value) {
      if (!didPop) _confirmExit();
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Preview')),
      body: Column(
        children: [
          if (widget.message != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(widget.message!),
            ),
          Expanded(
            child:
                widget.previewBuilder?.call(
                  widget.previewBytes ?? widget.bytes,
                ) ??
                PdfLinkPreview(bytes: widget.previewBytes ?? widget.bytes),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Saves to Downloads / DocumentZ and Recent'),
                  if (saveError != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        saveError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: saving || saved ? null : _saveCopy,
                    icon: const Icon(Icons.save_alt),
                    label: Text(saving ? 'Saving…' : 'Save'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
