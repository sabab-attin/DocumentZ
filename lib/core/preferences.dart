import 'package:flutter/foundation.dart';

import 'dart:ui' show TextAlign;

import 'package:shared_preferences/shared_preferences.dart';

import 'themes.dart';
import 'reader_shortcuts.dart';

enum ReadingAlignment {
  left('Left', TextAlign.left),
  right('Right', TextAlign.right),
  center('Centered', TextAlign.center),
  justify('Justified', TextAlign.justify);

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
    this.autoHideControls = true,
    this.showPageButtons = false,
    this.showPageIndicator = true,
    this.alignment = ReadingAlignment.justify,
    this.fontFamily = 'Times New Roman',
    this.viewingFit = 'bestFit',
    this.viewingZoom = 1,
  });
  final SharedPreferences? store;
  late final ReaderShortcuts shortcuts = ReaderShortcuts(store);
  ReaderTheme theme;
  double fontSize;
  bool pageDark;
  bool autoHideControls, showPageButtons, showPageIndicator;
  ReadingAlignment alignment;
  String fontFamily, viewingFit;
  double viewingZoom;
  String? _documentId;
  ReaderPreferences? _defaults;
  final _overrides = <String>{};
  bool get documentSpecific => _documentId != null;
  ReaderPreferences get globalDefaults => _defaults ?? this;
  String _key(String name) => _documentId == null
      ? name
      : 'reading.document.${Uri.encodeComponent(_documentId!)}.$name';
  void _override(String key) {
    if (documentSpecific) _overrides.add(key);
  }

  static ReaderPreferences forDocument(ReaderPreferences input, String id) {
    final defaults = input.globalDefaults;
    final result =
        ReaderPreferences(
            store: defaults.store,
            theme: defaults.theme,
            fontSize: defaults.fontSize,
            fontFamily: defaults.fontFamily,
            alignment: defaults.alignment,
            pageDark: defaults.pageDark,
            viewingFit: defaults.viewingFit,
            viewingZoom: defaults.viewingZoom,
            autoHideControls: defaults.autoHideControls,
            showPageButtons: defaults.showPageButtons,
            showPageIndicator: defaults.showPageIndicator,
          )
          .._documentId = id
          .._defaults = defaults;
    final storage = result.store;
    for (final key in [
      'theme',
      'fontSize',
      'fontFamily',
      'readingAlignment',
      'pageDark',
      'viewingFit',
      'viewingZoom',
      'autoHideControls',
      'showPageButtons',
      'showPageIndicator',
    ]) {
      if (storage?.containsKey(result._key(key)) == true) {
        result._overrides.add(key);
      }
    }
    result.theme = ReaderTheme.values.firstWhere(
      (v) => v.name == storage?.getString(result._key('theme')),
      orElse: () => result.theme,
    );
    result.fontSize =
        (storage?.getDouble(result._key('fontSize')) ?? result.fontSize).clamp(
          16,
          32,
        );
    result.fontFamily =
        storage?.getString(result._key('fontFamily')) ?? result.fontFamily;
    result.alignment = ReadingAlignment.values.firstWhere(
      (v) => v.name == storage?.getString(result._key('readingAlignment')),
      orElse: () => result.alignment,
    );
    result.pageDark =
        storage?.getBool(result._key('pageDark')) ?? result.pageDark;
    result.viewingFit =
        storage?.getString(result._key('viewingFit')) ?? result.viewingFit;
    result.viewingZoom =
        storage?.getDouble(result._key('viewingZoom')) ?? result.viewingZoom;
    result.autoHideControls =
        storage?.getBool(result._key('autoHideControls')) ??
        result.autoHideControls;
    result.showPageButtons =
        storage?.getBool(result._key('showPageButtons')) ??
        result.showPageButtons;
    result.showPageIndicator =
        storage?.getBool(result._key('showPageIndicator')) ??
        result.showPageIndicator;
    defaults.addListener(result._inheritDefaults);
    return result;
  }

  void _inheritDefaults() {
    final defaults = _defaults!;
    if (!_overrides.contains('theme')) theme = defaults.theme;
    if (!_overrides.contains('fontSize')) fontSize = defaults.fontSize;
    if (!_overrides.contains('fontFamily')) fontFamily = defaults.fontFamily;
    if (!_overrides.contains('readingAlignment')) {
      alignment = defaults.alignment;
    }
    if (!_overrides.contains('pageDark')) pageDark = defaults.pageDark;
    if (!_overrides.contains('viewingFit')) viewingFit = defaults.viewingFit;
    if (!_overrides.contains('viewingZoom')) viewingZoom = defaults.viewingZoom;
    if (!_overrides.contains('autoHideControls')) {
      autoHideControls = defaults.autoHideControls;
    }
    if (!_overrides.contains('showPageButtons')) {
      showPageButtons = defaults.showPageButtons;
    }
    if (!_overrides.contains('showPageIndicator')) {
      showPageIndicator = defaults.showPageIndicator;
    }
    notifyListeners();
  }

  Future<void> setFontFamily(String value) async {
    _override('fontFamily');
    fontFamily = value;
    notifyListeners();
    await _save(() => store?.setString(_key('fontFamily'), value));
  }

  Future<void> setViewing({required String fit, double zoom = 1}) async {
    _override('viewingFit');
    _override('viewingZoom');
    viewingFit = fit;
    viewingZoom = zoom.clamp(.5, 8);
    notifyListeners();
    await _save(() async {
      if (store == null) return true;
      return await store!.setString(_key('viewingFit'), fit) &&
          await store!.setDouble(_key('viewingZoom'), viewingZoom);
    });
  }

  Future<void> restoreTypographyDefaults() async {
    if (!documentSpecific) return;
    for (final key in [
      'fontFamily',
      'fontSize',
      'readingAlignment',
      'viewingFit',
      'viewingZoom',
    ]) {
      _overrides.remove(key);
      if (store != null) await store!.remove(_key(key));
    }
    _inheritDefaults();
  }

  @override
  void dispose() {
    _defaults?.removeListener(_inheritDefaults);
    super.dispose();
  }

  bool saveFailed = false;

  static Future<ReaderPreferences> load() async {
    try {
      final store = await SharedPreferences.getInstance();
      final name = store.getString('theme');
      if (!store.containsKey('fontFamily')) {
        await store.setString('fontFamily', 'Times New Roman');
        await store.setString('readingAlignment', 'justify');
        await store.setString('viewingFit', 'bestFit');
      }
      return ReaderPreferences(
        store: store,
        theme: ReaderTheme.values.firstWhere(
          (t) => t.name == name,
          orElse: () => name == 'night' ? ReaderTheme.dark : ReaderTheme.light,
        ),
        fontSize: (store.getDouble('fontSize') ?? 20).clamp(16, 32),
        fontFamily: store.getString('fontFamily') ?? 'Times New Roman',
        viewingFit: store.getString('viewingFit') ?? 'bestFit',
        viewingZoom: store.getDouble('viewingZoom') ?? 1,
        pageDark: store.getBool('pageDark') ?? false,
        autoHideControls: store.getBool('autoHideControls') ?? true,
        showPageButtons: store.getBool('showPageButtons') ?? false,
        showPageIndicator: store.getBool('showPageIndicator') ?? true,
        alignment: ReadingAlignment.values.firstWhere(
          (a) => a.name == store.getString('readingAlignment'),
          orElse: () => ReadingAlignment.justify,
        ),
      );
    } catch (_) {
      return ReaderPreferences()..saveFailed = true;
    }
  }

  Future<void> setTheme(ReaderTheme value) async {
    _override('theme');
    theme = value;
    notifyListeners();
    await _save(() => store?.setString(_key('theme'), value.name));
  }

  Future<void> setFontSize(double value) async {
    _override('fontSize');
    fontSize = value.clamp(16, 32);
    notifyListeners();
    await _save(() => store?.setDouble(_key('fontSize'), fontSize));
  }

  Future<void> setPageDark(bool value) async {
    _override('pageDark');
    pageDark = value;
    notifyListeners();
    await _save(() => store?.setBool(_key('pageDark'), value));
  }

  Future<void> setAlignment(ReadingAlignment value) async {
    _override('readingAlignment');
    alignment = value;
    notifyListeners();
    await _save(() => store?.setString(_key('readingAlignment'), value.name));
  }

  Future<void> setReaderControls({
    bool? autoHide,
    bool? pageButtons,
    bool? pageIndicator,
  }) async {
    if (autoHide != null) _override('autoHideControls');
    if (pageButtons != null) _override('showPageButtons');
    if (pageIndicator != null) _override('showPageIndicator');
    autoHideControls = autoHide ?? autoHideControls;
    showPageButtons = pageButtons ?? showPageButtons;
    showPageIndicator = pageIndicator ?? showPageIndicator;
    notifyListeners();
    await _save(() async {
      if (store == null) return true;
      final results = await Future.wait([
        store!.setBool(_key('autoHideControls'), autoHideControls),
        store!.setBool(_key('showPageButtons'), showPageButtons),
        store!.setBool(_key('showPageIndicator'), showPageIndicator),
      ]);
      return results.every((saved) => saved);
    });
  }

  Future<void> _save(Future<bool>? Function() write) async {
    if (store == null) {
      saveFailed = false;
      return;
    }
    try {
      saveFailed = await write() != true;
    } catch (_) {
      saveFailed = true;
    }
    notifyListeners();
  }
}
