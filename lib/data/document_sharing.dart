import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/book.dart';
import '../domain/services.dart';

Future<void> shareBytes(
  BuildContext context,
  Uint8List bytes,
  String name,
) async {
  final box = context.findRenderObject();
  await SharePlus.instance.share(
    ShareParams(
      files: [
        XFile.fromData(
          bytes,
          mimeType: switch (name.toLowerCase().split('.').last) {
            'pdf' => 'application/pdf',
            'epub' => 'application/epub+zip',
            'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
            'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
            'doc' => 'application/msword',
            'xls' => 'application/vnd.ms-excel',
            'ppt' => 'application/vnd.ms-powerpoint',
            'odt' => 'application/vnd.oasis.opendocument.text',
            'ods' => 'application/vnd.oasis.opendocument.spreadsheet',
            'odp' => 'application/vnd.oasis.opendocument.presentation',
            'rtf' => 'application/rtf',
            'html' || 'htm' => 'text/html',
            'mhtml' => 'multipart/related',
            'mobi' => 'application/x-mobipocket-ebook',
            'jpg' || 'jpeg' => 'image/jpeg',
            'tif' || 'tiff' => 'image/tiff',
            'bmp' => 'image/bmp',
            'gif' => 'image/gif',
            'svg' => 'image/svg+xml',
            'eps' || 'ps' => 'application/postscript',
            'zip' => 'application/zip',
            'png' => 'image/png',
            _ => 'text/plain',
          },
        ),
      ],
      fileNameOverrides: [name],
      sharePositionOrigin: box is RenderBox
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    ),
  );
}

Future<void> shareDocument(
  BuildContext context,
  ImportableLibrary repository,
  Book book,
) async {
  try {
    final bytes = await repository.readDocument(book);
    if (!context.mounted) return;
    final safeTitle = book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    await shareBytes(context, bytes, '$safeTitle.${book.format.name}');
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not share this document.')),
      );
    }
  }
}
