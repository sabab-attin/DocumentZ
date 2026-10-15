import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;

import 'epub_document.dart';

/// Classic, unencrypted MOBI/PalmDOC records. Unsupported encodings, HUFF/CDIC
/// and KF8 require conversion; they are never treated as plain text.
EpubDocumentData parseMobi(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  void requireRange(int start, int length) {
    if (start < 0 || length < 0 || start + length > bytes.length) {
      throw const FormatException('Invalid MOBI record.');
    }
  }

  int u16(int offset) {
    requireRange(offset, 2);
    return data.getUint16(offset);
  }

  int u32(int offset) {
    requireRange(offset, 4);
    return data.getUint32(offset);
  }

  requireRange(0, 78);
  final count = u16(76);
  if (count < 2 || count > 65535) {
    throw const FormatException('Missing MOBI records.');
  }
  requireRange(78, count * 8);
  final offsets = [
    for (var i = 0; i < count; i++) u32(78 + i * 8),
    bytes.length,
  ];
  for (var i = 0; i < count; i++) {
    if (offsets[i] < 78 + count * 8 || offsets[i] >= offsets[i + 1]) {
      throw const FormatException('Invalid MOBI record table.');
    }
  }
  final first = offsets[0], end = offsets[1];
  requireRange(first, 16);
  final compression = u16(first),
      expected = u32(first + 4),
      records = u16(first + 8);
  if (u16(first + 12) != 0) {
    throw const FormatException('DRM-protected MOBI is unsupported.');
  }
  if (![1, 2].contains(compression) ||
      records == 0 ||
      records >= count ||
      expected > 20 * 1024 * 1024) {
    throw const FormatException('This MOBI variant requires conversion.');
  }
  var encoding = 1252, flags = 0, firstImage = count;
  String title = latin1
      .decode(bytes.sublist(0, 32))
      .split(String.fromCharCode(0))
      .first;
  if (end - first >= 40 &&
      ascii.decode(bytes.sublist(first + 16, first + 20), allowInvalid: true) ==
          'MOBI') {
    final length = u32(first + 20);
    if (length < 24 || first + 16 + length > end || u32(first + 36) > 6) {
      throw const FormatException(
        'KF8 or an invalid MOBI header requires conversion.',
      );
    }
    encoding = u32(first + 28);
    if (length >= 96) {
      firstImage = u32(first + 108);
    }
    if (length >= 228) {
      flags = u16(first + 242);
    }
    if (length >= 76) {
      final nameStart = first + u32(first + 84), nameLength = u32(first + 88);
      if (nameStart >= first &&
          nameStart + nameLength <= end &&
          nameLength > 0) {
        title = utf8.decode(
          bytes.sublist(nameStart, nameStart + nameLength),
          allowMalformed: true,
        );
      }
    }
  }
  if (![1252, 65001].contains(encoding)) {
    throw const FormatException('This MOBI text encoding requires conversion.');
  }
  final text = BytesBuilder(copy: false);
  for (var r = 1; r <= records; r++) {
    var record = bytes.sublist(offsets[r], offsets[r + 1]);
    var tailFlags = flags >> 1;
    while (tailFlags != 0) {
      if ((tailFlags & 1) != 0) {
        var length = 0, shift = 0;
        for (var i = record.length - 1; i >= 0 && shift < 28; i--) {
          final b = record[i];
          length |= (b & 127) << shift;
          shift += 7;
          if ((b & 128) != 0) {
            break;
          }
        }
        if (length <= 0 || length > record.length) {
          throw const FormatException('Invalid MOBI trailing data.');
        }
        record = record.sublist(0, record.length - length);
      }
      tailFlags >>= 1;
    }
    if ((flags & 1) != 0) {
      if (record.isEmpty) {
        throw const FormatException('Missing MOBI overlap data.');
      }
      final length = (record.last & 3) + 1;
      if (length > record.length) {
        throw const FormatException('Invalid MOBI overlap data.');
      }
      record = record.sublist(0, record.length - length);
    }
    text.add(compression == 1 ? record : decodePalmDoc(record));
    if (text.length > 20 * 1024 * 1024) {
      throw const FormatException('MOBI text is too large.');
    }
  }
  final raw = text.takeBytes();
  if (expected > raw.length) {
    throw const FormatException('Truncated MOBI text.');
  }
  final content = raw.sublist(0, expected);
  const cp1252 = <int>[
    8364,
    129,
    8218,
    402,
    8222,
    8230,
    8224,
    8225,
    710,
    8240,
    352,
    8249,
    338,
    141,
    381,
    143,
    144,
    8216,
    8217,
    8220,
    8221,
    8226,
    8211,
    8212,
    732,
    8482,
    353,
    8250,
    339,
    157,
    382,
    376,
  ];
  String decode(List<int> input) => encoding == 65001
      ? utf8.decode(input, allowMalformed: true)
      : String.fromCharCodes(
          input.map((b) => b >= 128 && b < 160 ? cp1252[b - 128] : b),
        );
  var markup = decode(content);
  final links =
      html
          .parse(markup)
          .querySelectorAll('a[filepos]')
          .map((e) => int.tryParse(e.attributes['filepos'] ?? ''))
          .whereType<int>()
          .where((offset) => offset >= 0 && offset <= content.length)
          .toSet()
          .toList()
        ..sort();
  if (links.isNotEmpty) {
    final out = StringBuffer();
    var previous = 0;
    for (final offset in links) {
      out.write(decode(content.sublist(previous, offset)));
      out.write('<a id="filepos-$offset"></a>');
      previous = offset;
    }
    out.write(decode(content.sublist(previous)));
    markup = out.toString();
  }
  final document = html.parse(markup);
  for (final link in document.querySelectorAll('a[filepos]')) {
    link.attributes['href'] =
        '#filepos-${int.tryParse(link.attributes['filepos'] ?? '') ?? 0}';
  }
  final resources = <String, Uint8List>{};
  for (final image in document.querySelectorAll('img[recindex]')) {
    final index = int.tryParse(image.attributes['recindex'] ?? '');
    if (index != null && index > 0 && firstImage < count) {
      final record = firstImage + index - 1;
      if (record < count) {
        final path = 'images/$index';
        resources[path] = bytes.sublist(offsets[record], offsets[record + 1]);
        image.attributes['src'] = path;
      }
    }
  }
  for (final script in document.querySelectorAll(
    'script,iframe,object,embed',
  )) {
    script.remove();
  }
  return EpubDocumentData(title, [
    EpubSection('book.html', title, document.outerHtml),
  ], resources);
}

Uint8List decodePalmDoc(List<int> record) {
  final out = <int>[];
  for (var i = 0; i < record.length; i++) {
    final b = record[i];
    if (b >= 1 && b <= 8) {
      if (i + b >= record.length) {
        throw const FormatException('Truncated PalmDOC literal.');
      }
      out.addAll(record.sublist(i + 1, i + 1 + b));
      i += b;
    } else if (b <= 127) {
      out.add(b);
    } else if (b >= 192) {
      out.addAll([32, b ^ 128]);
    } else {
      if (++i >= record.length) {
        throw const FormatException('Truncated PalmDOC reference.');
      }
      final pair = (b << 8) | record[i], distance = (pair >> 3) & 2047;
      final length = (pair & 7) + 3;
      if (distance == 0 || distance > out.length) {
        throw const FormatException('Invalid PalmDOC reference.');
      }
      for (var n = 0; n < length; n++) {
        out.add(out[out.length - distance]);
      }
    }
    if (out.length > 65536) {
      throw const FormatException('MOBI record is too large.');
    }
  }
  return Uint8List.fromList(out);
}
