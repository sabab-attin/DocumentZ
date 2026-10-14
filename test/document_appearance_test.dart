import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/recent_documents.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'global defaults and per-document changes remain separate across reopen',
    () async {
      final defaults = await ReaderPreferences.load();
      expect(defaults.fontFamily, 'Times New Roman');
      expect(defaults.alignment, ReadingAlignment.justify);
      expect(defaults.viewingFit, 'bestFit');
      final first = ReaderPreferences.forDocument(defaults, 'first');
      final second = ReaderPreferences.forDocument(defaults, 'second');
      await first.setFontFamily('monospace');
      await first.setAlignment(ReadingAlignment.right);
      await first.setViewing(fit: 'custom', zoom: 1.25);
      expect(defaults.fontFamily, 'Times New Roman');
      expect(second.alignment, ReadingAlignment.justify);
      await defaults.setFontSize(24);
      expect(first.fontSize, 24);
      expect(second.fontSize, 24);
      await first.setFontSize(18);
      await defaults.setFontSize(26);
      expect(first.fontSize, 18);
      expect(second.fontSize, 26);
      first.dispose();
      second.dispose();
      final reopened = ReaderPreferences.forDocument(defaults, 'first');
      expect(reopened.fontFamily, 'monospace');
      expect(reopened.fontSize, 18);
      expect(reopened.viewingZoom, 1.25);
      reopened.dispose();
      defaults.dispose();
    },
  );
  test(
    'remove from Recents persists until the document is opened again',
    () async {
      final recents = RecentDocuments.instance;
      recents.resetForTests();
      await recents.record('book');
      await recents.remove('book');
      expect(recents.accessed.containsKey('book'), isFalse);
      expect(recents.removed.contains('book'), isTrue);
      recents.resetForTests();
      await recents.load();
      expect(recents.removed.contains('book'), isTrue);
      await recents.record('book');
      expect(recents.removed.contains('book'), isFalse);
      expect(recents.accessed.containsKey('book'), isTrue);
      recents.resetForTests();
    },
  );
}
