import 'dart:typed_data';

import '../domain/book.dart';

bool get supportsLocalConversion => false;
String conversionTool(BookFormat format) => 'Windows conversion software';
Future<Uint8List> convertDocumentToPdf(
  Uint8List bytes,
  BookFormat format, {
  String? executable,
}) async => throw const FormatException(
  'Convert this document to PDF in the Windows app, then import the PDF here.',
);
