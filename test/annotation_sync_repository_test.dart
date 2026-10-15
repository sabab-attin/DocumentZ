import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/sync_graph.dart';
import 'package:documentz/data/sync_repository.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/features/annotations.dart';

class _Library implements ImportableLibrary {
  final book = const Book(
    id: 'local-copy',
    title: 'Local document',
    format: BookFormat.txt,
  );
  @override
  bool get persistsFiles => true;
  @override
  Future<List<Book>> listBooks() async => [book];
  @override
  Future<Uint8List> readDocument(Book book) async =>
      Uint8List.fromList(utf8.encode('The same original document.'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('sync merges saved marks into the matching local copy and never needs network for saving', () async {
    final local = DocumentMark(
      id: 'local-note',
      anchor: 'page:1',
      tool: MarkTool.note,
      text: 'Local note',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'annotations.v1.local-copy',
      jsonEncode([local.toJson()]),
    );
    final repository = SyncRepository(_Library());
    await repository.prepare();
    final fingerprint = repository.fingerprints.single;
    final remote = SyncGraph()
      ..capture('different-device-id', fingerprint, [
        DocumentMark(
          id: 'remote-note',
          anchor: 'page:1',
          tool: MarkTool.note,
          text: 'Remote note',
        ).toJson(),
      ]);
    await repository.accept(remote.export({fingerprint}), {
      fingerprint,
    }, () => true);
    final saved =
        jsonDecode(prefs.getString('annotations.v1.local-copy')!) as List;
    expect(saved.map((m) => m['text']).toSet(), {'Local note', 'Remote note'});
    final after = prefs.getString('annotations.v1.local-copy');
    await repository.accept(remote.export({fingerprint}), {
      fingerprint,
    }, () => true);
    expect(prefs.getString('annotations.v1.local-copy'), after);
    final store = AnnotationStore('local-copy');
    await store.load();
    await store.add(
      DocumentMark(
        anchor: 'page:1',
        tool: MarkTool.note,
        text: 'Saved without sync',
      ),
    );
    expect(store.saveFailed, isFalse);
    store.dispose();
  });
  test('cancelling sync cannot overwrite local annotations', () async {
    final mark = DocumentMark(
      id: 'keep',
      anchor: 'page:1',
      tool: MarkTool.note,
      text: 'Keep',
    );
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode([mark.toJson()]);
    await prefs.setString('annotations.v1.local-copy', raw);
    final repository = SyncRepository(_Library());
    await repository.prepare();
    await expectLater(
      repository.accept({}, repository.fingerprints, () => false),
      throwsA(isA<Exception>()),
    );
    expect(prefs.getString('annotations.v1.local-copy'), raw);
  });
  test('malformed geometry is rejected before writing annotations', () async {
    final repository = SyncRepository(_Library());
    await repository.prepare();
    final fingerprint = repository.fingerprints.single;
    final mark = DocumentMark(
      id: 'bad',
      anchor: 'page:1',
      tool: MarkTool.note,
    ).toJson()..['fontSize'] = -100;
    final remote = SyncGraph()..capture('remote', fingerprint, [mark]);
    await expectLater(
      repository.accept(remote.export({fingerprint}), {
        fingerprint,
      }, () => true),
      throwsFormatException,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('annotations.v1.local-copy'), isNull);
  });
  test(
    'interrupted apply is completed before the next sync captures local state',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final mark = DocumentMark(
        id: 'incoming',
        anchor: 'page:1',
        tool: MarkTool.note,
        text: 'Recovered',
      );
      final graph = SyncGraph()
        ..capture(
          'remote',
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          [mark.toJson()],
        );
      final fingerprint = graph.documents.keys.single;
      final result = graph.materialize(fingerprint);
      await prefs.setString(syncJournalKey, jsonEncode(graph.toJson()));
      await prefs.setString(
        'documentz.annotationSync.recovery.v1',
        jsonEncode([
          {
            'key': 'annotations.v1.local-copy',
            'before': '[]',
            'after': jsonEncode(result.marks),
            'localId': 'local-copy',
            'fingerprint': fingerprint,
            'aliases': result.aliases,
          },
        ]),
      );
      final reader = AnnotationStore('local-copy');
      await reader.load();
      expect(reader.marks.single.text, 'Recovered');
      reader.dispose();
      final repository = SyncRepository(_Library());
      await repository.load();
      expect(
        (jsonDecode(
          prefs.getString('annotations.v1.local-copy')!,
        ) as List).single['text'],
        'Recovered',
      );
      expect(prefs.getString('documentz.annotationSync.recovery.v1'), isNull);
    },
  );
}
