import 'dart:async';

import 'package:documentz/data/device_document_index.dart';
import 'package:documentz/data/device_documents_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const document = DeviceDocument(
    location: 'file:///one.pdf',
    name: 'one.pdf',
    folder: '/storage',
    size: 12,
    modified: 34,
  );
  const complete = DeviceScan([document], ['/storage'], []);

  test(
    'a saved index survives app restarts without crawling storage again',
    () async {
      final documents = List.generate(
        50000,
        (i) => DeviceDocument(
          location: 'file:///$i.pdf',
          name: '$i.pdf',
          folder: '/storage',
          size: i,
          modified: i,
        ),
      );
      final saved = DeviceIndexSnapshot(
        'same-permissions',
        DeviceScan(documents, ['/storage'], []),
        complete: true,
      );
      var scans = 0, reads = 0;
      DeviceDocumentIndex create() => DeviceDocumentIndex(
        read: () async {
          reads++;
          return saved;
        },
        write: (_) async {},
        quickScan: () async {
          scans++;
          return complete;
        },
        fullScan: () async {
          scans++;
          return complete;
        },
        onChanged: () {},
      );
      final index = create();
      expect(
        (await index.load('same-permissions')).documents,
        hasLength(50000),
      );
      for (var i = 0; i < 10; i++) {
        expect(
          (await index.load('same-permissions')).documents,
          same(documents),
        );
      }
      expect(
        (await create().load('same-permissions')).documents,
        hasLength(50000),
      );
      expect(scans, 0);
      expect(
        reads,
        2,
        reason: 'One metadata read per process; no scan on each screen change.',
      );
    },
  );

  test(
    'first view returns the OS index while a single full index builds',
    () async {
      final pending = Completer<DeviceScan>();
      DeviceIndexSnapshot? saved;
      var scans = 0;
      final index = DeviceDocumentIndex(
        read: () async => null,
        write: (value) async {
          saved = value;
        },
        quickScan: () async => complete,
        fullScan: () {
          scans++;
          return pending.future;
        },
        onChanged: () {},
      );
      expect((await index.load('scope')).documents, [document]);
      expect(index.indexing, isTrue);
      expect(saved!.complete, isFalse);
      final firstRefresh = index.load('scope', refresh: true);
      final secondRefresh = index.load('scope', refresh: true);
      pending.complete(complete);
      await Future.wait([firstRefresh, secondRefresh]);
      expect(scans, 1);
      expect(saved!.complete, isTrue);
      expect(index.indexing, isFalse);
    },
  );

  test(
    'a permission change cannot return the previous scope’s documents',
    () async {
      final pending = Completer<DeviceScan>();
      final index = DeviceDocumentIndex(
        read: () async => const DeviceIndexSnapshot(
          'old-permission',
          complete,
          complete: true,
        ),
        write: (_) async {},
        quickScan: () async => const DeviceScan([], [], []),
        fullScan: () => pending.future,
        onChanged: () {},
      );
      expect((await index.load('revoked')).documents, isEmpty);
      pending.complete(const DeviceScan([], [], []));
      await index.load('revoked', refresh: true);
    },
  );

  test('rename and delete update cached metadata without a new scan', () async {
    var scans = 0;
    DeviceIndexSnapshot? saved;
    final index = DeviceDocumentIndex(
      read: () async =>
          const DeviceIndexSnapshot('scope', complete, complete: true),
      write: (value) async {
        saved = value;
      },
      quickScan: () async => complete,
      fullScan: () async {
        scans++;
        return complete;
      },
      onChanged: () {},
    );
    await index.load('scope');
    const renamed = DeviceDocument(
      location: 'file:///renamed.pdf',
      name: 'renamed.pdf',
      folder: '/storage',
      size: 12,
      modified: 34,
    );
    await index.replace(document, renamed);
    expect((await index.load('scope')).documents.single.name, 'renamed.pdf');
    await index.replace(renamed, null);
    expect((await index.load('scope')).documents, isEmpty);
    expect(saved!.scan.documents, isEmpty);
    expect(scans, 0);
  });

  test('automatic download changes merge without another full scan', () async {
    var scans = 0, notifications = 0;
    final index = DeviceDocumentIndex(
      read: () async =>
          const DeviceIndexSnapshot('scope', complete, complete: true),
      write: (_) async {},
      quickScan: () async => complete,
      fullScan: () async {
        scans++;
        return complete;
      },
      onChanged: () => notifications++,
    );
    await index.load('scope');
    const download = DeviceDocument(
      location: 'file:///new.epub',
      name: 'new.epub',
      folder: '/storage/Download',
      size: 24,
      modified: 56,
    );
    const changes = DeviceScan([download], [], []);
    await index.applyChanges(changes, {document.location});
    expect(
      (await index.load('scope')).documents.single.location,
      download.location,
    );
    await index.applyChanges(changes, {document.location});
    expect(
      notifications,
      1,
      reason: 'An unchanged journal replay does not rebuild the UI.',
    );
    expect(scans, 0);
  });

  test('a change arriving during the initial scan cannot be overwritten by old results', () async {
    final pending = Completer<DeviceScan>();
    final index = DeviceDocumentIndex(
      read: () async => null,
      write: (_) async {},
      quickScan: () async => complete,
      fullScan: () => pending.future,
      onChanged: () {},
    );
    await index.load('scope');
    const download = DeviceDocument(
      location: 'file:///new.pdf',
      name: 'new.pdf',
      folder: '/storage/Download',
      size: 50,
      modified: 60,
    );
    await index.applyChanges(const DeviceScan([download], [], []), {
      document.location,
    });
    pending.complete(complete);
    await index.load('scope', refresh: true);
    expect(
      (await index.load('scope')).documents.single.location,
      download.location,
    );
  });
}
