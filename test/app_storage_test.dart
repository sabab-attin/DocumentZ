import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/app_storage_io.dart';

void main() {
  test('rename copies legacy preferences once without modifying originals or newer settings', () async {
    final root = await Directory.systemTemp.createTemp('documentz_storage_');
    addTearDown(() => root.delete(recursive: true));
    final old = await Directory('${root.path}/quiet_reader').create();
    final current = Directory('${root.path}/DocumentZ');
    final source = File('${old.path}/shared_preferences.json');
    await source.writeAsString(
      '{"theme":"dark","annotations.v1.book":"saved"}',
    );
    await copyLegacyPreferences(old, current);
    final destination = File('${current.path}/shared_preferences.json');
    expect(await destination.readAsString(), await source.readAsString());
    await destination.writeAsString('{"theme":"kawaii"}');
    await copyLegacyPreferences(old, current);
    expect(await destination.readAsString(), '{"theme":"kawaii"}');
    expect(await source.readAsString(), contains('saved'));
  });
}
