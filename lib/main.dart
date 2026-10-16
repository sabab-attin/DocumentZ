import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'core/preferences.dart';
import 'data/app_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Tinos',
    ], await rootBundle.loadString('assets/fonts/OFL-Tinos.txt'));
    yield LicenseEntryWithLineBreaks([
      'ZXing Android Embedded',
      'ZXing core',
    ], await rootBundle.loadString('assets/licenses/zxing-android.txt'));
  });
  await prepareAppStorage();
  runApp(ReaderApp(preferences: await ReaderPreferences.load()));
}
