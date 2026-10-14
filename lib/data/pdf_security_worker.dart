import 'package:flutter/foundation.dart';

import 'pdf_editing.dart';

/// Only document bytes and strings cross the isolate boundary; never PDF handles.
Future<Uint8List> encryptPdfInBackground(
  Uint8List bytes,
  String opening,
  String owner,
  String sourcePassword,
) => compute(_encrypt, (
  bytes: bytes,
  opening: opening,
  owner: owner,
  sourcePassword: sourcePassword,
));

Future<Uint8List> _encrypt(
  ({Uint8List bytes, String opening, String owner, String sourcePassword}) job,
) => PdfEditing.encrypt(job.bytes, job.opening, job.owner, job.sourcePassword);

Future<int> pdfPageCountInBackground(Uint8List bytes) =>
    compute(_pageCount, bytes);
int _pageCount(Uint8List bytes) {
  final document = PdfEditing.open(bytes, '');
  try {
    return document.pages.count;
  } finally {
    document.dispose();
  }
}

Future<Uint8List> unlockPdfInBackground(Uint8List bytes, String password) =>
    compute(_unlock, (bytes: bytes, password: password));
Future<Uint8List> _unlock(({Uint8List bytes, String password}) job) =>
    PdfEditing.unprotect(job.bytes, job.password);
