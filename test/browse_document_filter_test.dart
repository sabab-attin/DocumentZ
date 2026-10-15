import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/browse_formats.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/shelf_preferences.dart';

void main() {
  test('Browse lists readable documents without photos or arbitrary files', () {
    for (final name in [
      'book.PDF',
      'book.epub',
      'book.mobi',
      'notes.txt',
      'notes.md',
      'notes.markdown',
      'report.docx',
      'sheet.xlsx',
      'slides.pptx',
      'report.odt',
      'sheet.ods',
      'slides.odp',
      'notes.rtf',
      'page.html',
      'page.htm',
      'page.mhtml',
      'page.mht',
    ]) {
      expect(isBrowseDocumentName(name), isTrue, reason: name);
    }
    for (final name in [
      'photo.jpg',
      'photo.JPEG',
      'animation.gif',
      'scan.png',
      'scan.tiff',
      'image.bmp',
      'drawing.svg',
      'image.eps',
      'print.ps',
      'archive.zip',
      'app.apk',
      'file.pdf.exe',
      'no-extension',
      '.pdf',
      'old.doc',
      'old.xls',
      'old.ppt',
    ]) {
      expect(isBrowseDocumentName(name), isFalse, reason: name);
    }
    expect(isBrowseDocumentFormat(BookFormat.markdown), isTrue);
    expect(isBrowseDocumentFormat(BookFormat.jpeg), isFalse);
  });

  test(
    'Browse migrates to newest modified first once and remembers later choices',
    () async {
      SharedPreferences.setMockInitialValues({
        'documentz.shelf.device-library.sort': 'name',
        'documentz.shelf.device-library.descending': false,
        'documentz.shelf.device-library.group': true,
      });
      final shelf = ShelfPreferences('device-library', newestFirst: true);
      await shelf.load();
      expect(shelf.sort, ShelfSort.modified);
      expect(shelf.descending, isTrue);
      expect(shelf.groupByType, isFalse);
      final records = [
        const ShelfOrderData(id: 'old', name: 'A', type: 'pdf', modified: 10),
        const ShelfOrderData(id: 'new', name: 'Z', type: 'pdf', modified: 30),
        const ShelfOrderData(id: 'unknown', name: 'B', type: 'pdf'),
      ]..sort(shelf.compare);
      expect(records.map((item) => item.id), ['new', 'old', 'unknown']);
      await shelf.choose(sort: ShelfSort.name, descending: false);
      shelf.dispose();
      final restored = ShelfPreferences('device-library', newestFirst: true);
      await restored.load();
      expect(restored.sort, ShelfSort.name);
      expect(restored.descending, isFalse);
      restored.dispose();
    },
  );
}
