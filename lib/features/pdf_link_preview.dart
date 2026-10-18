import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/document_links.dart';

/// The same interactive link handling used by the document reader.
class PdfLinkPreview extends StatefulWidget {
  const PdfLinkPreview({
    super.key,
    required this.bytes,
    this.initialPage = 1,
    this.onPageChanged,
    this.controller,
  });
  final Uint8List bytes;
  final int initialPage;
  final ValueChanged<int>? onPageChanged;
  final PdfViewerController? controller;
  @override
  State<PdfLinkPreview> createState() => _PdfLinkPreviewState();
}

class _PdfLinkPreviewState extends State<PdfLinkPreview> {
  late final viewer = widget.controller ?? PdfViewerController();
  @override
  Widget build(BuildContext context) => PdfViewer(
    PdfDocumentRefData(
      widget.bytes,
      sourceName: 'edit-preview',
      key: PdfDocumentRefKey('edit-preview', [widget.bytes]),
    ),
    controller: viewer,
    initialPageNumber: widget.initialPage,
    params: PdfViewerParams(
      onPageChanged: (page) {
        if (page != null) {
          widget.onPageChanged?.call(page);
        }
      },
      linkHandlerParams: PdfLinkHandlerParams(
        onLinkTap: (link) async {
          final opened = await followPdfLink(
            link,
            goToDestination: (destination) => viewer.goToDest(destination),
          );
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This link target is not available in this document.',
                ),
              ),
            );
          }
        },
      ),
    ),
  );
}
