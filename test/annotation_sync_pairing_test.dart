import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/local_annotation_sync_io.dart';
import 'package:documentz/data/local_sync_models.dart';
import 'package:documentz/data/sync_crypto.dart';
import 'package:documentz/data/sync_repository.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';
import 'package:documentz/features/annotations.dart';

class _Secrets implements SyncSecretStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class _Books implements ImportableLibrary {
  _Books(this.id);
  final String id;
  @override
  bool get persistsFiles => true;
  @override
  Future<List<Book>> listBooks() async => [
    Book(id: id, title: id, format: BookFormat.txt),
  ];
  @override
  Future<Uint8List> readDocument(Book book) async => Uint8List.fromList(
    utf8.encode('Exactly the same document on both devices.'),
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> settled(LocalAnnotationSync sync) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (sync.busy && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(sync.busy, isFalse, reason: sync.status);
}

void main() {
  test('real loopback pairing requires approval, syncs both directions and respects unpairing', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'annotations.v1.phone-copy',
      jsonEncode([
        DocumentMark(
          id: 'phone-note',
          anchor: 'page:1',
          tool: MarkTool.note,
          text: 'Phone',
        ).toJson(),
      ]),
    );
    await prefs.setString(
      'annotations.v1.computer-copy',
      jsonEncode([
        DocumentMark(
          id: 'computer-note',
          anchor: 'page:1',
          tool: MarkTool.note,
          text: 'Computer',
        ).toJson(),
      ]),
    );
    final phoneBooks = _Books('phone-copy'),
        computerBooks = _Books('computer-copy');
    final phoneSecrets = _Secrets(), computerSecrets = _Secrets();
    final bystanderSecrets = _Secrets();
    final bystanderBooks = _Books('bystander-copy');
    final bystander = LocalAnnotationSync(
      bystanderBooks,
      secrets: bystanderSecrets,
      persistence: SyncRepository(
        bystanderBooks,
        storageKey: 'test.bystander.journal',
      ),
      loopbackForTests: true,
      approve: (_, verification) async =>
          throw StateError('Bystander must never receive pairing'),
    );
    final bystanderMarks = jsonEncode([
      DocumentMark(
        id: 'private-note',
        anchor: 'page:1',
        tool: MarkTool.note,
        text: 'Private',
      ).toJson(),
    ]);
    await prefs.setString('annotations.v1.bystander-copy', bystanderMarks);
    var approved = 0;
    String? shownVerification;
    final phone = LocalAnnotationSync(
      phoneBooks,
      secrets: phoneSecrets,
      persistence: SyncRepository(phoneBooks, storageKey: 'test.phone.journal'),
      loopbackForTests: true,
      approve: (name, verification) async {
        approved++;
        shownVerification = verification;
        return true;
      },
    );
    final computer = LocalAnnotationSync(
      computerBooks,
      secrets: computerSecrets,
      persistence: SyncRepository(
        computerBooks,
        storageKey: 'test.computer.journal',
      ),
      loopbackForTests: true,
      approve: (name, verification) async => true,
    );
    addTearDown(() async {
      await bystander.stop();
      bystander.dispose();
      await phone.stop();
      await computer.stop();
      phone.dispose();
      computer.dispose();
    });
    await bystander.start();
    expect(bystander.enabled, isTrue, reason: bystander.status);
    final bystanderIdentity = bystanderSecrets.value;
    await phone.start();
    await computer.start();
    expect(phone.enabled, isTrue, reason: phone.status);
    expect(computer.enabled, isTrue, reason: computer.status);
    phone.allowPairing();
    final code = phone.pairingCode!;
    await computer.pair(phone.addresses.first, syncEncode(syncRandomBytes(16)));
    await settled(phone);
    expect(approved, 0);
    expect(phone.peers, isEmpty);
    expect(computer.peers, isEmpty);
    await computer.pair(phone.addresses.first, code);
    await settled(phone);
    expect(approved, 1);
    expect(shownVerification, matches(RegExp(r'^[0-9]{5} [0-9]{5}$')));
    expect(phone.peers.single.id, computer.id);
    expect(computer.peers.single.id, phone.id);
    expect(phone.pairingCode, isNull);
    await computer.syncWith(phone.id);
    await settled(phone);
    expect(
      computer.status,
      startsWith('Synced 1 documents.'),
      reason: computer.status,
    );
    for (final id in ['phone-copy', 'computer-copy']) {
      final marks = jsonDecode(prefs.getString('annotations.v1.$id')!) as List;
      expect(marks.map((m) => m['text']).toSet(), {'Phone', 'Computer'});
    }
    expect(bystander.peers, isEmpty);
    expect(bystanderSecrets.value, bystanderIdentity);
    expect(prefs.getString('annotations.v1.bystander-copy'), bystanderMarks);
    // A known peer ID from elsewhere cannot authorize another device.
    await bystander.syncWith(phone.id, address: phone.addresses.first);
    expect(bystander.status, isNot(startsWith('Synced')));
    expect(prefs.getString('annotations.v1.bystander-copy'), bystanderMarks);
    final before = prefs.getString('annotations.v1.phone-copy');
    await phone.forget(computer.id);
    await computer.syncWith(phone.id);
    await settled(phone);
    expect(computer.status, isNot(startsWith('Synced')));
    expect(prefs.getString('annotations.v1.phone-copy'), before);
    expect(phone.peers, isEmpty);
    await phone.stop();
    expect(phone.enabled, isFalse);
    expect(phone.addresses, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 45)));

  test('stopping during approval cannot create a trusted peer', () async {
    SharedPreferences.setMockInitialValues({});
    final entered = Completer<void>();
    final approval = Completer<bool>();
    final hostBooks = _Books('host'), guestBooks = _Books('guest');
    final host = LocalAnnotationSync(
      hostBooks,
      secrets: _Secrets(),
      persistence: SyncRepository(hostBooks, storageKey: 'cancel.host'),
      loopbackForTests: true,
      approve: (_, verification) {
        entered.complete();
        return approval.future;
      },
    );
    final guest = LocalAnnotationSync(
      guestBooks,
      secrets: _Secrets(),
      persistence: SyncRepository(guestBooks, storageKey: 'cancel.guest'),
      loopbackForTests: true,
      approve: (_, verification) async => false,
    );
    addTearDown(() async {
      if (!approval.isCompleted) approval.complete(false);
      await host.stop();
      await guest.stop();
      host.dispose();
      guest.dispose();
    });
    await host.start();
    await guest.start();
    expect(host.enabled, isTrue, reason: host.status);
    expect(guest.enabled, isTrue, reason: guest.status);
    host.allowPairing();
    final pairing = guest.pair(host.addresses.first, host.pairingCode!);
    await entered.future.timeout(const Duration(seconds: 10));
    await host.stop();
    approval.complete(true);
    await pairing;
    await settled(host);
    expect(host.peers, isEmpty);
    expect(guest.peers, isEmpty);
    await host.start();
    expect(host.enabled, isTrue, reason: host.status);
    expect(host.peers, isEmpty);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
