import 'core/desktop_platform.dart';
import 'data/recent_documents.dart';
import 'data/edit_output.dart';
import 'data/automatic_device_changes.dart';
import 'data/external_documents.dart';
import 'data/external_document_import.dart';
import 'features/reader.dart';

import 'dart:async';

import 'features/device_library.dart';
import 'features/annotation_sync_screen.dart';
import 'data/sync_pairing_links.dart';
import 'data/annotation_sync_session.dart';

import 'package:flutter/material.dart';

import 'core/preferences.dart';
import 'domain/services.dart';
import 'data/local_library.dart';
import 'features/library.dart';
import 'features/settings.dart';
import 'features/edit.dart';

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key, required this.preferences, this.repository});
  final ReaderPreferences preferences;
  final LibraryRepository? repository;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => MaterialApp(
      title: 'DocumentZ',
      debugShowCheckedModeBanner: false,
      theme: preferences.theme.data,
      home: ReaderShell(preferences: preferences, repository: repository),
    ),
  );
}

class ReaderShell extends StatefulWidget {
  const ReaderShell({super.key, required this.preferences, this.repository});
  final ReaderPreferences preferences;
  final LibraryRepository? repository;
  @override
  State<ReaderShell> createState() => _ReaderShellState();
}

class _ReaderShellState extends State<ReaderShell> {
  int selected = 0;
  final visitedTabs = <int>{0};
  void _selectTab(int index) {
    if (selected == index) {
      return;
    }
    setState(() {
      selected = index;
      visitedTabs.add(index);
    });
  }

  int libraryRevision = 0;
  late final LibraryRepository repository =
      widget.repository ?? createLibrary();
  AnnotationSyncSession? syncSession;
  @override
  void initState() {
    super.initState();
    editWorkflowCompleted.addListener(_editFinished);
    final library = repository;
    if (library is ImportableLibrary) {
      syncSession = AnnotationSyncSession.forLibrary(library);
      syncSession!.restore();
      unawaited(SyncPairingLinks.start(_openPairingLink));
      unawaited(ExternalDocuments.start(_incomingDocument));
    }
  }

  void _editFinished() {
    if (mounted) {
      setState(() {
        selected = 0;
        visitedTabs.add(0);
        libraryRevision++;
      });
    }
  }

  @override
  void dispose() {
    editWorkflowCompleted.removeListener(_editFinished);
    AutomaticDeviceChanges.stop();
    ExternalDocuments.stop();
    SyncPairingLinks.stop();
    syncSession?.dispose();
    super.dispose();
  }

  bool _openingDocument = false;
  bool _readDocumentsAgain = false;
  void _incomingDocument() {
    if (!mounted) return;
    if (_openingDocument) {
      _readDocumentsAgain = true;
      return;
    }
    _openingDocument = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openIncomingDocuments());
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _openIncomingDocuments() async {
    try {
      do {
        _readDocumentsAgain = false;
        while (mounted) {
          final library = repository;
          if (library is! ImportableLibrary) return;
          final incoming = await ExternalDocuments.take();
          if (incoming == null || !mounted) break;
          final id = incoming['id'] as String;
          final messenger = ScaffoldMessenger.of(context);
          final opening = messenger.showSnackBar(
            const SnackBar(
              content: Text('Opening documentâ€¦'),
              duration: Duration(minutes: 5),
            ),
          );
          try {
            final book = await importExternalDocument(
              library,
              incoming['name'] as String,
              incoming['path'] as String,
            );
            if (!mounted) return;
            await RecentDocuments.instance.record(book.id);
            if (!mounted) return;
            setState(() {
              selected = 0;
              visitedTabs.add(0);
              libraryRevision++;
            });
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
          } catch (error) {
            if (mounted) {
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    error is FormatException
                        ? error.message.toString()
                        : 'Could not open ${incoming['name']}. Check the file and access permissions.',
                  ),
                ),
              );
            }
          } finally {
            opening.close();
            await ExternalDocuments.finish(id);
          }
        }
      } while (_readDocumentsAgain && mounted);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is FormatException ? error.message.toString() : 'Could not open the document. Check the file, storage space and access permissions.',
            ),
          ),
        );
      }
    } finally {
      _openingDocument = false;
      if (_readDocumentsAgain && mounted) _incomingDocument();
    }
  }

  bool _openingPairingRoute = false;
  String? _pendingPairingLink;
  void _openPairingLink(String raw) {
    if (!mounted || SyncPairingLinks.deliverToScreen(raw)) {
      return;
    }
    _pendingPairingLink = raw;
    if (_openingPairingRoute) {
      return;
    }
    _openingPairingRoute = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final link = _pendingPairingLink;
      _pendingPairingLink = null;
      try {
        final library = repository;
        if (mounted && link != null && library is ImportableLibrary) {
          await Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => AnnotationSyncScreen(
                repository: library,
                initialInvite: link,
              ),
            ),
          );
        }
      } finally {
        _openingPairingRoute = false;
        final next = _pendingPairingLink;
        _pendingPairingLink = null;
        if (mounted && next != null) {
          _openPairingLink(next);
        }
      }
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      LibraryScreen(
        key: ValueKey(libraryRevision),
        repository: repository,
        preferences: widget.preferences,
        recentOnly: true,
      ),
      if (!isWindowsDesktop)
        DeviceLibraryScreen(
          revision: libraryRevision,
          repository: repository,
          preferences: widget.preferences,
          onChanged: () => setState(() => libraryRevision++),
        ),
      EditScreen(
        repository: repository,
        onSaved: () => setState(() => libraryRevision++),
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('DocumentZ'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Settings')),
                  body: SettingsScreen(
                    preferences: widget.preferences,
                    repository: repository,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: _selectTab,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Icon(Icons.auto_stories_outlined, size: 32),
                ),
                destinations: [
                  NavigationRailDestination(
                    icon: Icon(Icons.history),
                    label: Text('Recent'),
                  ),
                  if (!isWindowsDesktop)
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      label: Text('Library'),
                    ),
                  NavigationRailDestination(
                    icon: Icon(Icons.edit_outlined),
                    label: Text('Edit'),
                  ),
                ],
              ),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  for (var i = 0; i < pages.length; i++)
                    TickerMode(
                      enabled: i == selected,
                      child: visitedTabs.contains(i)
                          ? pages[i]
                          : const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: _selectTab,
              destinations: [
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'Recent',
                ),
                if (!isWindowsDesktop)
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    label: 'Library',
                  ),
                NavigationDestination(
                  icon: Icon(Icons.edit_outlined),
                  label: 'Edit',
                ),
              ],
            ),
    );
  }
}
