import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'document_reader.dart';
import 'format_reader.dart';
import 'settings.dart';
import 'reader_controls.dart';
import '../data/document_sharing.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({
    super.key,
    required this.book,
    required this.preferences,
    this.repository,
  });
  final Book book;
  final ReaderPreferences preferences;
  final LibraryRepository? repository;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}
class _ReaderScreenState extends State<ReaderScreen> {
  final controls = ValueNotifier<bool>(false);
  Book get book => widget.book;
  ReaderPreferences get preferences => widget.preferences;
  LibraryRepository? get repository => widget.repository;
  @override
  void dispose() { controls.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => _content(context),
  );

  Widget _content(BuildContext context) => Scaffold(
    body: SafeArea(child: ReaderControlsScope(expanded: controls, child: Stack(fit: StackFit.expand, children: [
      Positioned.fill(child: _readerBody(context)),
      Positioned(top: 0, left: 0, right: 0, child: ValueListenableBuilder<bool>(valueListenable: controls, builder: (context, open, _) => open
        ? SizedBox(height: 56, child: AppBar(title: Text(book.title), actions: [
          if (repository is ImportableLibrary) IconButton(tooltip: 'Share document',
            icon: const Icon(Icons.share_outlined), onPressed: () => shareDocument(context, repository as ImportableLibrary, book)),
          IconButton(tooltip: 'Reading appearance', icon: const Icon(Icons.tune),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Reading appearance')),
              body: SafeArea(child: SettingsScreen(preferences: preferences)))))),
        ])) : const SizedBox.shrink())),
      Positioned(right: 8, bottom: 4, child: ValueListenableBuilder<bool>(valueListenable: controls,
        builder: (context, open, _) => FilledButton.icon(
          onPressed: () => controls.value = !open,
          icon: Icon(open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up),
          label: Text(open ? 'Hide controls' : 'Controls'),
          style: FilledButton.styleFrom(minimumSize: const Size(120, 48))))),
    ]))),
  );
  Widget _readerBody(BuildContext context) => repository is ImportableLibrary && (book.localPath != null || book.id.startsWith('import-'))
        ? (book.format == BookFormat.pdf || book.format == BookFormat.epub
          ? DocumentReader(book: book, repository: repository as ImportableLibrary, preferences: preferences)
          : FormatReader(book: book, repository: repository as ImportableLibrary, preferences: preferences))
        : _sample(context);

  Widget _sample(BuildContext context) =>
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              if (book.text != null)
                SelectableText(
                  book.text!,
                  style: TextStyle(
                    fontSize: preferences.fontSize,
                    height: 1.75,
                  ),
                )
              else const Text('Document unavailable'),
            ],
          ),
        ),
      );
}



