import '../domain/book.dart';

// Browse lists readable documents. Image import and conversion tools retain
// their wider format lists without filling Browse with photos or graphics.
const browseDocumentExtensions = [
  'pdf',
  'epub',
  'mobi',
  'txt',
  'md',
  'markdown',
  'docx',
  'xlsx',
  'pptx',
  'odt',
  'ods',
  'odp',
  'rtf',
  'html',
  'htm',
  'mhtml',
  'mht',
];

bool isBrowseDocumentName(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 &&
      browseDocumentExtensions.contains(name.substring(dot + 1).toLowerCase());
}

bool isBrowseDocumentFormat(BookFormat format) =>
    browseDocumentExtensions.contains(format.name);
