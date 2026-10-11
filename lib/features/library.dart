import 'package:flutter/material.dart';

import '../core/preferences.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'reader.dart';
import 'document_cover.dart';
import 'dart:typed_data';
import '../data/document_picker.dart';
import '../data/document_sharing.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.repository,
    required this.preferences,
    this.picker = pickDocument,
  });
  final LibraryRepository repository;
  final ReaderPreferences preferences;
  final DocumentPicker picker;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late Future<List<Book>> books = widget.repository.listBooks();
  String query = '';
  final covers = <String, Future<Uint8List?>>{};
  Future<void> coverQueue = Future.value();
  Future<Uint8List?> _cover(Book book) => covers.putIfAbsent(book.id, () {
    final result = coverQueue.then((_) => mounted
      ? loadDocumentCover(book, widget.repository as ImportableLibrary) : Future<Uint8List?>.value(null));
    coverQueue = result.then<void>((_) {});
    return result;
  });
  final searchController = TextEditingController();
  @override
  void dispose() { searchController.dispose(); super.dispose(); }
  bool importing = false;

  void _refresh() {
    if (!mounted) return;
    final refreshedBooks = widget.repository.listBooks();
    setState(() {
      books = refreshedBooks;
    });
  }

  Future<void> _import() async {
    final repository = widget.repository;
    if (repository is! ImportableLibrary || importing) return;
    setState(() => importing = true);
    try {
      final selection = await widget.picker();
      if (selection == null) return;
      final book = await repository.importDocument(selection.name, selection.openStream());
      if (!mounted) return;
      setState(() { searchController.clear(); query = ''; books = repository.listBooks(); });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added ${book.title} to your library.')));
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException ? error.message : 'Could not import this file. Check that it is downloaded and try again.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }
  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          
          const SizedBox(height: 12),
          Text(
            'Library',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),

          if (widget.repository is ImportableLibrary) ...[
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
              onPressed: importing ? null : _import,
              icon: importing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
              label: Text(importing ? 'Adding document…' : 'Add document'),
            )),
            const SizedBox(height: 8),

          ],
          const SizedBox(height: 24),
          TextField(
            controller: searchController,
            decoration: const InputDecoration(
              labelText: 'Search your library',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: 24),

          FutureBuilder<List<Book>>(
            future: books,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Column(
                  children: [
                    const Text('Could not load your library.'),
                    OutlinedButton(
                      onPressed: _refresh,
                      child: const Text('Try again'),
                    ),
                  ],
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final matches = snapshot.data!
                  .where((book) => book.title.toLowerCase().contains(query))
                  .toList();
              if (matches.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    query.isEmpty
                        ? 'Your library is empty.'
                        : 'No documents found.',
                  ),
                );
              }
              return Column(
                children: matches
                    .map(
                      (book) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Card.outlined(
                          child: ListTile(
                            minTileHeight: 104,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            leading: widget.repository is ImportableLibrary ? DocumentCover(
                              format: book.format, cover: _cover(book)) : Icon(
                              book.format == BookFormat.pdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.menu_book_outlined,
                            ),
                            title: Text(book.title),
                            subtitle: Text(
                              book.format.name.toUpperCase(),
                            ),
                            trailing: widget.repository is ImportableLibrary ? IconButton(
                              tooltip: 'Share document', icon: const Icon(Icons.share_outlined),
                              onPressed: () => shareDocument(context, widget.repository as ImportableLibrary, book),
                            ) : const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ReaderScreen(
                                  book: book,
                                  preferences: widget.preferences,
                                  repository: widget.repository,
                                ),
                              ),
                            ).then((_) {
                              _refresh();
                            }),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}

