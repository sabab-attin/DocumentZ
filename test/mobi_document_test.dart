import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/mobi_document.dart';

Uint8List fixtureMobi(String markup, {bool encrypted = false}) {
  final text = utf8.encode(markup);
  const first = 94, headerLength = 264;
  final bytes = Uint8List(first + headerLength + text.length);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('Book'));
  data.setUint16(76, 2);
  data.setUint32(78, first);
  data.setUint32(86, first + headerLength);
  data.setUint16(first, 1);
  data.setUint32(first + 4, text.length);
  data.setUint16(first + 8, 1);
  data.setUint16(first + 12, encrypted ? 1 : 0);
  bytes.setRange(first + 16, first + 20, ascii.encode('MOBI'));
  data.setUint32(first + 20, 232);
  data.setUint32(first + 28, 65001);
  data.setUint32(first + 36, 6);
  data.setUint32(first + 108, 0xffffffff);
  bytes.setRange(first + headerLength, bytes.length, text);
  return bytes;
}

void main() {
  test('classic MOBI extracts UTF-8 text and internal links', () {
    final book = parseMobi(
      fixtureMobi('<p>Déjà vu</p><a filepos="0">Back</a>'),
    );
    expect(book.sections.single.html, contains('Déjà vu'));
    expect(book.sections.single.html, contains('#filepos-0'));
    expect(book.sections.single.html, contains('id="filepos-0"'));
  });
  test('PalmDOC expands literals, spaces and overlapping backreferences', () {
    expect(utf8.decode(decodePalmDoc([97, 98, 99, 128, 24])), 'abcabc');
    expect(utf8.decode(decodePalmDoc([1, 65, 193])), 'A A');
    expect(() => decodePalmDoc([128]), throwsFormatException);
    expect(() => decodePalmDoc([128, 8]), throwsFormatException);
  });
  test('encrypted and malformed MOBI are refused', () {
    expect(
      () => parseMobi(fixtureMobi('<p>Private</p>', encrypted: true)),
      throwsFormatException,
    );
    expect(() => parseMobi(Uint8List(20)), throwsFormatException);
  });
}
