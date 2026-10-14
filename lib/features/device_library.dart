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

class _DeviceLibraryScreenState extends State<DeviceLibraryScreen> {
  List<_LibraryItem> items = [];
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
  int generation = 0;
  String? failure;
  static const mappingKey = 'documentz.deviceImports.v1';
  @override
  void initState() {
    super.initState();
    LibraryChanges.instance.addListener(_refresh);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DeviceLibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision) _refresh();
  }

  @override
  void dispose() {
    LibraryChanges.instance.removeListener(_refresh);
    generation++;
    query.dispose();
    scroll.dispose();
    super.dispose();
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
      final scan = await scanDeviceDocuments();
      final byId = {for (final book in books) book.id: book};
      final mapped = <String>{};
      final next = <_LibraryItem>[];
      for (final doc in scan.documents) {
        final book = byId[mappings[doc.versionKey]];
        if (book != null) mapped.add(book.id);
        next.add(_LibraryItem(doc.location, doc.name, book, doc));
      }
      for (final book in books) {
        if (!mapped.contains(book.id)) {
          next.add(_LibraryItem(book.id, book.title, book, null));
        }
      }
      next.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted || token != generation) return;
      setState(() {
        imported
          ..clear()
          ..addAll(mappings);
        items = next;
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
  @override
  Widget build(BuildContext context) {
    final text = query.text.trim().toLowerCase();
    final matches = items
        .where(
          (item) =>
              item.name.toLowerCase().contains(text) ||
              item.format.name.contains(text),
        )
        .toList();
    return Column(
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
                  IconButton(
                    tooltip: 'Connected folders',
                    onPressed: folders.isEmpty ? null : _folders,
                    icon: const Icon(Icons.folder_copy_outlined),
                  ),
                  IconButton(
                    tooltip: 'Refresh documents',
                    onPressed: loading || busy ? null : _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
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
        if (loading || busy) const LinearProgressIndicator(),
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
                              ? 'Add folders to find documents on this device.'
                              : 'No documents found.',
                        ),
                        if (text.isEmpty)
                          TextButton.icon(
                            onPressed: _addFolder,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Add folder'),
                          ),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns =
                        MediaQuery.textScalerOf(context).scale(14) > 21
                        ? 1
                        : (constraints.maxWidth / 180).floor().clamp(1, 5);
                    return GridView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisExtent: 304,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: matches.length,
                      itemBuilder: (context, index) {
                        final item = matches[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: busy
                                ? null
                                : () {
                                    if (selected.isNotEmpty) {
                                      setState(() {
                                        if (!selected.add(item.id)) {
                                          selected.remove(item.id);
                                        }
                                      });
                                    } else {
                                      _open(item);
                                    }
                                  },
                            onLongPress: busy ? null : () => _actions(item),
                            child: Padding(
                              padding: const EdgeInsets.all(10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Stack(
                                      children: [
                                        Positioned.fill(
                                          child: DocumentCover(
                                            format: item.format,
                                            width: double.infinity,
                                            height: 220,
                                            cover: _cover(item),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 40,
                                          child: IconButton(
                                            tooltip: 'Document options',
                                            icon: const Icon(Icons.more_vert),
                                            onPressed: busy
                                                ? null
                                                : () => _actions(item),
                                          ),
                                        ),
                                        Positioned(
                                          top: 0,
                                          right: 0,
                                          child: Checkbox(
                                            value: selected.contains(item.id),
                                            onChanged: busy
                                                ? null
                                                : (value) => setState(() {
                                                    if (value == true) {
                                                      selected.add(item.id);
                                                    } else {
                                                      selected.remove(item.id);
                                                    }
                                                  }),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    item.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall,
                                  ),
                                  Text(
                                    item.format.name.toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}
