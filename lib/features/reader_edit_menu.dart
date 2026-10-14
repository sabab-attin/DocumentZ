import 'package:flutter/material.dart';

import '../domain/book.dart';
import '../domain/services.dart';
import '../data/mobile_pdf.dart';
import 'edit.dart';
import 'reader_controls.dart';
import 'selection_panel.dart';

/// Editing commands share the editor implementation and use the open PDF.
class ReaderEditMenu extends StatelessWidget {
  const ReaderEditMenu({
    super.key,
    required this.book,
    required this.repository,
    this.onAnnotate,
  });
  final VoidCallback? onAnnotate;
  final Book book;
  final ImportableLibrary repository;

  void _open(BuildContext context, String action) {
    ReaderControlsScope.of(context)?.value = false;
    if (action == 'Annotate' && onAnnotate != null) {
      onAnnotate!();
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Edit document')),
          body: SafeArea(
            child: EditScreen(
              repository: repository,
              onSaved: () {},
              initialDocument:
                  action == 'Annotate' || book.format == BookFormat.pdf
                  ? book
                  : null,
              initialAction: action,
            ),
          ),
        ),
      ),
    );
  }

  Widget _group(
    BuildContext context,
    String title,
    Map<String, IconData> actions,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Text(
          title,
          style: const TextStyle(
            color: readerPanelInk,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      ReaderMenuGrid(
        children: [
          for (final entry in actions.entries)
            ReaderMenuAction(
              label: entry.key,
              icon: entry.value,
              onTap: ['Scan', 'OCR'].contains(entry.key) && !mobilePdfSupported
                  ? null
                  : () => _open(context, entry.key),
            ),
        ],
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: const EdgeInsets.symmetric(horizontal: 4),
    leading: const Icon(Icons.edit_document, color: readerPanelInk),
    title: Text(
      book.format == BookFormat.pdf ? 'Edit document' : 'PDF tools',
      style: const TextStyle(
        color: readerPanelInk,
        fontWeight: FontWeight.w600,
      ),
    ),
    iconColor: readerPanelInk,
    collapsedIconColor: readerPanelInk,
    shape: const Border(),
    collapsedShape: const Border(),
    children: [
      _group(context, 'Annotations', const {'Annotate': Icons.draw_outlined}),
      _group(context, 'Pages', const {
        'Merge': Icons.merge,
        'Split': Icons.call_split,
        'Organize': Icons.dashboard_outlined,
        'Create booklet': Icons.menu_book_outlined,
        'Rotate': Icons.rotate_right,
      }),
      _group(context, 'Document', const {
        'Content': Icons.edit_note,
        'Fill form': Icons.list_alt,
        'Export': Icons.ios_share,
        'Compress PDF': Icons.compress,
      }),
      _group(context, 'Sign & protect', const {
        'Signature': Icons.gesture,
        'Encrypt': Icons.lock_outline,
      }),
      _group(context, 'Create', const {
        'Create PDF': Icons.note_add_outlined,
        'Scan': Icons.document_scanner_outlined,
        'OCR': Icons.text_fields,
      }),
    ],
  );
}
