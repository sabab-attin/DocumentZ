enum BookFormat {
  pdf,
  epub,
  txt,
  markdown,
  docx,
  doc,
  xlsx,
  xls,
  pptx,
  ppt,
  odt,
  ods,
  odp,
  rtf,
  html,
  htm,
  mhtml,
  mobi,
  png,
  jpg,
  jpeg,
  tiff,
  tif,
  bmp,
  gif,
  svg,
  eps,
  ps,
}

class Book {
  const Book({
    required this.id,
    required this.title,
    required this.format,
    this.text,
    this.localPath,
  });
  final String id;
  final String title;
  final BookFormat format;
  final String? text;
  final String? localPath;
}

class ReadingPosition {
  const ReadingPosition({
    required this.bookId,
    required this.locator,
    required this.updatedAt,
  });
  final String bookId;
  // Adapter-specific locator: page, EPUB CFI, or text offset.
  final String locator;
  final DateTime updatedAt;
}
