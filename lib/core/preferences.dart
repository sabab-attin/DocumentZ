import 'package:flutter/foundation.dart';
import 'dart:ui' show TextAlign;
import 'package:shared_preferences/shared_preferences.dart';

import 'themes.dart';

enum ReadingAlignment {
  left('Left', TextAlign.left), right('Right', TextAlign.right),
  center('Centered', TextAlign.center), justify('Justified', TextAlign.justify);
  const ReadingAlignment(this.label, this.textAlign);
  final String label;
  final TextAlign textAlign;
}

class ReaderPreferences extends ChangeNotifier {
  ReaderPreferences({
    this.store,
    this.theme = ReaderTheme.light,
    this.fontSize = 20,
    this.pageDark = false,
    this.alignment = ReadingAlignment.left,
  });
  final SharedPreferences? store;
  ReaderTheme theme;
  double fontSize;
  bool pageDark;
  ReadingAlignment alignment;
  bool saveFailed = false;

  static Future<ReaderPreferences> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final name = store.getString('theme');
      return ReaderPreferences(
        store: store,
        theme: ReaderTheme.values.firstWhere(
          (t) => t.name == name,
          orElse: () => name == 'night' ? ReaderTheme.dark : ReaderTheme.light,
        ),
        fontSize: (store.getDouble('fontSize') ?? 20).clamp(16, 32),
        pageDark: store.getBool('pageDark') ?? false,
        alignment: ReadingAlignment.values.firstWhere((a) => a.name == store.getString('readingAlignment'), orElse: () => ReadingAlignment.left),
      );
    } catch (_) {
      return ReaderPreferences()..saveFailed = true;
    }
  }

  Future<void> setTheme(ReaderTheme value) async {
    theme = value;
    notifyListeners();
    await _save(() => store?.setString('theme', value.name));
  }

  Future<void> setFontSize(double value) async {
    fontSize = value.clamp(16, 32);
    notifyListeners();
    await _save(() => store?.setDouble('fontSize', fontSize));
  }

  Future<void> setPageDark(bool value) async {
    pageDark = value;
    notifyListeners();
    await _save(() => store?.setBool('pageDark', value));
  }

  Future<void> setAlignment(ReadingAlignment value) async {
    alignment = value;
    notifyListeners();
    await _save(() => store?.setString('readingAlignment', value.name));
  }

  Future<void> _save(Future<bool>? Function() write) async {
    try {
      saveFailed = await write() != true;
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }
}
