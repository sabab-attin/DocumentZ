import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ShelfView {
  extraLarge('Extra large icons', Icons.crop_portrait),
  large('Large icons', Icons.photo_size_select_large),
  medium('Medium icons', Icons.grid_view_outlined),
  small('Small icons', Icons.apps),
  list('List', Icons.view_list_outlined),
  details('Details', Icons.table_rows_outlined),
  tiles('Tiles', Icons.view_agenda_outlined),
  content('Content', Icons.view_stream_outlined);

  const ShelfView(this.label, this.icon);
  final String label;
  final IconData icon;
  bool get grid => index <= ShelfView.small.index;
}

enum ShelfSort {
  name('Name', Icons.sort_by_alpha),
  modified('Date modified', Icons.update),
  type('Type', Icons.description_outlined),
  opened('Last opened', Icons.history),
  size('Size', Icons.storage_outlined),
  progress('Reading progress', Icons.auto_stories_outlined);

  const ShelfSort(this.label, this.icon);
  final String label;
  final IconData icon;
}

class ShelfOrderData {
  const ShelfOrderData({
    required this.id,
    required this.name,
    required this.type,
    this.modified,
    this.opened,
    this.size,
    this.progress,
  });
  final String id, name, type;
  final int? modified, opened, size;
  final double? progress;
}

class ShelfPreferences extends ChangeNotifier {
  ShelfPreferences(this.scope, {bool recent = false})
    : sort = recent ? ShelfSort.opened : ShelfSort.name,
      descending = recent;
  final String scope;
  ShelfView view = ShelfView.medium;
  ShelfSort sort;
  bool descending, groupByType = false, disposed = false;
  SharedPreferences? _store;
  int _revision = 0;
  String _key(String field) => 'documentz.shelf.$scope.$field';
  Future<void> load() async {
    try {
      final revision = _revision;
      final storage = await SharedPreferences.getInstance();
      if (disposed || revision != _revision) return;
      _store = storage;
      view = ShelfView.values.firstWhere(
        (v) => v.name == storage.getString(_key('view')),
        orElse: () => view,
      );
      sort = ShelfSort.values.firstWhere(
        (v) => v.name == storage.getString(_key('sort')),
        orElse: () => sort,
      );
      descending = storage.getBool(_key('descending')) ?? descending;
      groupByType = storage.getBool(_key('group')) ?? groupByType;
      notifyListeners();
    } catch (_) {
      /* Views still work for this session. */
    }
  }

  Future<void> choose({
    ShelfView? view,
    ShelfSort? sort,
    bool? descending,
    bool? groupByType,
  }) async {
    _revision++;
    this.view = view ?? this.view;
    this.sort = sort ?? this.sort;
    this.descending = descending ?? this.descending;
    this.groupByType = groupByType ?? this.groupByType;
    if (disposed) return;
    notifyListeners();
    try {
      final storage = _store ?? await SharedPreferences.getInstance();
      await storage.setString(_key('view'), this.view.name);
      await storage.setString(_key('sort'), this.sort.name);
      await storage.setBool(_key('descending'), this.descending);
      await storage.setBool(_key('group'), this.groupByType);
    } catch (_) {
      /* Views still work for this session. */
    }
  }

  int compare(ShelfOrderData a, ShelfOrderData b) {
    if (groupByType) {
      final group = a.type.compareTo(b.type);
      if (group != 0) return group;
    }
    final Object? left = switch (sort) {
      ShelfSort.name => a.name.toLowerCase(),
      ShelfSort.type => a.type,
      ShelfSort.modified => a.modified,
      ShelfSort.opened => a.opened,
      ShelfSort.size => a.size,
      ShelfSort.progress => a.progress,
    };
    final Object? right = switch (sort) {
      ShelfSort.name => b.name.toLowerCase(),
      ShelfSort.type => b.type,
      ShelfSort.modified => b.modified,
      ShelfSort.opened => b.opened,
      ShelfSort.size => b.size,
      ShelfSort.progress => b.progress,
    };
    // Missing provider metadata always sorts last, in either direction.
    if (left == null && right != null) return 1;
    if (right == null && left != null) return -1;
    int order;
    if (left == null) {
      order = 0;
    } else if (left is String) {
      order = left.compareTo(right as String);
    } else {
      order = (left as num).compareTo(right as num);
    }
    if (descending) order = -order;
    if (order != 0) return order;
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class ShelfViewControls extends StatelessWidget {
  const ShelfViewControls({super.key, required this.preferences});
  final ShelfPreferences preferences;
  Future<void> _sort(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheet) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ListenableBuilder(
            listenable: preferences,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Sort documents')),
                for (final order in ShelfSort.values)
                  ListTile(
                    leading: Icon(order.icon),
                    title: Text(order.label),
                    trailing: preferences.sort == order
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => preferences.choose(sort: order),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('Ascending'),
                  trailing: !preferences.descending
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => preferences.choose(descending: false),
                ),
                ListTile(
                  leading: const Icon(Icons.arrow_downward),
                  title: const Text('Descending'),
                  trailing: preferences.descending
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => preferences.choose(descending: true),
                ),
                const Divider(),
                SwitchListTile(
                  secondary: const Icon(Icons.workspaces_outline),
                  title: const Text('Group by type'),
                  value: preferences.groupByType,
                  onChanged: (value) => preferences.choose(groupByType: value),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      PopupMenuButton<ShelfView>(
        tooltip: 'View documents',
        icon: Icon(preferences.view.icon),
        onSelected: (view) => preferences.choose(view: view),
        itemBuilder: (_) => [
          for (final view in ShelfView.values)
            CheckedPopupMenuItem(
              value: view,
              checked: view == preferences.view,
              child: Row(
                children: [
                  Icon(view.icon, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(view.label)),
                ],
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: 'Sort documents',
        icon: const Icon(Icons.sort),
        onPressed: () => _sort(context),
      ),
    ],
  );
}
