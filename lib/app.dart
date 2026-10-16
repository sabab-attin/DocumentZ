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
    final library = repository;
    if (library is ImportableLibrary) {
      syncSession = AnnotationSyncSession.forLibrary(library);
      syncSession!.restore();
      unawaited(SyncPairingLinks.start(_openPairingLink));
    }
  }

  @override
  void dispose() {
    SyncPairingLinks.stop();
    syncSession?.dispose();
    super.dispose();
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
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.history),
                    label: Text('Recent'),
                  ),
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
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.history),
                  label: 'Recent',
                ),
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
