import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Historical storage names are compatibility keys, not current app branding.
Directory legacyWindowsSupport(Directory current) =>
    Directory(p.join(p.dirname(current.path), 'quiet_reader'));

Future<void> copyLegacyPreferences(Directory old, Directory current) async {
  final source = File(p.join(old.path, 'shared_preferences.json'));
  final destination = File(p.join(current.path, 'shared_preferences.json'));
  if (!await destination.exists() && await source.exists()) {
    await current.create(recursive: true);
    await source.copy(destination.path);
  }
}

Future<void> prepareAppStorage() async {
  if (!Platform.isWindows) return;
  final current = await getApplicationSupportDirectory();
  await copyLegacyPreferences(legacyWindowsSupport(current), current);
}

Future<Directory> applicationLibraryDirectory() async {
  final current = await getApplicationSupportDirectory();
  final library = Directory(p.join(current.path, 'library'));
  if (Platform.isWindows && !await library.exists()) {
    final legacy = Directory(
      p.join(legacyWindowsSupport(current).path, 'library'),
    );
    if (await legacy.exists()) return legacy;
  }
  return library;
}
