import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/pdf_compression_choices.dart';
import '../domain/services.dart';
import 'edit.dart' show PdfResultScreen;
export '../data/pdf_compression_choices.dart'
    show PdfCompressionMode, PdfCompressionChoice;

String compressionFileSize(int bytes) => bytes < 1000000
    ? '${(bytes / 1000).toStringAsFixed(1)} KB'
    : '${(bytes / 1000000).toStringAsFixed(2)} MB';

typedef CompressionMeasure = Future<List<PdfCompressionChoice>> Function(
  Uint8List input, {
  required bool Function() cancelled,
  required void Function(double) onProgress,
});

class PdfCompressionScreen extends StatefulWidget {
  const PdfCompressionScreen({
    super.key,
    required this.bytes,
    required this.title,
    required this.repository,
    required this.onSaved,
    this.measure = measurePdfCompression,
  });
  final Uint8List bytes;
  final String title;
  final ImportableLibrary repository;
  final VoidCallback onSaved;
  final CompressionMeasure measure;
  @override
  State<PdfCompressionScreen> createState() => _PdfCompressionScreenState();
}

class _PdfCompressionScreenState extends State<PdfCompressionScreen> {
  List<PdfCompressionChoice> choices = [];
  PdfCompressionChoice? selected;
  bool loading = true;
  double progress = 0;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _measure();
      }
    });
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  Future<void> _measure() async {
    final token = ++generation;
    setState(() {
      loading = true;
      error = null;
      progress = 0;
    });
    try {
      final result = await widget.measure(
        widget.bytes,
        cancelled: () => !mounted || token != generation,
        onProgress: (value) {
          if (mounted && token == generation) {
            setState(() => progress = value);
          }
        },
      );
      if (!mounted || token != generation) {
        return;
      }
      final smaller = result.where((c) => c.bytes != null);
      setState(() {
        choices = result;
        selected = smaller.isEmpty ? null : smaller.first;
        loading = false;
      });
    } on PdfCompressionCancelled {
      // Navigating away discards unfinished work.
    } catch (_) {
      if (mounted && token == generation) {
        setState(() {
          loading = false;
          error =
              'Could not compress this PDF. It may be protected or damaged.';
        });
      }
    }
  }

  Future<void> _preview() async {
    final choice = selected;
    if (choice == null || choice.bytes == null) {
      return;
    }
    var saved = false;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => PdfResultScreen(
          bytes: choice.bytes!,
          name: '${widget.title} - compressed',
          repository: widget.repository,
          onSaved: () {
            saved = true;
            widget.onSaved();
          },
          message:
              '${compressionFileSize(widget.bytes.length)} → ${compressionFileSize(choice.size)}'
              '${choice.imageOnly ? ' · Image copy: text, forms and links are flattened.' : ''}',
        ),
      ),
    );
    if (mounted && saved) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Compress PDF')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('Original · ${compressionFileSize(widget.bytes.length)}'),
              const SizedBox(height: 16),
              if (loading) ...[
                LinearProgressIndicator(value: progress > 0 ? progress : null),
                const SizedBox(height: 8),
                const Text('Calculating sizes…'),
                TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ] else if (error != null) ...[
                Text(error!),
                TextButton(onPressed: _measure, child: const Text('Retry')),
              ] else ...[
                for (final choice in choices)
                  Card(
                    child: ListTile(
                      enabled: choice.bytes != null,
                      leading: Icon(
                        identical(selected, choice)
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                      ),
                      title: Text(choice.mode.label),
                      subtitle: Text(
                        '${compressionFileSize(choice.size)}${choice.bytes == null ? ' · Not smaller' : ''}',
                      ),
                      onTap: choice.bytes == null
                          ? null
                          : () => setState(() => selected = choice),
                    ),
                  ),
                if (selected == null)
                  const Text(
                    'This PDF is already smaller than these image copies.',
                  ),
                if (selected?.imageOnly == true)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Image copy · Text, forms and links become flat.',
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: selected == null ? null : _preview,
                  icon: const Icon(Icons.preview_outlined),
                  label: const Text('Preview'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
