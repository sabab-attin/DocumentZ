import '../core/desktop_platform.dart';
import '../data/external_document_import.dart';
import '../data/document_file_info.dart';
import 'document_shelf.dart';
import 'shelf_preferences.dart';
import 'document_tile.dart';
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
    this.multiplePicker = pickDocuments,
    this.coverLoader = loadDocumentCover,
    this.recentOnly = false,
  });
  final bool recentOnly;
  final LibraryRepository repository;
  final ReaderPreferences preferences;
  final DocumentPicker picker;
  final Future<List<PickedDocument>> Function() multiplePicker;
  final Future<Uint8List?> Function(Book, ImportableLibrary) coverLoader;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  late final shelf = ShelfPreferences(
    widget.recentOnly ? 'recent' : 'imported-library',
    recent: widget.recentOnly,
  );
  Map<String, DocumentFileInfo> fileInfo = {};
  Map<String, int> accessTimes = {};
  void _shelfChanged() {
    if (mounted) setState(() {});
  }

  ShelfOrderData _order(Book book) => ShelfOrderData(
    id: book.id,
    name: book.title,
    type: book.format.name,
    modified: fileInfo[book.id]?.modified,
    size: fileInfo[book.id]?.size,
    opened: accessTimes[book.id] ?? RecentDocuments.instance.accessed[book.id],
    progress: ReadingProgress.instance.fraction(book.id),
  );

  Future<List<Book>> _loadBooks() async {
    final all = await widget.repository.listBooks();
    fileInfo = await documentFileInfo(all);
    await RecentDocuments.instance.load();
    if (!widget.recentOnly) return all;
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
    accessTimes = times;
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
    shelf.addListener(_shelfChanged);
    unawaited(shelf.load());
    unawaited(ReadingProgress.instance.load());
  }

  @override
  void dispose() {
    LibraryChanges.instance.removeListener(_refresh);
    shelf.removeListener(_shelfChanged);
    shelf.dispose();
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
      final List<PickedDocument> selections;
      if (isWindowsDesktop) {
        selections = await widget.multiplePicker();
      } else {
        final selection = await widget.picker();
        selections = selection == null ? [] : [selection];
      }
      if (selections.isEmpty) return;
      for (final selection in selections) {
        try {
          final book = isWindowsDesktop && selection.localPath != null
              ? await importExternalDocument(
                  repository,
                  selection.name,
                  selection.localPath!,
                )
              : await repository.importDocument(
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
          if (isWindowsDesktop) {
            unawaited(
              Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => ReaderScreen(
                    book: book,
                    preferences: widget.preferences,
                    repository: repository,
                  ),
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Added ${book.title} to your library.')),
            );
          }
        } catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error is FormatException
                    ? error.message.toString()
                    : 'Could not open ${selection.name}. Check the file and try again.',
              ),
            ),
          );
        }
      }
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
          return CustomScrollView(
            key: const PageStorageKey('recent-document-scroll'),
            scrollCacheExtent: const ScrollCacheExtent.pixels(240),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.recentOnly ? 'Recent' : 'Library',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                          ),
                          ShelfViewControls(preferences: shelf),
                        ],
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
                            importing
                                ? 'Adding documentâ€¦'
                                : (isWindowsDesktop
                                      ? 'Open document'
                                      : 'Add document'),
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
                  matches.sort((a, b) => shelf.compare(_order(a), _order(b)));
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
                      sliver: DocumentShelfSliver<Book>(
                        items: matches,
                        preferences: shelf,
                        width: constraints.maxWidth,
                        typeOf: (book) => book.format.name,
                        tileBuilder: _documentCard,
                        rowBuilder: _documentRow,
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

  Widget _documentRow(Book book) => ShelfDocumentRow(
    key: ValueKey(book.id),
    title: book.title,
    format: book.format,
    view: shelf.view,
    progress: ReadingProgress.instance.fraction(book.id),
    size: fileInfo[book.id]?.size,
    modified: fileInfo[book.id]?.modified,
    cover: shelf.view == ShelfView.tiles || shelf.view == ShelfView.content
        ? _cover(book)
        : null,
    onOptions: widget.repository is ImportableLibrary
        ? () => _actions(book)
        : null,
    onOpen: () => Navigator.of(context)
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
  );

  Widget _documentCard(Book book, DocumentTileLayout layout) => DocumentTile(
    key: ValueKey(book.id),
    title: book.title,
    format: book.format,
    cover: _cover(book),
    layout: layout,
    progress: ReadingProgress.instance.fraction(book.id),
    onOptions: widget.repository is ImportableLibrary
        ? () => _actions(book)
        : null,
    onOpen: () => Navigator.of(context)
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
  );
}
