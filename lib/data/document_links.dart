import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import 'epub_document.dart';

Uri normalizeDocumentUrl(Uri uri) =>
    uri.scheme.isEmpty && uri.hasAuthority ? uri.replace(scheme: 'https') : uri;
bool isExternalDocumentUrl(Uri uri) => const [
  'https',
  'http',
  'mailto',
  'tel',
].contains(normalizeDocumentUrl(uri).scheme.toLowerCase());

Future<bool> openDocumentUrl(Uri uri) async {
  if (!isExternalDocumentUrl(uri)) {
    return false;
  }
  try {
    return await launchUrl(
      normalizeDocumentUrl(uri),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

Future<bool> followPdfLink(
  PdfLink link, {
  required Future<bool> Function(PdfDest) goToDestination,
  Future<bool> Function(Uri) openExternal = openDocumentUrl,
}) async {
  try {
    if (link.dest != null) {
      return await goToDestination(link.dest!);
    }
    final url = link.url;
    if (url == null) {
      return false;
    }
    if (url.scheme.isEmpty && url.path.isEmpty && url.hasFragment) {
      final number = int.tryParse(
        Uri.splitQueryString(url.fragment)['page'] ?? '',
      );
      if (number != null && number > 0) {
        return await goToDestination(PdfDest(number, PdfDestCommand.fit, null));
      }
    }
    return isExternalDocumentUrl(url) &&
        await openExternal(normalizeDocumentUrl(url));
  } catch (_) {
    return false;
  }
}

({int section, String fragment})? resolveEbookLink(
  EpubDocumentData book,
  String base,
  String reference,
) {
  try {
    final uri = Uri.parse(reference.trim());
    if (uri.hasScheme || uri.hasAuthority) {
      return null;
    }
    final path = epubResourcePath(base, reference);
    var section = book.sections.indexWhere((s) => s.path == path);
    if (section < 0) {
      final matches = book.sections.indexed
          .where((s) => s.$2.path.toLowerCase() == path.toLowerCase())
          .toList();
      if (matches.length == 1) {
        section = matches.single.$1;
      }
    }
    if (section < 0) {
      return null;
    }
    return (section: section, fragment: Uri.decodeComponent(uri.fragment));
  } on FormatException {
    return null;
  }
}
