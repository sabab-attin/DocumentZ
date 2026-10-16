import '../domain/book.dart';

// Document imports have no application-level byte cap. Archive expansion and
// malformed-content checks remain independent of the source file size.
const officeArchiveFormats = {
  BookFormat.docx,
  BookFormat.xlsx,
  BookFormat.pptx,
  BookFormat.odt,
  BookFormat.ods,
  BookFormat.odp,
};
const rasterFormats = {
  BookFormat.png,
  BookFormat.jpg,
  BookFormat.jpeg,
  BookFormat.tiff,
  BookFormat.tif,
  BookFormat.bmp,
  BookFormat.gif,
};
const conversionFormats = {
  BookFormat.doc,
  BookFormat.xls,
  BookFormat.ppt,
  BookFormat.mobi,
  BookFormat.eps,
  BookFormat.ps,
};
const documentExtensions = [
  'pdf',
  'epub',
  'txt',
  'md',
  'markdown',
  'docx',
  'doc',
  'xlsx',
  'xls',
  'pptx',
  'ppt',
  'odt',
  'ods',
  'odp',
  'rtf',
  'html',
  'htm',
  'mhtml',
  'mht',
  'mobi',
  'png',
  'jpg',
  'jpeg',
  'tiff',
  'tif',
  'bmp',
  'gif',
  'svg',
  'eps',
  'ps',
];

BookFormat importFormat(String name) {
  final extension = name.split('.').last.toLowerCase();
  if (extension == 'md') return BookFormat.markdown;
  if (extension == 'mht') return BookFormat.mhtml;
  for (final format in BookFormat.values) {
    if (format.name == extension) return format;
  }
  throw const FormatException('This document format is not supported.');
}

void validateDocumentHeader(BookFormat format, List<int> header, int length) {
  if (length == 0) throw const FormatException('This file is empty.');
  if (format == BookFormat.pdf) {
    if (!String.fromCharCodes(header).contains('%PDF-')) {
      throw const FormatException('This file does not appear to be a PDF.');
    }
  } else if (format == BookFormat.epub ||
      officeArchiveFormats.contains(format)) {
    if (header.length < 4 ||
        header[0] != 0x50 ||
        header[1] != 0x4b ||
        header[2] != 3 ||
        header[3] != 4) {
      throw FormatException(
        'This file does not appear to be a ${format.name.toUpperCase()} archive. Encrypted Office files must be unlocked first.',
      );
    }
  } else if ({
    BookFormat.doc,
    BookFormat.xls,
    BookFormat.ppt,
  }.contains(format)) {
    const signature = [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1];
    if (header.length < 8 ||
        List.generate(8, (i) => header[i] == signature[i]).contains(false)) {
      throw const FormatException(
        'This file does not appear to be a legacy Office document.',
      );
    }
  }
}

String documentTitle(String name) {
  final base = name.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  final title = (dot > 0 ? base.substring(0, dot) : base).trim();
  return title.isEmpty ? 'Untitled book' : title;
}
