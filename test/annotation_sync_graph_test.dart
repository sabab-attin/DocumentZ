import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/data/sync_graph.dart';

const fingerprint =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
Map<String, dynamic> mark(String text) => {
  'id': 'note',
  'text': text,
  'anchor': 'page:1',
  'group': '',
};
SyncGraph copy(SyncGraph graph) => SyncGraph(
  Map<String, dynamic>.from(jsonDecode(jsonEncode(graph.toJson())) as Map),
);
void apply(SyncGraph graph, String localId) {
  final result = graph.materialize(fingerprint);
  graph.applied(localId, fingerprint, result.aliases);
}

void main() {
  test('the same content fingerprint joins annotations despite different local IDs', () {
    final a = SyncGraph()
      ..capture('phone-import', fingerprint, [mark('Phone')]);
    final b = SyncGraph()
      ..capture('desktop-import', fingerprint, [
        {...mark('Computer'), 'id': 'other-note'},
      ]);
    a.merge(b.export({fingerprint}), {fingerprint});
    b.merge(a.export({fingerprint}), {fingerprint});
    expect(a.materialize(fingerprint).marks.map((m) => m['text']).toSet(), {
      'Phone',
      'Computer',
    });
    expect(
      syncCanonical(a.export({fingerprint})),
      syncCanonical(b.export({fingerprint})),
    );
  });
  test('concurrent edits survive in both directions and repeated sync is idempotent', () {
    final initial = SyncGraph()..capture('a', fingerprint, [mark('Original')]);
    final a = copy(initial), b = copy(initial);
    apply(a, 'a');
    apply(b, 'b');
    a.capture('a', fingerprint, [mark('Phone edit')]);
    b.capture('b', fingerprint, [mark('Computer edit')]);
    final left = a.export({fingerprint}), right = b.export({fingerprint});
    a.merge(right, {fingerprint});
    b.merge(left, {fingerprint});
    expect(a.materialize(fingerprint).marks.map((m) => m['text']).toSet(), {
      'Phone edit',
      'Computer edit',
    });
    expect(a.materialize(fingerprint).conflicts, 1);
    final once = syncCanonical(a.export({fingerprint}));
    a.merge(right, {fingerprint});
    expect(syncCanonical(a.export({fingerprint})), once);
    expect(
      syncCanonical(a.materialize(fingerprint).marks),
      syncCanonical(b.materialize(fingerprint).marks),
    );
    final displayed = a.materialize(fingerprint).marks;
    apply(a, 'a');
    a.capture('a', fingerprint, [displayed.first]);
    final kept = a.materialize(fingerprint).marks;
    expect(kept.length, 1);
    expect(kept.single['text'], displayed.first['text']);
    expect(a.materialize(fingerprint).conflicts, 0);
  });
  test('deletions do not resurrect when an older snapshot arrives', () {
    final a = SyncGraph()..capture('a', fingerprint, [mark('Original')]);
    final stale = copy(a).export({fingerprint});
    apply(a, 'a');
    a.capture('a', fingerprint, []);
    a.merge(stale, {fingerprint});
    expect(a.materialize(fingerprint).marks, isEmpty);
  });
  test('a concurrent edit is preserved against deletion', () {
    final initial = SyncGraph()..capture('a', fingerprint, [mark('Original')]);
    final a = copy(initial), b = copy(initial);
    apply(a, 'a');
    apply(b, 'b');
    a.capture('a', fingerprint, []);
    b.capture('b', fingerprint, [mark('Edited offline')]);
    a.merge(b.export({fingerprint}), {fingerprint});
    expect(a.materialize(fingerprint).marks.single['text'], 'Edited offline');
    expect(a.materialize(fingerprint).conflicts, 1);
    apply(a, 'a');
    a.capture('a', fingerprint, []);
    expect(a.materialize(fingerprint).marks, isEmpty);
  });
  test('malformed and cyclic histories cannot partly merge', () {
    final graph = SyncGraph()..capture('a', fingerprint, [mark('Keep')]);
    final before = syncCanonical(graph.toJson());
    final id = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
    expect(
      () => graph.merge(
        {
          fingerprint: {
            id: {
              'root': 'note',
              'parents': [id],
              'value': null,
            },
          },
        },
        {fingerprint},
      ),
      throwsFormatException,
    );
    expect(syncCanonical(graph.toJson()), before);
    expect(
      () => graph.merge({'wrong-document': {}}, {fingerprint}),
      throwsFormatException,
    );
    expect(syncCanonical(graph.toJson()), before);
  });
}
