import 'dart:math' show max, min;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/pdf_compression.dart';
import '../domain/services.dart';
import 'edit.dart' show PdfResultScreen;

enum PdfCompressionMode {
  preserve(
    'Preserve content',
    'Lossless optimization. Keeps selectable text, forms, links and bookmarks.',
  ),
  balanced(
    'Balanced image copy',
    '150 DPI, JPEG quality 82. Often useful for scans.',
  ),
  small(
    'Smaller image copy',
    '100 DPI, JPEG quality 65. Smaller pages with lower image detail.',
  );

  const PdfCompressionMode(this.label, this.description);
  final String label, description;
}

String compressionFileSize(int bytes) => bytes < 1000000
    ? '${(bytes / 1000).toStringAsFixed(1)} KB'
    : '${(bytes / 1000000).toStringAsFixed(2)} MB';

class PdfCompressionScreen extends StatefulWidget {
  const PdfCompressionScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.repository,
    required this.onSaved,
  });
  final Uint8List bytes;
  final String title;
  final ImportableLibrary repository;
  final VoidCallback onSaved;
  @override
  State<PdfCompressionScreen> createState() => _PdfCompressionScreenState();
}

class _PdfCompressionScreenState extends State<PdfCompressionScreen> {
  PdfCompressionMode mode = PdfCompressionMode.preserve;
  bool busy = false, acknowledged = false, cancelled = false;
  double? progress;
  String status = '';
  int generation = 0;
  void _check(int token) {
    if (!mounted || cancelled || token != generation) {
      throw const _CompressionCancelled();
    }
  }

  Future<void> _compress() async {
    if (busy || (mode != PdfCompressionMode.preserve && !acknowledged)) {
      return;
    }
    final chosen = mode, token = ++generation;
    setState(() {
      busy = true;
      cancelled = false;
      progress = null;
      status = 'Optimizing PDF…';
    });
    try {
      if (chosen != PdfCompressionMode.preserve) {
        await validatePdfCompressionInput(widget.bytes);
      }
      _check(token);
      PdfCompressionResult result;
      if (chosen == PdfCompressionMode.preserve) {
        result = await optimizePdf(widget.bytes);
        _check(token);
      } else {
        await pdfrxFlutterInitialize();
        _check(token);
        final source = await PdfDocument.openData(
          widget.bytes,
          passwordProvider: () => null,
        );
        try {
          if (source.isEncrypted) {
            throw const FormatException(
              'Protected PDFs are kept unchanged. Use an unlocked copy.',
            );
          }
          if (source.pages.isEmpty) {
            throw const FormatException('This PDF has no pages.');
          }
          final pages = <CompressedPdfPage>[];
          final dpi = chosen == PdfCompressionMode.balanced ? 150.0 : 100.0;
          final quality = chosen == PdfCompressionMode.balanced ? 82 : 65;
          for (var index = 0; index < source.pages.length; index++) {
            _check(token);
            setState(() {
              status =
                  'Compressing page ${index + 1} of ${source.pages.length}…';
              progress = index / source.pages.length;
            });
            final page = source.pages[index];
            if (page.width <= 0 || page.height <= 0) {
              throw const FormatException('Invalid PDF page dimensions.');
            }
            final fullWidth = page.width * dpi / 72,
                fullHeight = page.height * dpi / 72;
            final scale = min(1.0, 4096 / max(fullWidth, fullHeight));
            final raster = await page.render(
              fullWidth: fullWidth * scale,
              fullHeight: fullHeight * scale,
              backgroundColor: 0xffffffff,
            );
            if (raster == null) {
              throw const FormatException(
                'Could not render a page. Original unchanged.',
              );
            }
            try {
              final picture = await raster.createImage();
              try {
                final data = await picture.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                if (data == null) {
                  throw const FormatException(
                    'Could not render a page. Original unchanged.',
                  );
                }
                _check(token);
                final jpeg = await compressPageImage(
                  data.buffer.asUint8List(
                    data.offsetInBytes,
                    data.lengthInBytes,
                  ),
                  quality,
                );
                _check(token);
                pages.add(CompressedPdfPage(jpeg, page.width, page.height));
              } finally {
                picture.dispose();
              }
            } finally {
              raster.dispose();
            }
          }
          setState(() {
            progress = null;
            status = 'Assembling compressed PDF…';
          });
          result = await assembleImagePdf(pages);
          _check(token);
        } finally {
          await source.dispose();
        }
      }
      if (result.bytes.length >= widget.bytes.length) {
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (dialog) => AlertDialog(
              title: const Text('No size reduction'),
              content: const Text(
                'This PDF is already as small or smaller with these settings. The original was kept unchanged. Try another compression option.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialog),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
        return;
      }
      _check(token);
      final saving = (100 * (1 - result.bytes.length / widget.bytes.length))
          .toStringAsFixed(1);
      final summary =
          '${compressionFileSize(widget.bytes.length)} → ${compressionFileSize(result.bytes.length)} · $saving% smaller. '
          '${result.imageOnly ? 'Image-only copy: selectable text, forms, links and bookmarks are not retained. ' : 'Lossless optimization. '}'
          'The original and its DocumentZ annotations remain unchanged. App annotations are not embedded in this copy.';
      setState(() {
        busy = false;
        status = '';
        progress = null;
      });
      var saved = false;
      if (!mounted) {
        return;
      }
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => PdfResultScreen(
            bytes: result.bytes,
            name: '${widget.title} - compressed',
            repository: widget.repository,
            onSaved: () {
              saved = true;
              widget.onSaved();
            },
            message: summary,
          ),
        ),
      );
      if (saved && mounted) {
        Navigator.pop(context);
      }
    } on _CompressionCancelled {
      // Processing results are discarded; the original is never overwritten.
    } catch (error) {
      if (mounted && !cancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message.toString() : 'Could not compress this PDF. It may be protected or damaged. The original is unchanged.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          progress = null;
          status = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope<void>(
    canPop: !busy || cancelled,
    child: Scaffold(
      appBar: AppBar(title: const Text('Compress PDF')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Original size: ${compressionFileSize(widget.bytes.length)}',
              ),
              const SizedBox(height: 20),
              for (final option in PdfCompressionMode.values)
                Card(
                  child: ListTile(
                    leading: Icon(
                      option == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                    ),
                    title: Text(option.label),
                    subtitle: Text(option.description),
                    onTap: busy
                        ? null
                        : () => setState(() {
                            mode = option;
                            acknowledged = false;
                          }),
                  ),
                ),
              if (mode != PdfCompressionMode.preserve)
                CheckboxListTile(
                  value: acknowledged,
                  onChanged: busy
                      ? null
                      : (value) =>
                            setState(() => acknowledged = value ?? false),
                  title: const Text('Create an image-only copy'),
                  subtitle: const Text(
                    'Selectable text, forms, links, embedded notes and bookmarks will not be retained. Page images are recompressed with some quality loss.',
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Original files are never replaced. Signed and protected PDFs are kept unchanged. Compression savings depend on the document.',
              ),
              const SizedBox(height: 20),
              if (busy) ...[
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text(status),
                TextButton.icon(
                  onPressed: cancelled
                      ? null
                      : () => setState(() {
                          cancelled = true;
                          generation++;
                          status = 'Cancelling… You can go back safely.';
                        }),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ] else
                FilledButton.icon(
                  onPressed:
                      mode != PdfCompressionMode.preserve && !acknowledged
                      ? null
                      : _compress,
                  icon: const Icon(Icons.compress),
                  label: const Text('Compress and preview'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CompressionCancelled implements Exception {
  const _CompressionCancelled();
}
