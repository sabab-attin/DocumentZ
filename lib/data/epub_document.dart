import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class EpubSection {
  const EpubSection(this.path, this.title, this.html);
  final String path;
  final String title;
  final String html;
}

class EpubDocumentData {
  const EpubDocumentData(
    this.title,
    this.sections,
    this.resources, {
    this.coverPath,
  });
  final String title;
  final List<EpubSection> sections;
  final Map<String, Uint8List> resources;
  final String? coverPath;
}

String epubResourcePath(String base, String reference) {
  reference = reference.trim().replaceAll('\\', '/');
  base = base.replaceAll('\\', '/');
  final uri = Uri.parse(reference);
  if (uri.hasScheme || uri.hasAuthority) return '';
  return Uri.decodeComponent(Uri(path: base).resolve(reference).path)
      .replaceFirst(RegExp('^/'), '');
}

String _archivePath(String path) {
  final parts = <String>[];
  for (final part in path.replaceAll('\\', '/').split('/')) {
    if (part.isEmpty || part == '.') continue;
    if (part == '..') {
      if (parts.isNotEmpty) parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

({String path, Uint8List bytes})? epubImageResource(
  EpubDocumentData book,
  String base,
  String reference,
) {
  try {
    reference = reference.trim();
    if (reference.toLowerCase().startsWith('data:image/')) {
      final data = UriData.parse(reference);
      return (
        path: data.mimeType == 'image/svg+xml' ? 'embedded.svg' : 'embedded',
        bytes: data.contentAsBytes(),
      );
    }
    final path = epubResourcePath(base, reference);
    if (path.isEmpty) return null; // Remote images stay offline.
    final bytes = book.resources[path];
    if (bytes != null) return (path: path, bytes: bytes);
    // Some exporters vary ZIP filename case. Accept only an unambiguous match.
    final matches = book.resources.keys
        .where((key) => key.toLowerCase() == path.toLowerCase())
        .toList();
    if (matches.length == 1) {
      return (path: matches.single, bytes: book.resources[matches.single]!);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Give flutter_svg self-contained artwork instead of unresolved ZIP references.
String epubSvgMarkup(EpubDocumentData book, String base, String markup) {
  final xml = XmlDocument.parse(
    markup
        .replaceAll('viewbox=', 'viewBox=')
        .replaceAll('preserveaspectratio=', 'preserveAspectRatio='),
  );
  for (final image in _elements(xml, 'image')) {
    final href = image.attributes
        .where((a) => a.name.local == 'href')
        .firstOrNull
        ?.value;
    if (href == null) continue;
    final resource = epubImageResource(book, base, href);
    if (resource == null) continue;
    final extension = resource.path.split('.').last.toLowerCase();
    final mime = switch (extension) {
      'svg' => 'image/svg+xml',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      _ => 'image/png',
    };
    image.attributes.removeWhere((a) => a.name.local == 'href');
    image.setAttribute(
      'href',
      'data:$mime;base64,${base64Encode(resource.bytes)}',
    );
  }
  return xml.toXmlString();
}

Iterable<XmlElement> _elements(XmlNode node, String name) => node.descendants
    .whereType<XmlElement>()
    .where((element) => element.name.local == name);

/// EPUB 2/3 package-container and spine parsing, independent of PDF image APIs.
EpubDocumentData parseEpub(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final resources = <String, Uint8List>{};
  int total = 0;
  for (final file in archive) {
    if (!file.isFile) continue;
    total += file.size;
    if (total > 200 * 1024 * 1024) {
      throw const FormatException('EPUB contents are too large.');
    }
    resources[_archivePath(file.name)] = Uint8List.fromList(file.content);
  }
  String content(String path) {
    final data = resources[path];
    if (data == null) throw FormatException('Missing EPUB resource: $path');
    return utf8.decode(data);
  }

  final container = XmlDocument.parse(content('META-INF/container.xml'));
  final rootfiles = _elements(container, 'rootfile');
  if (rootfiles.isEmpty) throw const FormatException('Missing EPUB package.');
  final packagePath = rootfiles.first.getAttribute('full-path');
  if (packagePath == null) {
    throw const FormatException('Missing EPUB package path.');
  }
  final package = XmlDocument.parse(content(packagePath));
  final titles = _elements(package, 'title');
  final title = titles.isEmpty
      ? 'EPUB document'
      : titles.first.innerText.trim();
  final manifest = <String, String>{};
  String? coverId;
  String? coverPath;
  for (final meta in _elements(package, 'meta')) {
    if (meta.getAttribute('name') == 'cover') {
      coverId = meta.getAttribute('content');
    }
  }
  for (final item in _elements(package, 'item')) {
    final id = item.getAttribute('id');
    final href = item.getAttribute('href');
    if (id != null && href != null) {
      manifest[id] = epubResourcePath(packagePath, href);
      if ((item.getAttribute('properties') ?? '')
              .split(RegExp(r'\s+'))
              .contains('cover-image') ||
          id == coverId) {
        coverPath = manifest[id];
      }
    }
  }
  final sections = <EpubSection>[];
  for (final reference in _elements(package, 'itemref')) {
    if (reference.getAttribute('linear') == 'no') continue;
    final path = manifest[reference.getAttribute('idref')];
    if (path == null) {
      throw const FormatException('Missing EPUB chapter reference.');
    }
    final html = content(path);
    String heading = 'Section ${sections.length + 1}';
    try {
      final chapter = XmlDocument.parse(html);
      final headings = _elements(chapter, 'h1').toList();
      final chapterTitles = _elements(chapter, 'title').toList();
      if (headings.isNotEmpty) {
        heading = headings.first.innerText.trim();
      } else if (chapterTitles.isNotEmpty) {
        heading = chapterTitles.first.innerText.trim();
      }
    } catch (_) {
      /* HTML renderer tolerates markup that is not strict XML. */
    }
    sections.add(EpubSection(path, heading, html));
  }
  if (sections.isEmpty) {
    throw const FormatException('EPUB contains no reading sections.');
  }
  return EpubDocumentData(title, sections, resources, coverPath: coverPath);
}
