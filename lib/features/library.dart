import '../data/library_changes.dart';
import 'document_actions.dart';
import '../data/recent_documents.dart';

import 'dart:async';

import '../data/reading_progress.dart';

import 'package:flutter/material.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;

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
    this.coverLoader = loadDocumentCover,
    this.recentOnly = false,
  });
  final bool recentOnly;
  final LibraryRepository repository;
  final ReaderPreferences preferences;
  final DocumentPicker picker;
  final Future<Uint8List?> Function(Book, ImportableLibrary) coverLoader;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Future<List<Book>> _loadBooks() async {
    final all = await widget.repository.listBooks();
    if (!widget.recentOnly) return all;
    await RecentDocuments.instance.load();
    final times = Map<String, int>.of(RecentDocuments.instance.accessed);
    for (final book in all) {
      if (!times.containsKey(book.id) &&
          !RecentDocuments.instance.removed.contains(book.id)) {
        final position = await widget.repository.positionFor(book.id);
        if (position != null) {
          times[book.id] = position.updatedAt.millisecondsSinceEpoch;
        }
      }
    }
    return all.where((book) => times.containsKey(book.id)).toList()
      ..sort((a, b) => times[b.id]!.compareTo(times[a.id]!));
  }

  late Future<List<Book>> books = _loadBooks();
  String query = '';
  final covers = <String, Future<Uint8List?>>{};
  Future<void> coverQueue = Future.value();
  Future<Uint8List?> _cover(Book book) => covers.putIfAbsent(book.id, () {
    if (widget.repository is! ImportableLibrary) {
      return Future<Uint8List?>.value(null);
    }
    final result = coverQueue.then(
      (_) => mounted
          ? widget.coverLoader(book, widget.repository as ImportableLibrary)
          : Future<Uint8List?>.value(null),
    );
    coverQueue = result.then<void>((_) {});
    return result;
  });
  final searchController = TextEditingController();
  @override
  void initState() {
    super.initState();
    LibraryChanges.instance.addListener(_refresh);
    unawaited(ReadingProgress.instance.load());
  }

  @override
  void dispose() {
    LibraryChanges.instance.removeListener(_refresh);
    searchController.dispose();
    super.dispose();
  }

  bool importing = false;

  void _refresh() {
    if (!mounted) return;
    final refreshedBooks = _loadBooks();
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
      final book = await repository.importDocument(
        selection.name,
        selection.openStream(),
      );
      await RecentDocuments.instance.record(book.id);
      if (!mounted) return;
      setState(() {
        searchController.clear();
        query = '';
        books = _loadBooks();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${book.title} to your library.')),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is FormatException
          ? error.message
          : 'Could not import this file. Check that it is downloaded and try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
          final available = (constraints.maxWidth - 32).clamp(
            0.0,
            double.infinity,
          );
          final columns = largeText || available < 300
              ? 1
              : available >= 760
              ? 4
              : available >= 540
              ? 3
              : 2;
          final width = (available - (columns - 1) * 16) / columns;
          return CustomScrollView(
            key: const PageStorageKey('recent-document-scroll'),
            scrollCacheExtent: const ScrollCacheExtent.pixels(240),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.recentOnly ? 'Recent' : 'Library',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      if (widget.repository is ImportableLibrary) ...[
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: importing ? null : _import,
                          icon: importing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.add),
                          label: Text(
                            importing ? 'Adding document…' : 'Add document',
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      TextField(
                        controller: searchController,
                        decoration: const InputDecoration(
                          labelText: 'Search documents',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) =>
                            setState(() => query = value.trim().toLowerCase()),
                      ),
                    ],
                  ),
                ),
              ),
              FutureBuilder<List<Book>>(
                future: books,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const Text('Could not load your library.'),
                          OutlinedButton(
                            onPressed: _refresh,
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const SliverToBoxAdapter(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  final matches = snapshot.data!
                      .where((book) => book.title.toLowerCase().contains(query))
                      .toList();
                  if (matches.isEmpty) {
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          query.isEmpty
                              ? (widget.recentOnly
                                    ? 'No recently opened documents.'
                                    : 'Your library is empty.')
                              : 'No documents found.',
                        ),
                      ),
                    );
                  }
                  return ListenableBuilder(
                    listenable: ReadingProgress.instance,
                    builder: (context, _) => SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, row) => Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var col = 0; col < columns; col++) ...[
                                  if (col > 0) const SizedBox(width: 16),
                                  if (row * columns + col < matches.length)
                                    SizedBox(
                                      width: width,
                                      child: _documentCard(
                                        matches[row * columns + col],
                                      ),
                                    )
                                  else
                                    SizedBox(width: width),
                                ],
                              ],
                            ),
                          ),
                          childCount: (matches.length + columns - 1) ~/ columns,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    ),
  );
  void _actions(Book book) {
    final repository = widget.repository;
    showDocumentActions(
      context,
      title: book.title,
      onShare: () {
        if (repository is ImportableLibrary) {
          shareDocument(context, repository, book);
        }
      },
      onRename: repository is MutableLibrary
          ? () async {
              final title = await askDocumentName(context, book.title);
              if (title == null || !mounted) return;
              try {
                await repository.renameDocument(book, title);
                if (mounted) _refresh();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not rename this document.'),
                    ),
                  );
                }
              }
            }
          : null,
      onDelete: repository is MutableLibrary
          ? () async {
              if (!await confirmDocumentDelete(
                    context,
                    'Deletes the copy stored in DocumentZ. Your original device file is not deleted.',
                  ) ||
                  !mounted) {
                return;
              }
              try {
                await repository.deleteDocument(book);
                await RecentDocuments.instance.remove(book.id);
                if (mounted) _refresh();
              } catch (_) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Could not delete this document.'),
                    ),
                  );
                }
              }
            }
          : null,
      onRemoveRecent: widget.recentOnly
          ? () async {
              await RecentDocuments.instance.remove(book.id);
              if (mounted) _refresh();
            }
          : null,
    );
  }

  Widget _documentCard(Book book) => Card(
    margin: EdgeInsets.zero,
    elevation: 0,
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onLongPress: () => _actions(book),
      onTap: () => Navigator.of(context)
          .push(
            MaterialPageRoute<void>(
              builder: (_) => ReaderScreen(
                book: book,
                preferences: widget.preferences,
                repository: widget.repository,
              ),
            ),
          )
          .then((_) => _refresh()),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => DocumentCover(
                format: book.format,
                width: constraints.maxWidth,
                height: constraints.maxWidth * 1.35,
                cover: _cover(book),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    book.format.name.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (widget.repository is ImportableLibrary)
                  IconButton(
                    tooltip: 'Document options',
                    icon: const Icon(Icons.more_vert, size: 20),
                    onPressed: () => _actions(book),
                  )
                else
                  const SizedBox(height: 48),
              ],
            ),
            Text(
              'Progress ${ReadingProgress.instance.percent(book.id)}%',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ReadingProgress.instance.fraction(book.id),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    ),
  );
}
