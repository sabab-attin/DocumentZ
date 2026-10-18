import 'package:flutter/material.dart';

enum PdfExtractionMode { single, separate }

Future<PdfExtractionMode?> chooseExtractionMode(
  BuildContext context,
  int count,
) {
  if (count < 1) throw const FormatException('Select pages before extracting.');
  return showModalBottomSheet<PdfExtractionMode>(
    context: context,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(title: Text('Extract $count selected pages')),
          ListTile(
            title: const Text('Single file'),
            subtitle: const Text('All selected pages in one PDF'),
            onTap: () => Navigator.pop(sheet, PdfExtractionMode.single),
          ),
          ListTile(
            title: const Text('Separate files'),
            subtitle: const Text('One PDF for each selected page'),
            onTap: () => Navigator.pop(sheet, PdfExtractionMode.separate),
          ),
        ],
      ),
    ),
  );
}
