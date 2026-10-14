import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/reading_progress.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('progress persists independently for each document', () async {
    final progress = ReadingProgress();
    await progress.load();
    progress.record('first', .42);
    progress.record('second', .85);
    await progress.flush();
    final restored = ReadingProgress();
    await restored.load();
    expect(restored.percent('first'), 42);
    expect(restored.percent('second'), 85);
    expect(restored.percent('unread'), 0);
    progress.dispose();
    restored.dispose();
  });

  test('revisiting earlier pages does not erase completion progress', () async {
    final progress = ReadingProgress();
    await progress.load();
    progress.record('book', .7);
    progress.record('book', .1);
    expect(progress.percent('book'), 70);
    progress.record('book', 2);
    expect(progress.percent('book'), 100);
    progress.record('book', double.nan);
    await progress.flush();
    progress.dispose();
  });

  test(
    'an early reader update cannot overwrite saved progress before loading',
    () async {
      SharedPreferences.setMockInitialValues({
        ReadingProgress.storageKey: jsonEncode({'book': .75}),
      });
      final progress = ReadingProgress();
      progress.record('book', .01);
      await progress.flush();
      expect(progress.percent('book'), 75);
      progress.dispose();
    },
  );
}
