import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:html/parser.dart' as html;
import 'package:markdown/markdown.dart' as md;
import '../domain/book.dart';
import 'epub_document.dart';

String escapeMarkup(String value) => const HtmlEscape().convert(value);
Iterable<XmlElement> elements(XmlNode node, String name) => node.descendants.whereType<XmlElement>().where((e) => e.name.local == name);
String? attribute(XmlElement node, String name) {
  for (final attr in node.attributes) { if (attr.name.local == name) return attr.value; }
  return null;
}
String? relationshipId(XmlElement node) {
  for (final attr in node.attributes) {
    if (attr.name.local == 'id' && attr.name.prefix == 'r') return attr.value;
  }
  return attribute(node, 'id');
}
String decodeDocumentText(Uint8List bytes) {
  if (bytes.length >= 2 && ((bytes[0] == 255 && bytes[1] == 254) || (bytes[0] == 254 && bytes[1] == 255))) {
    final little = bytes[0] == 255;
    return String.fromCharCodes([for (int i = 2; i + 1 < bytes.length; i += 2)
      little ? bytes[i] | bytes[i + 1] << 8 : bytes[i] << 8 | bytes[i + 1]]);
  }
  try { return utf8.decode(bytes).replaceFirst(RegExp('^\uFEFF'), ''); }
  catch (_) { return latin1.decode(bytes); }
}

Map<String, Uint8List> documentArchive(Uint8List bytes) {
  final files = <String, Uint8List>{};
  int total = 0;
  final archive = ZipDecoder().decodeBytes(bytes);
  if (archive.length > 10000) throw const FormatException('This document has too many archive entries.');
  for (final file in archive) {
    if (!file.isFile) continue;
    total += file.size;
    if (total > 200 * 1024 * 1024) throw const FormatException('The expanded document is too large.');
    files[file.name] = Uint8List.fromList(file.content);
  }
  return files;
}
Map<String, String> relationships(Map<String, Uint8List> files, String part) {
  final slash = part.lastIndexOf('/');
  final path = '${part.substring(0, slash + 1)}_rels/${part.substring(slash + 1)}.rels';
  final bytes = files[path];
  if (bytes == null) return {};
  return {for (final rel in elements(XmlDocument.parse(decodeDocumentText(bytes)), 'Relationship'))
    if (attribute(rel, 'TargetMode') != 'External') attribute(rel, 'Id')!: attribute(rel, 'Target')!};
}

EpubDocumentData parseReadableDocument((BookFormat, Uint8List) input) {
  final (format, bytes) = input;
  final sections = <EpubSection>[];
  final resources = <String, Uint8List>{};
  void section(String path, String title, String markup) => sections.add(EpubSection(path, title, markup));
  if ([BookFormat.txt, BookFormat.markdown, BookFormat.rtf, BookFormat.html, BookFormat.htm, BookFormat.mhtml].contains(format)) {
    final text = decodeDocumentText(bytes);
    final markup = switch (format) {
      BookFormat.markdown => md.markdownToHtml(text, extensionSet: md.ExtensionSet.gitHubFlavored),
      BookFormat.txt => '<pre>${escapeMarkup(text)}</pre>',
      BookFormat.rtf => '<pre>${escapeMarkup(rtfText(text))}</pre>',
      BookFormat.mhtml => mhtmlMarkup(latin1.decode(bytes), resources),
      _ => text,
    };
    final document = html.parse(markup);
    for (final element in document.querySelectorAll('script,iframe,object,embed')) { element.remove(); }
    for (final image in document.querySelectorAll('img')) {
      final src = image.attributes['src'] ?? '';
      if (src.startsWith('data:image/')) {
        try {
          final data = UriData.parse(src).contentAsBytes();
          final path = 'embedded-${resources.length}';
          resources[path] = Uint8List.fromList(data);
          image.attributes['src'] = path;
        } catch (_) { image.attributes.remove('src'); }
      }
    }
    section('index.html', 'Document', document.body?.innerHtml ?? markup);
  } else {
    resources.addAll(documentArchive(bytes));
    XmlDocument xml(String path) {
      final data = resources[path];
      if (data == null) throw FormatException('Missing document part: $path');
      return XmlDocument.parse(decodeDocumentText(data));
    }
    if (format == BookFormat.docx) {
      const path = 'word/document.xml';
      final rels = relationships(resources, path);
      String paragraph(XmlElement p) {
        final out = StringBuffer();
        for (final run in elements(p, 'r')) {
          var text = elements(run, 't').map((e) => escapeMarkup(e.innerText)).join();
          if (elements(run, 'tab').isNotEmpty) text += ' &emsp; ';
          if (elements(run, 'br').isNotEmpty) text += '<br/>';
          bool enabled(String tag) => elements(run, tag).any((e) => !['0', 'false', 'none'].contains(attribute(e, 'val')));
          if (enabled('b')) text = '<b>$text</b>';
          if (enabled('i')) text = '<i>$text</i>';
          if (enabled('u')) text = '<u>$text</u>';
          if (enabled('strike')) text = '<s>$text</s>';
          out.write(text);
          for (final image in elements(run, 'blip')) {
            final target = rels[attribute(image, 'embed')];
            if (target != null) out.write('<img src="${escapeMarkup(target)}"/>');
          }
        }
        final heading = elements(p, 'pStyle').map((e) => attribute(e, 'val') ?? '').any((s) => s.toLowerCase().startsWith('heading'));
        return '<${heading ? 'h2' : 'p'}>${out.isEmpty ? '<br/>' : out.toString()}</${heading ? 'h2' : 'p'}>';
      }
      final body = elements(xml(path), 'body').first;
      final out = StringBuffer();
      for (final child in body.childElements) {
        if (child.name.local == 'p') out.write(paragraph(child));
        if (child.name.local == 'tbl') {
          out.write('<table border="1">');
          for (final row in child.childElements.where((e) => e.name.local == 'tr')) {
            out.write('<tr>');
            for (final cell in row.childElements.where((e) => e.name.local == 'tc')) {
              out.write('<td>${elements(cell, 'p').map(paragraph).join()}</td>');
            }
            out.write('</tr>');
          }
          out.write('</table>');
        }
      }
      section(path, 'Document', out.toString());
    } else if (format == BookFormat.xlsx) {
      final shared = resources.containsKey('xl/sharedStrings.xml')
        ? elements(xml('xl/sharedStrings.xml'), 'si').map((e) => elements(e, 't').map((t) => t.innerText).join()).toList() : <String>[];
      final rels = relationships(resources, 'xl/workbook.xml');
      for (final sheet in elements(xml('xl/workbook.xml'), 'sheet')) {
        final target = rels[relationshipId(sheet)];
        if (target == null) continue;
        final path = epubResourcePath('xl/workbook.xml', target).replaceFirst(RegExp('^/'), '');
        final out = StringBuffer('<table border="1">');
        int count = 0;
        for (final row in elements(xml(path), 'row')) {
          out.write('<tr><th>${escapeMarkup(attribute(row, 'r') ?? '')}</th>');
          int column = 0;
          for (final cell in row.childElements.where((e) => e.name.local == 'c')) {
            final address = attribute(cell, 'r') ?? '';
            int targetColumn = 0;
            for (final letter in RegExp('[A-Z]+').stringMatch(address)?.codeUnits ?? <int>[]) { targetColumn = targetColumn * 26 + letter - 64; }
            if (targetColumn > 512) throw const FormatException('Use Windows PDF conversion for very wide spreadsheets.');
            while (column + 1 < targetColumn) { out.write('<td></td>'); column++; }
            column++;
            if (++count > 100000) throw const FormatException('Use Windows PDF conversion for large spreadsheets.');
            final values = elements(cell, 'v');
            var text = values.isEmpty ? elements(cell, 't').map((e) => e.innerText).join() : values.first.innerText;
            if (attribute(cell, 't') == 's') {
              final index = int.tryParse(text);
              text = index != null && index >= 0 && index < shared.length ? shared[index] : '';
            }
            if (text.isEmpty && elements(cell, 'f').isNotEmpty) text = '=${elements(cell, 'f').first.innerText}';
            out.write('<td>${escapeMarkup(text)}</td>');
          }
          out.write('</tr>');
        }
        section(path, attribute(sheet, 'name') ?? 'Sheet', '$out</table>');
      }
    } else if (format == BookFormat.pptx) {
      final rels = relationships(resources, 'ppt/presentation.xml');
      for (final slide in elements(xml('ppt/presentation.xml'), 'sldId')) {
        final target = rels[relationshipId(slide)];
        if (target == null) continue;
        final path = epubResourcePath('ppt/presentation.xml', target).replaceFirst(RegExp('^/'), '');
        final page = xml(path);
        final markup = elements(page, 'p').map((e) => '<p>${elements(e, 't').map((e) => escapeMarkup(e.innerText)).join()}</p>').join();
        final images = relationships(resources, path);
        final artwork = elements(page, 'blip').map((e) => images[attribute(e, 'embed')]).whereType<String>()
          .map((src) => '<img src="${escapeMarkup(src)}"/>').join();
        section(path, 'Slide ${sections.length + 1}', '$markup$artwork');
      }
    } else {
      final content = xml('content.xml');
      String markup(XmlElement node) {
        final tag = node.name.local;
        if (tag == 'image') return '<img src="${escapeMarkup(attribute(node, 'href') ?? '')}"/>';
        if (tag == 's') return ' ';
        if (tag == 'line-break') return '<br/>';
        if (tag == 'tab') return ' &emsp; ';
        final inner = node.children.map((child) => child is XmlElement ? markup(child)
          : child is XmlText ? escapeMarkup(child.value) : child is XmlCDATA ? escapeMarkup(child.value) : '').join();
        final rendered = switch (tag) {
          'p' => '<p>$inner</p>', 'h' => '<h2>$inner</h2>', 'table' => '<table border="1">$inner</table>',
          'table-row' => '<tr>$inner</tr>', 'table-cell' || 'covered-table-cell' => '<td>$inner</td>', _ => inner,
        };
        final repeated = int.tryParse(attribute(node, tag == 'table-row' ? 'number-rows-repeated' : 'number-columns-repeated') ?? '1') ?? 1;
        if ((tag == 'table-row' || tag == 'table-cell') && repeated > 1) {
          if (repeated > 512 && node.innerText.trim().isEmpty) return '';
          if (repeated > 512) throw const FormatException('Use Windows PDF conversion for large repeated spreadsheet ranges.');
          return List.filled(repeated, rendered).join();
        }
        return rendered;
      }
      if (format == BookFormat.ods) {
        for (final table in elements(content, 'table')) {
          section('sheet-${sections.length + 1}.html', attribute(table, 'name') ?? 'Sheet ${sections.length + 1}', markup(table));
        }
      } else if (format == BookFormat.odp) {
        for (final page in elements(content, 'page')) {
          section('slide-${sections.length + 1}.html', attribute(page, 'name') ?? 'Slide ${sections.length + 1}', markup(page));
        }
      } else { section('content.xml', 'Document', markup(elements(content, 'text').first)); }
    }
  }
  if (sections.isEmpty) throw const FormatException('No readable document content was found. Try Windows PDF conversion.');
  return EpubDocumentData('Document', sections, resources);
}

/// Read RTF text, honoring skipped destinations, Unicode fallback counts,
/// escaped braces and paragraph breaks. Original font/layout is not recreated.
String rtfText(String source) {
  if (!source.startsWith(r'{\rtf')) throw const FormatException('Invalid RTF document.');
  final out = StringBuffer();
  final stack = <(bool, int)>[];
  bool skip = false;
  int unicodeFallback = 1, fallback = 0;
  for (int i = 0; i < source.length;) {
    final char = source[i++];
    if (char == '{') { stack.add((skip, unicodeFallback)); continue; }
    if (char == '}') { if (stack.isNotEmpty) { final state = stack.removeLast(); skip = state.$1; unicodeFallback = state.$2; } continue; }
    if (char != r'\') {
      if (fallback > 0) { fallback--; } else if (!skip && char != '\r' && char != '\n') { out.write(char); }
      continue;
    }
    if (i >= source.length) break;
    final next = source[i];
    if (next == '*' ) { skip = true; i++; continue; }
    if (next == "'" && i + 2 < source.length) {
      final code = int.tryParse(source.substring(i + 1, i + 3), radix: 16);
      if (fallback > 0) { fallback--; } else if (!skip && code != null) { out.writeCharCode(code); }
      i += 3; continue;
    }
    if (!RegExp('[a-zA-Z]').hasMatch(next)) {
      if (fallback > 0) { fallback--; } else if (!skip) { out.write(next == '~' ? ' ' : next); }
      i++; continue;
    }
    final match = RegExp(r'([a-zA-Z]+)(-?\d+)? ?').matchAsPrefix(source, i)!;
    i = match.end;
    final word = match.group(1)!, number = int.tryParse(match.group(2) ?? '');
    if (['fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'object', 'fldinst'].contains(word)) skip = true;
    if (word == 'uc' && number != null) unicodeFallback = number.clamp(0, 10);
    if (skip) continue;
    if (word == 'u' && number != null) { out.writeCharCode(number & 0xffff); fallback = unicodeFallback; }
    else if (word == 'par' || word == 'line') { out.write('\n'); }
    else if (word == 'tab') { out.write('\t'); }
    else if (word == 'emdash') { out.write('—'); }
    else if (word == 'endash') { out.write('–'); }
  }
  return out.toString();
}

String mhtmlMarkup(String source, Map<String, Uint8List> resources) {
  final boundary = RegExp(r'''boundary\s*=\s*(?:"([^"]+)"|([^\s;]+))''', caseSensitive: false).firstMatch(source);
  if (boundary == null) throw const FormatException('Missing MHTML multipart boundary.');
  final locations = <String, String>{};
  String? page;
  String base = '';
  for (final part in source.split('--${boundary.group(1) ?? boundary.group(2)}').skip(1)) {
    final divider = RegExp(r'\r?\n\r?\n').firstMatch(part);
    if (divider == null) continue;
    final headers = part.substring(0, divider.start).replaceAll(RegExp(r'\r?\n[ \t]+'), ' ');
    String header(String name) => RegExp('$name:([^\r\n]+)', caseSensitive: false).firstMatch(headers)?.group(1)?.trim() ?? '';
    final body = part.substring(divider.end).trimRight();
    final encoding = header('Content-Transfer-Encoding').toLowerCase();
    List<int> bytes;
    if (encoding == 'base64') { bytes = base64.decode(body.replaceAll(RegExp(r'\s'), '')); }
    else if (encoding == 'quoted-printable') {
      final unfolded = body.replaceAll(RegExp(r'=\r?\n'), '');
      bytes = [];
      for (int i = 0; i < unfolded.length; i++) {
        final hex = unfolded[i] == '=' && i + 2 < unfolded.length ? int.tryParse(unfolded.substring(i + 1, i + 3), radix: 16) : null;
        if (hex != null) { bytes.add(hex); i += 2; } else { bytes.add(unfolded.codeUnitAt(i) & 255); }
      }
    } else { bytes = latin1.encode(body); }
    final location = header('Content-Location');
    if (header('Content-Type').toLowerCase().startsWith('text/html') && page == null) {
      page = decodeDocumentText(Uint8List.fromList(bytes)); base = location;
    } else if (header('Content-Type').toLowerCase().startsWith('image/')) {
      final key = 'mhtml-${resources.length}'; resources[key] = Uint8List.fromList(bytes);
      locations[location] = key;
      locations['cid:${header('Content-ID').replaceAll(RegExp('[<>]'), '')}'] = key;
    }
  }
  if (page == null) throw const FormatException('No HTML page in this MHTML file.');
  final document = html.parse(page);
  for (final image in document.querySelectorAll('img')) {
    final src = image.attributes['src'] ?? '';
    final key = locations[src] ?? locations[Uri.tryParse(base)?.resolve(src).toString()];
    if (key != null) image.attributes['src'] = key;
  }
  return document.body?.innerHtml ?? page;
}
