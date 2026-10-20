import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cryptography/cryptography.dart';
import 'package:documentz/data/local_annotation_sync_io.dart';
import 'package:documentz/data/local_sync_models.dart';
import 'package:documentz/data/sync_connection_io.dart';
import 'package:documentz/data/sync_graph.dart';
import 'package:documentz/data/sync_crypto.dart';
import 'package:documentz/data/sync_repository.dart';
import 'package:documentz/data/sync_wire.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/features/annotations.dart';

class _Secrets implements SyncSecretStore {
  String? raw;
  @override
  Future<String?> read() async => raw;
  @override
  Future<void> write(String value) async {
    raw = value;
  }
}

class _Library implements ImportableLibrary {
  _Library(this.device);
  final String device;
  static const formats = [BookFormat.pdf, BookFormat.epub, BookFormat.markdown];
  @override
  bool get persistsFiles => true;
  @override
  Future<List<Book>> listBooks() async => [
    for (final format in formats)
      Book(id: '$device-${format.name}', title: format.name, format: format),
    Book(
      id: '$device-private',
      title: 'Different original',
      format: BookFormat.txt,
    ),
  ];
  @override
  Future<Uint8List> readDocument(Book book) async => Uint8List.fromList(
    utf8.encode(
      book.id.endsWith('-private')
          ? 'Private original on $device'
          : '# Shared original\nIdentical bytes on both devices.\n',
    ),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle(LocalAnnotationSync engine) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (engine.busy && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(engine.busy, isFalse, reason: engine.status);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'listener collisions stay inside the installer firewall range',
    () async {
      final attempted = <int>[];
      final server = await bindSyncServer(
        binder: (address, port) async {
          attempted.add(port);
          if (port < 45833) throw const SocketException('Already in use');
          return ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        },
      );
      await server.close();
      expect(attempted, [45831, 45832, 45833]);
      attempted.clear();
      await expectLater(
        bindSyncServer(
          binder: (address, port) async {
            attempted.add(port);
            throw const SocketException('Already in use');
          },
        ),
        throwsA(isA<SocketException>()),
      );
      expect(attempted, List.generate(9, (i) => 45831 + i));
    },
  );

  test('a refused address falls back to the next address and remembers the actual endpoint', () async {
    final closed = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final refused = '127.0.0.1:${closed.port}';
    final live = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    await closed.close();
    final accepted = <Socket>[];
    live.listen(accepted.add);
    Socket? connected;
    addTearDown(() async {
      connected?.destroy();
      for (final socket in accepted) {
        socket.destroy();
      }
      await live.close();
    });
    final attempts = <int>[];
    final result = await connectSyncAddresses(
      [refused, '127.0.0.1:${live.port}'],
      localAddresses: [],
      active: () => true,
      onAttempt: (attempt, total) {
        attempts.add(attempt);
      },
    );
    connected = result.socket;
    expect(attempts, [1, 2]);
    expect(result.address, '127.0.0.1:${live.port}');
  });

  test('invalid, public and oversized endpoint lists are rejected before connecting', () async {
    for (final candidates in <List<String>>[
      [],
      ['example.com:80'],
      ['8.8.8.8:80'],
      ['192.168.0.2:0'],
      ['127.0.0.1:45831', 'https://example.com'],
      List.filled(9, '127.0.0.1:1'),
    ]) {
      var attempts = 0;
      await expectLater(
        connectSyncAddresses(
          candidates,
          localAddresses: [],
          active: () => true,
          onAttempt: (_, _) {
            attempts++;
          },
        ),
        throwsFormatException,
      );
      expect(attempts, 0);
    }
    await expectLater(
      connectSyncAddresses(
        ['127.0.0.1:1'],
        localAddresses: [],
        active: () => false,
      ),
      throwsA(isA<SocketException>()),
    );
    expect(
      syncInterfacePriority('wlan0'),
      lessThan(syncInterfacePriority('tun0')),
    );
  });

  test('approved pairing also saves all mark fields both ways for PDF, EPUB and Markdown', () async {
    final prefs = await SharedPreferences.getInstance();
    final picture = base64Encode(img.encodePng(img.Image(width: 2, height: 2)));
    final expected = <String, Map<String, dynamic>>{};
    for (final device in ['a', 'b']) {
      final marks = [
        for (final tool in MarkTool.values.where(
          (tool) => tool != MarkTool.browse && tool != MarkTool.eraser,
        ))
          DocumentMark(
            id: '$device-${tool.name}',
            anchor: 'page:1',
            tool: tool,
            text:
                '**Markdown note**\nÙ…Ø±Ø­Ø¨Ø§ â€” à¦¬à¦¾à¦‚à¦²à¦¾ â€” Milena',
            locked: true,
            points: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
            rects: const [Rect.fromLTWH(0.1, 0.2, 0.3, 0.4)],
            quote: 'Original quotation',
            block: 'chapter#paragraph',
            start: 2,
            end: 12,
            font: 'serif',
            fontSize: 21,
            color: 0xff123456,
            width: 2.5,
            rotation: 90,
            geometryVersion: 1,
            attachments: tool == MarkTool.image ? [picture] : const [],
          ).toJson(),
      ];
      for (final mark in marks) {
        expected[mark['id'] as String] = mark;
      }
      for (final format in _Library.formats) {
        await prefs.setString(
          'annotations.v1.$device-${format.name}',
          jsonEncode(marks),
        );
      }
      await prefs.setString('annotations.v1.$device-private', '[]');
    }
    LocalAnnotationSync engine(String device, SyncPairApproval approve) {
      final library = _Library(device);
      return LocalAnnotationSync(
        library,
        approve: approve,
        secrets: _Secrets(),
        persistence: SyncRepository(
          library,
          storageKey: 'test.$device.journal',
        ),
        loopbackForTests: true,
      );
    }

    var approvals = 0;
    final host = engine('a', (_, _) async {
      approvals++;
      return true;
    });
    final guest = engine('b', (_, _) async => false);
    addTearDown(() async {
      await host.stop();
      await guest.stop();
      host.dispose();
      guest.dispose();
    });
    await host.start();
    await guest.start();
    expect(host.enabled && guest.enabled, isTrue);
    host.allowPairing();
    final unavailable = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final unavailableAddress = '127.0.0.1:${unavailable.port}';
    await unavailable.close();
    await guest.pairAny([
      unavailableAddress,
      ...host.addresses,
    ], host.pairingCode!);
    await _settle(host);
    expect(approvals, 1);
    expect(host.status, startsWith('Synced 3 documents.'), reason: host.status);
    expect(
      guest.status,
      startsWith('Synced 3 documents.'),
      reason: guest.status,
    );
    expect(host.peers.single.lastSync, greaterThan(0));
    expect(guest.peers.single.lastSync, greaterThan(0));
    expect(guest.peers.single.address, host.addresses.single);
    for (final device in ['a', 'b']) {
      for (final format in _Library.formats) {
        final marks = jsonDecode(
          prefs.getString('annotations.v1.$device-${format.name}')!,
        ) as List;
        expect(
          syncCanonical({for (final mark in marks) mark['id']: mark}),
          syncCanonical(expected),
        );
      }
      expect(prefs.getString('annotations.v1.$device-private'), '[]');
    }
    // Repeating sync must not duplicate any mark, and the reverse direction works.
    final before = prefs.getString('annotations.v1.a-markdown');
    await host.syncWith(guest.id);
    await _settle(guest);
    expect(host.status, startsWith('Synced 3 documents.'), reason: host.status);
    expect(prefs.getString('annotations.v1.a-markdown'), before);
    final common = host.data.fingerprints.intersection(guest.data.fingerprints);
    expect(
      await syncSnapshotDigest(await host.data.snapshot(common)),
      await syncSnapshotDigest(await guest.data.snapshot(common)),
    );
    // Later edits and removals also converge, without resurrecting bookmarks.
    final revised =
        (jsonDecode(prefs.getString('annotations.v1.a-markdown')!) as List)
            .where((mark) => mark['id'] != 'a-bookmark')
            .map(
              (mark) => mark['id'] == 'a-note'
                  ? {...mark as Map, 'text': 'Revised note'}
                  : mark,
            )
            .toList();
    await prefs.setString('annotations.v1.a-markdown', jsonEncode(revised));
    await guest.syncWith(host.id);
    await _settle(host);
    expect(
      guest.status,
      startsWith('Synced 3 documents.'),
      reason: guest.status,
    );
    for (final device in ['a', 'b']) {
      final marks = jsonDecode(
        prefs.getString('annotations.v1.$device-markdown')!,
      ) as List;
      expect(marks.any((mark) => mark['id'] == 'a-bookmark'), isFalse);
      expect(
        marks.singleWhere((mark) => mark['id'] == 'a-note')['text'],
        'Revised note',
      );
    }
  }, timeout: const Timeout(Duration(seconds: 60)));

  for (final wrongDigest in [false, true]) {
    test(
      'missing or mismatched final acknowledgement cannot report sync success: $wrongDigest',
      () async {
        final library = _Library('guest');
        final guest = LocalAnnotationSync(
          library,
          approve: (_, _) async => false,
          secrets: _Secrets(),
          loopbackForTests: true,
          persistence: SyncRepository(library, storageKey: 'test.ack.journal'),
        );
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final port = server.port;
        addTearDown(() async {
          await guest.stop();
          guest.dispose();
          await server.close();
        });
        await guest.start();
        final code = syncRandomBytes(16);
        final serving = () async {
          final wire = SyncWire(await server.first);
          try {
            final client = await wire.read();
            final proof = client.remove('proof') as String;
            await verifySyncProof(code, {
              'role': 'client',
              'hello': client,
            }, proof);
            final key = await X25519().newKeyPair();
            final hello = <String, dynamic>{
              'v': 1,
              'mode': 'pair',
              'id': 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              'name': 'Acknowledgement test',
              'port': port,
              'key': syncEncode((await key.extractPublicKey()).bytes),
              'nonce': syncEncode(syncRandomBytes(32)),
              'features': ['pair-sync-v1', 'saved-ack-v1'],
            };
            final transcript = {'client': client, 'server': hello};
            await wire.write({
              ...hello,
              'proof': await syncProof(code, {'role': 'server', ...transcript}),
            });
            final session = await makeSyncCipher(
              localKey: key,
              remoteKey: client['key'] as String,
              secret: code,
              transcript: transcript,
              client: false,
            );
            final cipher = session.cipher;
            expect((await wire.receive(cipher))['kind'], 'confirm');
            await wire.send(cipher, {
              'kind': 'paired',
              'secret': syncEncode(syncRandomBytes(32)),
            });
            expect((await wire.receive(cipher))['kind'], 'stored');
            await wire.send(cipher, {'kind': 'pair-complete'});
            final common = guest.data.fingerprints;
            await wire.send(cipher, {
              'kind': 'documents',
              'documents': common.toList(),
            });
            expect((await wire.receive(cipher))['kind'], 'exchange');
            final snapshot = await guest.data.snapshot(common);
            await wire.send(cipher, {
              'kind': 'merged',
              'annotations': snapshot,
              'digest': await syncSnapshotDigest(snapshot),
            });
            expect((await wire.receive(cipher))['kind'], 'saved');
            if (wrongDigest) {
              await wire.send(cipher, {
                'kind': 'sync-complete',
                'digest': 'incorrect',
              });
            }
          } finally {
            wire.close();
          }
        }();
        await guest.pair('127.0.0.1:$port', syncEncode(code));
        await serving;
        expect(guest.status, isNot(startsWith('Synced')), reason: guest.status);
        expect(guest.peers.single.lastSync, 0);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}
