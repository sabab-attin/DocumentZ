import 'package:pdfrx/pdfrx.dart';

// Browser PDF backends do not expose page objects. Keep the original artwork.
const supportsPdfPageColors = false;
PdfDocument applyPdfPageColors(PdfDocument document) => document;
