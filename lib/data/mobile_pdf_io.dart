import 'dart:io';
import 'dart:typed_data';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as image;

bool get mobilePdfSupported => Platform.isAndroid || Platform.isIOS;

Future<Uint8List?> scanPdf() async {
  final paths = await CunningDocumentScanner.getPictures(noOfPages: 30);
  if (paths == null || paths.isEmpty) return null;
  final document = pw.Document();
  try {
    for (final path in paths) {
      final bytes = await File(path).readAsBytes();
      final decoded = image.decodeImage(bytes);
      if (decoded == null) throw const FormatException('Could not read a scanned page.');
      final picture = pw.MemoryImage(bytes);
      document.addPage(pw.Page(pageFormat: PdfPageFormat(decoded.width / 2, decoded.height / 2, marginAll: 0),
        build: (_) => pw.Image(picture, fit: pw.BoxFit.fill)));
    }
    return await document.save();
  } finally { await CunningDocumentScanner.cleanCache(); }
}

Future<Uint8List> recognizePdf(Uint8List bytes, void Function(int) progress) async {
  final directory = await Directory((await getTemporaryDirectory()).path).createTemp('reader-ocr-');
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final output = pw.Document();
  int page = 0, linesFound = 0;
  try {
    await for (final raster in Printing.raster(bytes, dpi: 144)) {
      progress(++page);
      final png = await raster.toPng();
      final file = File('${directory.path}/page.png');
      await file.writeAsBytes(png, flush: true);
      final recognized = await recognizer.processImage(InputImage.fromFilePath(file.path));
      final lines = recognized.blocks.expand((block) => block.lines).toList();
      linesFound += lines.length;
      if (lines.any((line) => line.text.runes.any((value) => value > 255))) {
        throw const FormatException('OCR found characters that need an embedded font. This version supports Latin text.');
      }
      final picture = pw.MemoryImage(png);
      final width = raster.width / 2, height = raster.height / 2;
      output.addPage(pw.Page(pageFormat: PdfPageFormat(width, height, marginAll: 0), build: (_) => pw.Stack(children: [
        pw.Positioned.fill(child: pw.Image(picture, fit: pw.BoxFit.fill)),
        for (final line in lines)
          pw.Positioned(left: line.boundingBox.left / 2, top: line.boundingBox.top / 2,
            child: pw.SizedBox(width: line.boundingBox.width / 2, height: line.boundingBox.height / 2,
              child: pw.FittedBox(fit: pw.BoxFit.fill, child: pw.Text(line.text,
                style: pw.TextStyle(fontSize: 12, renderingMode: PdfTextRenderingMode.invisible))))),
      ])));
    }
    if (linesFound == 0) throw const FormatException('No text recognized. Try a sharper scan.');
    return await output.save();
  } finally { await recognizer.close(); await directory.delete(recursive: true); }
}
