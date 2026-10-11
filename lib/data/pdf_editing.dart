import 'dart:typed_data';
import 'dart:ui';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:image/image.dart' as image;

List<int> parsePageRange(String value, int count) {
  if (value.trim().isEmpty) return List.generate(count, (i) => i);
  final result = <int>{};
  for (final part in value.split(',')) {
    final range = part.trim().split('-');
    final first = int.tryParse(range.first);
    final last = range.length == 1 ? first : int.tryParse(range.last);
    if (range.length > 2 || first == null || last == null || first < 1 || last < first || last > count) {
      throw FormatException('Enter page numbers from 1 to $count, such as 1,3-5.');
    }
    for (int page = first; page <= last; page++) { result.add(page - 1); }
  }
  return result.toList();
}

class PdfEditing {
  static sf.PdfDocument open(Uint8List bytes, String password) => sf.PdfDocument(inputBytes: bytes, password: password);
  static Future<Uint8List> save(sf.PdfDocument document) async => Uint8List.fromList(await document.save());

  static Map<String, String> textInArea(Uint8List bytes, int pageIndex, Rect region) {
    final document = open(bytes, '');
    try {
      final size = document.pages[pageIndex].getClientSize();
      final bounds = Rect.fromLTWH(region.left * size.width, region.top * size.height, region.width * size.width, region.height * size.height);
      final lines = sf.PdfTextExtractor(document).extractTextLines(startPageIndex: pageIndex, endPageIndex: pageIndex)
        .where((line) => line.bounds.overlaps(bounds)).toList();
      if (lines.isEmpty) return {'text': '', 'size': '12', 'font': 'Helvetica'};
      final name = lines.first.fontName.toLowerCase();
      final family = name.contains('times') ? 'Times' : name.contains('courier') ? 'Courier' : 'Helvetica';
      return {'text': lines.map((line) => line.wordCollection.where((word) => word.bounds.overlaps(bounds)).map((word) => word.text).join(' ')).join('\n'),
        'size': lines.first.fontSize.toStringAsFixed(1), 'font': family, 'originalFont': lines.first.fontName};
    } finally { document.dispose(); }
  }

  static Future<Uint8List> unprotect(Uint8List bytes, String password) async {
    final document = open(bytes, password);
    try {
      document.security.userPassword = '';
      document.security.ownerPassword = '';
      return await save(document);
    } finally { document.dispose(); }
  }

  static Future<Uint8List> extract(List<Uint8List> inputs, {String pages = '', String password = '', List<int>? pageOrder}) async {
    final output = sf.PdfDocument();
    final sources = <sf.PdfDocument>[];
    try {
      for (final bytes in inputs) {
        final source = open(bytes, password);
        sources.add(source);
        final indices = pageOrder ?? parsePageRange(pages, source.pages.count);
        if (indices.isEmpty || indices.any((i) => i < 0 || i >= source.pages.count)) throw const FormatException('Choose valid pages.');
        for (final index in indices) {
          final template = source.pages[index].createTemplate();
          final section = output.sections!.add();
          section.pageSettings.size = template.size;
          section.pageSettings.margins.all = 0;
          section.pages.add().graphics.drawPdfTemplate(template, Offset.zero);
        }
      }
      return await save(output);
    } finally { output.dispose(); for (final source in sources) { source.dispose(); } }
  }

  static Future<Uint8List> rotate(Uint8List bytes, String pages, int degrees, String password) async {
    final document = open(bytes, password);
    try {
      for (final index in parsePageRange(pages, document.pages.count)) {
        final page = document.pages[index];
        final next = (page.rotation.index + degrees ~/ 90) % 4;
        page.rotation = sf.PdfPageRotateAngle.values[next];
      }
      return await save(document);
    } finally { document.dispose(); }
  }

  static Future<Uint8List> encrypt(Uint8List bytes, String password, String owner, String sourcePassword) async {
    if (password.isEmpty || owner.isEmpty || password == owner) {
      throw const FormatException('Use different, nonempty opening and owner passwords.');
    }
    final document = open(bytes, sourcePassword);
    try {
      document.security.userPassword = password;
      document.security.ownerPassword = owner;
      document.security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      return await save(document);
    } finally { document.dispose(); }
  }

  static Future<Uint8List> stamp(Uint8List bytes, Uint8List png, int pageIndex, Rect region, String password) async {
    final document = open(bytes, password);
    try {
      final page = document.pages[pageIndex];
      final size = page.getClientSize();
      page.graphics.drawImage(sf.PdfBitmap(png), Rect.fromLTWH(
        region.left * size.width, region.top * size.height, region.width * size.width, region.height * size.height));
      return await save(document);
    } finally { document.dispose(); }
  }

  static Future<Uint8List> addText(Uint8List bytes, int pageIndex, Rect region, String text,
      {double fontSize = 12, sf.PdfFontFamily family = sf.PdfFontFamily.helvetica, Uint8List? fontBytes}) async {
    if (text.isEmpty || !fontSize.isFinite || fontSize < 4 || fontSize > 144) throw const FormatException('Enter text and a font size from 4 to 144.');
    if (fontBytes == null && text.runes.any((c) => c > 255)) throw const FormatException('Load a TTF font for this script.');
    final document = open(bytes, '');
    try {
      final page = document.pages[pageIndex];
      final size = page.getClientSize();
      final bounds = Rect.fromLTWH(region.left * size.width, region.top * size.height, region.width * size.width, region.height * size.height);
      final sf.PdfFont font = fontBytes == null ? sf.PdfStandardFont(family, fontSize) : sf.PdfTrueTypeFont(fontBytes, fontSize);
      final measured = font.measureString(text, layoutArea: Size(bounds.width, 0));
      if (measured.height > bounds.height || measured.width > bounds.width + 1) throw const FormatException('Text does not fit. Choose a larger area or smaller font.');
      page.graphics.drawString(text, font, brush: sf.PdfBrushes.black, bounds: bounds);
      return await save(document);
    } finally { document.dispose(); }
  }

  /// A reviewed visual correction: rebuild the chosen page without its old
  /// content objects. Other pages retain their artwork through templates.
  static Future<Uint8List> clearArea(Uint8List bytes, int pageIndex, Rect region, {PdfRaster? rasterOverride}) async {
    final raster = rasterOverride ?? await Printing.raster(bytes, pages: [pageIndex], dpi: 144).first;
    final pixels = image.decodePng(await raster.toPng())!;
    image.fillRect(pixels, x1: (region.left * pixels.width).floor(), y1: (region.top * pixels.height).floor(),
      x2: (region.right * pixels.width).ceil().clamp(0, pixels.width - 1), y2: (region.bottom * pixels.height).ceil().clamp(0, pixels.height - 1),
      color: image.ColorRgb8(255, 255, 255));
    final original = open(bytes, '');
    final output = sf.PdfDocument();
    try {
      for (int i = 0; i < original.pages.count; i++) {
        final template = original.pages[i].createTemplate();
        final section = output.sections!.add(); section.pageSettings.margins.all = 0;
        section.pageSettings.size = i == pageIndex ? Size(raster.width / 2, raster.height / 2) : template.size;
        final page = section.pages.add();
        if (i == pageIndex) {
          page.graphics.drawImage(sf.PdfBitmap(image.encodePng(pixels)), Offset.zero & section.pageSettings.size);
        } else { page.graphics.drawPdfTemplate(template, Offset.zero); }
      }
      return await save(output);
    } finally { output.dispose(); original.dispose(); }
  }

  static Future<Uint8List> sign(Uint8List bytes, Uint8List certificate, String certificatePassword,
      int pageIndex, String password) async {
    final document = open(bytes, password);
    try {
      final page = document.pages[pageIndex];
      final field = sf.PdfSignatureField(page, 'Signature_${DateTime.now().microsecondsSinceEpoch}',
        bounds: const Rect.fromLTWH(24, 24, 200, 60),
        signature: sf.PdfSignature(certificate: sf.PdfCertificate(certificate, certificatePassword)));
      document.form.fields.add(field);
      return await save(document);
    } finally { document.dispose(); }
  }

  /// Creates new image-only pages; masked source pixels and all old PDF objects are omitted.
  static Future<Uint8List> redact(Uint8List bytes, int pageIndex, Rect region, {Stream<PdfRaster>? rasters}) async {
    final document = pw.Document();
    int index = 0;
    await for (final raster in rasters ?? Printing.raster(bytes, dpi: 144)) {
      final pixels = image.decodePng(await raster.toPng())!;
      if (index == pageIndex) {
        image.fillRect(pixels, x1: (region.left * pixels.width).floor(), y1: (region.top * pixels.height).floor(),
          x2: (region.right * pixels.width).ceil().clamp(0, pixels.width - 1),
          y2: (region.bottom * pixels.height).ceil().clamp(0, pixels.height - 1), color: image.ColorRgb8(0, 0, 0));
      }
      final picture = pw.MemoryImage(image.encodePng(pixels));
      document.addPage(pw.Page(pageFormat: PdfPageFormat(raster.width / 2, raster.height / 2, marginAll: 0),
        build: (_) => pw.Image(picture, fit: pw.BoxFit.fill)));
      index++;
    }
    if (index == 0 || pageIndex >= index) throw const FormatException('Page not found.');
    return document.save();
  }

  static Future<Uint8List> create(String title, String text) async {
    if ('$title$text'.runes.any((value) => value > 255)) {
      throw const FormatException('This PDF font supports Latin text. Other scripts need an embedded font.');
    }
    final document = pw.Document();
    document.addPage(pw.MultiPage(build: (_) => [pw.Header(level: 0, child: pw.Text(title)), pw.Text(text)]));
    return document.save();
  }
}
