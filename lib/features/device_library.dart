import '../data/browse_formats.dart';
import '../data/document_file_info.dart';
import 'document_shelf.dart';
import 'shelf_preferences.dart';

import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import 'dart:async';

import '../data/reading_progress.dart';
import 'document_tile.dart';
import '../data/library_changes.dart';
import 'document_actions.dart';
import '../data/recent_documents.dart';
import '../data/document_sharing.dart';

import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/preferences.dart';
import '../data/device_documents.dart';
import '../data/import_validation.dart';
import '../domain/book.dart';
import '../domain/services.dart';
import 'reader.dart';
import 'edit.dart';
import 'document_cover.dart';

class DeviceLibraryScreen extends StatefulWidget {
  const DeviceLibraryScreen({
    super.key,
    required this.repository,
    required this.preferences,
    required this.onChanged,
    this.revision = 0,
  });
  final int revision;
  final LibraryRepository repository;
  final ReaderPreferences preferences;
  final VoidCallback onChanged;
  @override
  State<DeviceLibraryScreen> createState() => _DeviceLibraryScreenState();
}

class _LibraryItem {
  const _LibraryItem(this.id, this.name, this.book, this.device);
  final String id, name;
  final Book? book;
  final DeviceDocument? device;
  BookFormat get format => book?.format ?? importFormat(name);
}

class _DeviceLibraryScreenState extends State<DeviceLibraryScreen>
    with WidgetsBindingObserver {
  final shelf = ShelfPreferences('device-library', newestFirst: true);
  Map<String, DocumentFileInfo> fileInfo = {};
  void _shelfChanged() {
    if (mounted) setState(() => _orderDirty = true);
  }

  ShelfOrderData _order(_LibraryItem item) => ShelfOrderData(
    id: item.id,
    name: item.name,
    type: item.format.name,
    size: item.device?.size ?? fileInfo[item.book?.id]?.size,
    modified:
        (item.device?.modified ?? fileInfo[item.book?.id]?.modified ?? 0) > 0
        ? item.device?.modified ?? fileInfo[item.book?.id]?.modified
        : null,
    opened: RecentDocuments.instance.accessed[item.book?.id],
    progress: item.book == null
        ? 0
        : ReadingProgress.instance.fraction(item.book!.id),
  );

  List<_LibraryItem> items = [];
  List<_LibraryItem> _orderedItems = [];
  Map<String, String> _searchTokens = {};
  bool _orderDirty = true;
  List<String> folders = [], errors = [];
  final selected = <String>{};
  final imported = <String, String>{};
  final coverCache = <String, Future<Uint8List?>>{};
  Future<void> coverQueue = Future.value();
  Future<Uint8List?> _cover(_LibraryItem item) {
    final repository = widget.repository;
    final book = item.book;
    if (repository is! ImportableLibrary || book == null) {
      return coverCache.putIfAbsent(
        book?.id ?? 'empty',
        () => Future<Uint8List?>.value(null),
      );
    }
    return coverCache.putIfAbsent(book.id, () {
      final next = coverQueue.then(
        (_) => mounted
            ? loadDocumentCover(book, repository)
            : Future<Uint8List?>.value(null),
      );
      coverQueue = next.then<void>((_) {});
      return next;
    });
  }

  final query = TextEditingController();
  final scroll = ScrollController();
  bool loading = true, busy = false;
  bool storageAllowed = false;
  int generation = 0;
  String? failure;
  static const mappingKey = 'documentz.deviceImports.v1';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LibraryChanges.instance.addListener(_refresh);
    shelf.addListener(_shelfChanged);
    unawaited(shelf.load());
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_offerStorageAccess());
      }
    });
    unawaited(ReadingProgress.instance.load());
  }

  @override
  void didUpdateWidget(covariant DeviceLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LibraryChanges.instance.removeListener(_refresh);
    shelf.removeListener(_shelfChanged);
    shelf.dispose();
    generation++;
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !busy && !loading) {
      unawaited(_refresh());
    }
  }

  Future<void> _rescan() async {
    try {
      await scanDeviceDocuments(refresh: true);
      if (mounted) await _refresh();
    } catch (_) {
      if (mounted) {
        _actionFailure(
          'Could not refresh the document index. Check folder access and try again.',
        );
      }
    }
  }

  Future<void> _refresh() async {
    final token = ++generation;
    if (mounted) {
      setState(() {
        loading = true;
        failure = null;
      });
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final mappings = (jsonDecode(prefs.getString(mappingKey) ?? '{}') as Map)
          .cast<String, String>();
      final books = await widget.repository.listBooks();
      final access = await hasDeviceStorageAccess();
      final scan = await scanDeviceDocuments();
      final metadata = await documentFileInfo(books);
      await RecentDocuments.instance.load();
      final byId = {for (final book in books) book.id: book};
      final mapped = <String>{};
      final next = <_LibraryItem>[];
      for (final doc in scan.documents) {
        if (!isBrowseDocumentName(doc.name)) {
          continue;
        }
        final book = byId[mappings[doc.versionKey]];
        if (book != null) mapped.add(book.id);
        next.add(_LibraryItem(doc.location, doc.name, book, doc));
      }
      for (final book in books) {
        if (!mapped.contains(book.id) && isBrowseDocumentFormat(book.format)) {
          next.add(_LibraryItem(book.id, book.title, book, null));
        }
      }
      if (!mounted || token != generation) return;
      setState(() {
        imported
          ..clear()
          ..addAll(mappings);
        items = next;
        _searchTokens = {
          for (final item in next)
            item.id: '${item.name.toLowerCase()} ${item.format.name}',
        };
        _orderDirty = true;
        fileInfo = metadata;
        storageAllowed = access;
        folders = scan.folders;
        errors = scan.errors;
        selected.removeWhere((id) => !items.any((item) => item.id == id));
      });
    } catch (_) {
      if (mounted && token == generation) {
        setState(
          () => failure =
              'Could not refresh documents. Check folder access and try again.',
        );
      }
    } finally {
      if (mounted && token == generation) setState(() => loading = false);
    }
  }

  void _actions(_LibraryItem item) {
    if (busy) return;
    showDocumentActions(
      context,
      title: item.name,
      onShare: () async {
        try {
          final book = await _book(item);
          if (mounted && widget.repository is ImportableLibrary) {
            await shareDocument(
              context,
              widget.repository as ImportableLibrary,
              book,
            );
          }
        } catch (_) {
          _actionFailure('Could not share this document.');
        }
      },
      onRename: () async {
        final name = await askDocumentName(context, item.name);
        if (name == null || !mounted || busy) return;
        setState(() => busy = true);
        try {
          if (item.device != null) {
            final changed = await renameDeviceDocument(item.device!, name);
            final book = item.book;
            if (book != null) {
              imported.remove(item.device!.versionKey);
              imported[changed.versionKey] = book.id;
              await (await SharedPreferences.getInstance()).setString(
                mappingKey,
                jsonEncode(imported),
              );
              final repository = widget.repository;
              if (repository is MutableLibrary) {
                await repository.renameDocument(book, documentTitle(name));
              }
            }
          } else {
            final repository = widget.repository;
            if (repository is! MutableLibrary || item.book == null) {
              throw const FormatException('Rename is unavailable.');
            }
            await repository.renameDocument(item.book!, name);
          }
          if (mounted) {
            widget.onChanged();
            await _refresh();
          }
        } catch (e) {
          _actionFailure(
            e is FormatException
                ? e.message
                : e.toString().contains('permission')
                ? 'Reconnect this folder and allow write access.'
                : 'Could not rename this document.',
          );
        } finally {
          if (mounted) setState(() => busy = false);
        }
      },
      onDelete: () async {
        if (!await confirmDocumentDelete(
              context,
              item.device != null
                  ? 'Deletes this file from device storage. Its linked DocumentZ copy will also be removed. This cannot be undone.'
                  : 'Deletes the copy stored in DocumentZ. The original device file is unchanged.',
            ) ||
            !mounted ||
            busy) {
          return;
        }
        setState(() => busy = true);
        try {
          if (item.device != null) await deleteDeviceDocument(item.device!);
          final repository = widget.repository;
          if (item.book != null && repository is MutableLibrary) {
            await repository.deleteDocument(item.book!);
            await RecentDocuments.instance.remove(item.book!.id);
          }
          if (item.device != null) {
            imported.remove(item.device!.versionKey);
            await (await SharedPreferences.getInstance()).setString(
              mappingKey,
              jsonEncode(imported),
            );
          }
          if (mounted) {
            widget.onChanged();
            await _refresh();
          }
        } catch (_) {
          _actionFailure(
            'Could not complete deletion. Reconnect the folder with write access, then refresh to check its current contents.',
          );
        } finally {
          if (mounted) setState(() => busy = false);
        }
      },
      onSelect: () => setState(() {
        if (!selected.add(item.id)) selected.remove(item.id);
      }),
    );
  }

  void _actionFailure(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<Book> _book(_LibraryItem item) async {
    if (item.book != null) return item.book!;
    final repository = widget.repository;
    if (repository is! ImportableLibrary || item.device == null) {
      throw const FormatException('Cannot open document.');
    }
    final current = imported[item.device!.versionKey];
    if (current != null) {
      final books = await repository.listBooks();
      for (final book in books) {
        if (book.id == current) return book;
      }
    }
    final book = await repository.importDocument(
      item.name,
      openDeviceDocument(item.device!),
    );
    imported[item.device!.versionKey] = book.id;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(mappingKey, jsonEncode(imported))) {
      throw const FormatException('Could not save document index.');
    }
    return book;
  }

  Future<void> _open(_LibraryItem item) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final book = await _book(item);
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            repository: widget.repository,
            preferences: widget.preferences,
          ),
        ),
      );
      if (mounted) {
        widget.onChanged();
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'Could not open this document.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit() async {
    if (busy || selected.isEmpty) return;
    setState(() => busy = true);
    try {
      final documents = <Book>[];
      for (final item in items.where((item) => selected.contains(item.id))) {
        documents.add(await _book(item));
      }
      if (!mounted) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('Edit ${documents.length} documents')),
            body: EditScreen(
              repository: widget.repository,
              onSaved: widget.onChanged,
              initialDocuments: documents,
            ),
          ),
        ),
      );
      if (mounted) {
        setState(selected.clear);
        widget.onChanged();
        await _refresh();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'Could not open selected documents.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _offerStorageAccess() async {
    if (!supportsDeviceStorageAccess) {
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      if (await hasDeviceStorageAccess() ||
          prefs.getBool('documentz.storageAccessAsked.v1') == true) {
        return;
      }
      await prefs.setBool('documentz.storageAccessAsked.v1', true);
      if (!mounted) {
        return;
      }
      final allow = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('Browse local documents'),
          content: const Text(
            'Allow storage access to find documents across your device. You control this permission in Android settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Allow access'),
            ),
          ],
        ),
      );
      if (allow == true && mounted) {
        await _storageAccess();
      }
    } catch (_) {
      // The access button remains available if the system request could not open.
    }
  }

  Future<void> _storageAccess() async {
    if (busy) {
      return;
    }
    setState(() => busy = true);
    try {
      await requestDeviceStorageAccess();
      await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open storage access settings.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _addFolder() async {
    if (busy || loading) return;
    setState(() => busy = true);
    try {
      if (await addDeviceFolder()) await _refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access this folder.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _folders() => showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const ListTile(title: Text('Connected folders')),
          for (final folder in folders)
            ListTile(
              title: Text(
                Uri.decodeFull(folder),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: IconButton(
                tooltip: 'Disconnect folder',
                icon: const Icon(Icons.link_off),
                onPressed: () async {
                  Navigator.pop(sheet);
                  try {
                    await removeDeviceFolder(folder);
                    await _refresh();
                  } catch (_) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not disconnect folder.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ),
        ],
      ),
    ),
  );
  void _tapItem(_LibraryItem item) {
    if (busy) return;
    if (selected.isNotEmpty) {
      setState(() {
        if (!selected.add(item.id)) {
          selected.remove(item.id);
        }
      });
    } else {
      _open(item);
    }
  }

  void _selectItem(_LibraryItem item, bool value) => setState(() {
    if (value) {
      selected.add(item.id);
    } else {
      selected.remove(item.id);
    }
  });
  Widget _gridTile(_LibraryItem item, DocumentTileLayout layout) =>
      DocumentTile(
        key: ValueKey(item.id),
        title: item.name,
        format: item.format,
        cover: _cover(item),
        layout: layout,
        progress: item.book == null
            ? 0
            : ReadingProgress.instance.fraction(item.book!.id),
        selected: selected.contains(item.id),
        selectable: true,
        onOptions: busy ? null : () => _actions(item),
        onSelected: busy ? null : (value) => _selectItem(item, value),
        onOpen: busy ? null : () => _tapItem(item),
      );
  Widget _rowTile(_LibraryItem item) {
    final metadata = _order(item);
    return ShelfDocumentRow(
      key: ValueKey(item.id),
      title: item.name,
      format: item.format,
      view: shelf.view,
      progress: metadata.progress ?? 0,
      size: metadata.size,
      modified: metadata.modified,
      folder: item.device?.folder,
      cover: shelf.view == ShelfView.tiles || shelf.view == ShelfView.content
          ? _cover(item)
          : null,
      selected: selected.contains(item.id),
      selectable: true,
      onOptions: busy ? null : () => _actions(item),
      onSelected: busy ? null : (value) => _selectItem(item, value),
      onOpen: busy ? null : () => _tapItem(item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = query.text.trim().toLowerCase();
    if (_orderDirty) {
      _orderedItems = items.toList()
        ..sort((a, b) => shelf.compare(_order(a), _order(b)));
      _orderDirty = false;
    }
    final matches = text.isEmpty
        ? _orderedItems
        : _orderedItems
              .where((item) => _searchTokens[item.id]?.contains(text) ?? false)
              .toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Library',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      ShelfViewControls(preferences: shelf),
                      IconButton(
                        tooltip: 'Connected folders',
                        onPressed: folders.isEmpty ? null : _folders,
                        icon: const Icon(Icons.folder_copy_outlined),
                      ),
                      IconButton(
                        tooltip: 'Refresh documents',
                        onPressed: loading || busy || deviceDocumentIndexing
                            ? null
                            : _rescan,
                        icon: const Icon(Icons.refresh),
                      ),
                    ],
                  ),
                  if (supportsDeviceStorageAccess && storageAllowed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storage_outlined),
                      title: const Text('Device storage access is on'),
                      subtitle: Text(
                        loading
                            ? 'Finding documents…'
                            : deviceDocumentIndexing
                            ? 'Building your document index… You can keep browsing.'
                            : '${items.where((item) => item.device != null).length} documents · Updates automatically',
                      ),
                      trailing: IconButton(
                        tooltip: 'Scan device storage',
                        onPressed: loading || busy || deviceDocumentIndexing
                            ? null
                            : _rescan,
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  if (supportsDeviceStorageAccess && !storageAllowed)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : _storageAccess,
                        icon: const Icon(Icons.storage_outlined),
                        label: const Text('Allow local storage access'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: query,
                          decoration: const InputDecoration(
                            hintText: 'Search documents',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Add folder',
                        onPressed: busy || loading ? null : _addFolder,
                        icon: const Icon(Icons.create_new_folder_outlined),
                      ),
                    ],
                  ),
                  if (selected.isNotEmpty)
                    Row(
                      children: [
                        Text('${selected.length} selected'),
                        const Spacer(),
                        TextButton(
                          onPressed: () => setState(selected.clear),
                          child: const Text('Clear'),
                        ),
                        FilledButton.icon(
                          onPressed: busy ? null : _edit,
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Edit'),
                        ),
                      ],
                    ),
                  if (errors.isNotEmpty)
                    Text(
                      'Some folders could not be read. Reconnect them to restore access.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            if (loading || busy || deviceDocumentIndexing)
              const LinearProgressIndicator(),
            Expanded(
              child: failure != null
                  ? Center(child: Text(failure!))
                  : matches.isEmpty && !loading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              text.isEmpty
                                  ? supportsDeviceStorageAccess
                                        ? 'Allow local storage access to find documents.'
                                        : 'Add folders to find documents on this device.'
                                  : 'No documents found.',
                            ),
                            if (text.isEmpty)
                              TextButton.icon(
                                onPressed: supportsDeviceStorageAccess
                                    ? _storageAccess
                                    : _addFolder,
                                icon: const Icon(Icons.storage_outlined),
                                label: Text(
                                  supportsDeviceStorageAccess
                                      ? 'Allow access'
                                      : 'Add folder',
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        return ListenableBuilder(
                          listenable: ReadingProgress.instance,
                          builder: (context, _) => CustomScrollView(
                            controller: scroll,
                            scrollCacheExtent: const ScrollCacheExtent.pixels(
                              240,
                            ),
                            slivers: [
                              SliverPadding(
                                padding: const EdgeInsets.all(16),
                                sliver: DocumentShelfSliver<_LibraryItem>(
                                  items: matches,
                                  preferences: shelf,
                                  width: constraints.maxWidth,
                                  typeOf: (item) => item.format.name,
                                  selectionEnabled: true,
                                  tileBuilder: _gridTile,
                                  rowBuilder: _rowTile,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
