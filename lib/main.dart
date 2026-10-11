import 'package:flutter/material.dart';

import 'app.dart';
import 'core/preferences.dart';
import 'data/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await prepareAppStorage();
  runApp(ReaderApp(preferences: await ReaderPreferences.load()));
}
