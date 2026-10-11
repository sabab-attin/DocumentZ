import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/book.dart';

bool get supportsLocalConversion => Platform.isWindows;
String conversionTool(BookFormat format) => format == BookFormat.mobi ? 'Calibre'
  : [BookFormat.eps, BookFormat.ps].contains(format) ? 'Ghostscript' : 'LibreOffice';

Future<String?> _findTool(BookFormat format) async {
  final programFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
  final programFiles86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
  final tool = conversionTool(format);
  final saved = (await SharedPreferences.getInstance()).getString('converter.$tool');
  if (saved != null && await File(saved).exists()) return saved;
  final names = tool == 'Calibre' ? ['ebook-convert.exe'] : tool == 'Ghostscript' ? ['gswin64c.exe', 'gswin32c.exe'] : ['soffice.exe'];
  final candidates = <String>[];
  for (final base in [programFiles, programFiles86]) {
    if (tool == 'LibreOffice') candidates.add(p.join(base, 'LibreOffice', 'program', names.first));
    if (tool == 'Calibre') candidates.add(p.join(base, 'Calibre2', names.first));
    if (tool == 'Ghostscript') {
      final directory = Directory(p.join(base, 'gs'));
      if (await directory.exists()) {
        final versions = await directory.list().where((entry) => entry is Directory).toList();
        versions.sort((a, b) => b.path.compareTo(a.path));
        for (final version in versions) { for (final name in names) { candidates.add(p.join(version.path, 'bin', name)); } }
      }
    }
  }
  for (final directory in (Platform.environment['PATH'] ?? '').split(';')) {
    for (final name in names) { candidates.add(p.join(directory.replaceAll('"', ''), name)); }
  }
  for (final file in candidates) { if (await File(file).exists()) return file; }
  return null;
}

Future<Uint8List> convertDocumentToPdf(Uint8List bytes, BookFormat format, {String? executable}) async {
  if (!supportsLocalConversion) throw const FormatException('Convert to PDF in the Windows app, then share that PDF to this device.');
  final tool = conversionTool(format);
  final binary = executable ?? await _findTool(format);
  if (binary == null || !await File(binary).exists()) throw FormatException('$tool is not installed or could not be found. Install it on Windows or choose its executable.');
  final allowed = tool == 'Calibre' ? {'ebook-convert.exe'} : tool == 'Ghostscript' ? {'gswin64c.exe', 'gswin32c.exe'} : {'soffice.exe'};
  if (!allowed.contains(p.basename(binary).toLowerCase())) throw FormatException('Choose ${allowed.join(' or ')} for $tool conversion.');
  if (executable != null) await (await SharedPreferences.getInstance()).setString('converter.$tool', binary);
  final temp = await Directory(p.join((await getTemporaryDirectory()).path, 'documentz-convert')).create(recursive: true);
  final job = await temp.createTemp('job-');
  try {
    final source = File(p.join(job.path, 'source.${format.name}'));
    final output = File(p.join(job.path, 'source.pdf'));
    await source.writeAsBytes(bytes, flush: true);
    final args = tool == 'Calibre' ? [source.path, output.path]
      : tool == 'Ghostscript' ? ['-dSAFER', '-dBATCH', '-dNOPAUSE', '-sDEVICE=pdfwrite', if (format == BookFormat.eps) '-dEPSCrop', '-sOutputFile=${output.path}', source.path]
      : ['-env:UserInstallation=${Directory(p.join(job.path, 'profile')).uri}', '--headless', '--convert-to', 'pdf', '--outdir', job.path, source.path];
    final process = await Process.start(binary, args, runInShell: false, workingDirectory: job.path);
    // Drain both pipes without storing unbounded converter diagnostics.
    Future<void> drain(Stream<List<int>> stream) async { await for (final _ in stream) {} }
    final streams = Future.wait([drain(process.stdout), drain(process.stderr)]);
    int code;
    try { code = await process.exitCode.timeout(const Duration(minutes: 3)); }
    on TimeoutException { process.kill(); throw const FormatException('Conversion took too long. Try a smaller document.'); }
    await streams;
    if (code != 0 || !await output.exists()) throw FormatException('$tool could not convert this document. Check that it is not damaged, encrypted, or DRM-protected.');
    if (await output.length() > 100 * 1024 * 1024) throw const FormatException('The converted PDF is larger than 100 MB.');
    final result = await output.readAsBytes();
    if (!latin1.decode(result.take(1024).toList()).contains('%PDF-')) throw const FormatException('The converter did not produce a valid PDF.');
    return result;
  } finally {
    // This is only the unique temporary job directory created above.
    try { await job.delete(recursive: true); } catch (_) { /* A converter may still be releasing files. */ }
  }
}
