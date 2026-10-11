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
  int libraryRevision = 0;
  late final LibraryRepository repository =
      widget.repository ?? createLibrary();
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pages = [
      LibraryScreen(key: ValueKey(libraryRevision), repository: repository, preferences: widget.preferences),
      EditScreen(repository: repository, onSaved: () => setState(() => libraryRevision++)),
      SettingsScreen(preferences: widget.preferences),
    ];
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              NavigationRail(
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    setState(() => selected = index),
                labelType: NavigationRailLabelType.all,
                leading: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Icon(Icons.auto_stories_outlined, size: 32),
                ),
                destinations: const [
                  NavigationRailDestination(
                    icon: Icon(Icons.local_library_outlined),
                    selectedIcon: Icon(Icons.local_library),
                    label: Text('Library'),
                  ),
                  NavigationRailDestination(icon: Icon(Icons.edit_outlined), label: Text('Edit')),
                  NavigationRailDestination(
                    icon: Icon(Icons.tune),
                    label: Text('Settings'),
                  ),
                ],
              ),
            if (wide) const VerticalDivider(width: 1),
            Expanded(
              child: IndexedStack(index: selected, children: pages),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (index) =>
                  setState(() => selected = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.local_library_outlined),
                  label: 'Library',
                ),
                NavigationDestination(icon: Icon(Icons.edit_outlined), label: 'Edit'),
                NavigationDestination(
                  icon: Icon(Icons.tune),
                  label: 'Settings',
                ),
              ],
            ),
    );
  }
}
