import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cryptography/cryptography.dart';

import '../domain/services.dart';
import 'local_sync_models.dart';
import 'sync_crypto.dart';
import 'sync_connection_io.dart';
import 'android_lan_connection.dart';
import 'nearby_sync_io.dart';
import 'sync_graph.dart';
import 'sync_repository.dart';
import 'sync_wire.dart';

bool get localSyncAvailable => Platform.isAndroid || Platform.isWindows;
const _secretStore = FlutterSecureStorage(
  aOptions: AndroidOptions(
    storageNamespace: 'documentz_sync',
    resetOnError: false,
  ),
);
const _identityKey = 'documentz.localSync.identity.v1';

class _PlatformSyncSecrets implements SyncSecretStore {
  @override
  Future<String?> read() => _secretStore.read(key: _identityKey);
  @override
  Future<void> write(String value) =>
      _secretStore.write(key: _identityKey, value: value);
}

class LocalAnnotationSync extends ChangeNotifier {
  LocalAnnotationSync(
    ImportableLibrary library, {
    required this.approve,
    SyncSecretStore? secrets,
    SyncRepository? persistence,
    this.loopbackForTests = false,
  }) : data = persistence ?? SyncRepository(library),
       _credentials = secrets ?? _PlatformSyncSecrets();
  final SyncSecretStore _credentials;
  final bool loopbackForTests;
  final SyncRepository data;
  SyncPairApproval approve;
  final _known = <String, Map<String, dynamic>>{};
  final _found = <String, NearbySyncDevice>{};
  final _wires = <SyncWire>{};
  ServerSocket? _server;
  NearbySyncTransport? _nearby;
  bool _directNearby = true;
  bool get supportsNearby => Platform.isAndroid && !loopbackForTests;
  bool get usesNearby => supportsNearby && _directNearby;
  String? get nearbyPairingId => usesNearby && enabled ? id : null;
  void setNearbyMode(bool value) {
    if (enabled || busy) {
      return;
    }
    _directNearby = value;
    _notify();
  }

  RawDatagramSocket? _discovery;
  Timer? _beacon;
  bool _enabled = false, _disposed = false, busy = false;
  String id = '', name = '', status = 'Sync is off.', verification = '';
  String? pairingCode;
  List<String> addresses = [];
  DateTime? _pairUntil;
  int _epoch = 0;
  int _failures = 0;
  DateTime _failureWindow = DateTime.now();
  bool get enabled => _enabled;
  DateTime? get pairingExpiresAt => _pairUntil;
  List<SyncPeer> get peers => _known.entries
      .map(
        (e) => SyncPeer(
          e.key,
          e.value['name'] as String,
          e.value['address'] as String,
          e.value['lastSync'] as int? ?? 0,
        ),
      )
      .toList();
  List<NearbySyncDevice> get nearby => _found.values
      .where((d) => DateTime.now().difference(d.seen).inSeconds < 15)
      .toList();
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (id.isNotEmpty) {
      return;
    }
    final raw = await _credentials.read();
    if (raw != null) {
      final decoded = jsonDecode(raw) as Map;
      id = decoded['id'] as String;
      name = decoded['name'] as String;
      for (final entry in (decoded['peers'] as Map).entries) {
        _known[entry.key as String] = Map<String, dynamic>.from(
          entry.value as Map,
        );
      }
    } else {
      id = syncRandomId();
      name = Platform.isAndroid ? 'DocumentZ phone' : 'DocumentZ computer';
      await _saveIdentity();
    }
    _notify();
  }

  Future<void> _saveIdentity() =>
      _credentials.write(jsonEncode({'id': id, 'name': name, 'peers': _known}));
  Future<void> _guard(Future<void> Function() operation) async {
    if (busy || _disposed) {
      return;
    }
    busy = true;
    _notify();
    try {
      await operation();
    } catch (error) {
      data.loaded = false;
      status = error is FormatException
          ? error.message.toString()
          : error is SocketException
          ? 'The local connection was interrupted. Keep both apps open on the same Wi-Fi or hotspot. If a VPN or guest Wi-Fi blocks local devices, allow local-network access or use a phone hotspot.'
          : error is TimeoutException
          ? 'The other device did not respond in time. Keep DocumentZ open on both devices and retry.'
          : 'Sync failed before completion. Your local annotations are kept. Retry, or pair the devices again.';
    } finally {
      verification = '';
      busy = false;
      _notify();
    }
  }

  Future<void> start() => _guard(() async {
    if (_enabled) return;
    final epoch = _epoch;
    await initialize();
    if (!localSyncAvailable && !loopbackForTests) {
      throw const FormatException(
        'Local sync is available in the installed Android and Windows apps.',
      );
    }
    if (usesNearby) {
      await data.prepare(active: () => !_disposed && epoch == _epoch);
      final transport = _nearby ??= NearbySyncTransport();
      transport.onIncoming = (link) {
        if (!_enabled || busy || _disposed || _tooManyFailures()) {
          link.close();
          return;
        }
        unawaited(
          _guard(
            () => _serveWire(
              link.wire,
              'nearby:${link.peer}',
              nearbyPeer: link.peer,
            ),
          ),
        );
      };
      status = 'Preparing direct nearby connection…';
      _notify();
      await transport.start(id);
      if (_disposed || epoch != _epoch) {
        await transport.stop();
        return;
      }
      _enabled = true;
      addresses = [];
      _beacon = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_pairUntil != null && DateTime.now().isAfter(_pairUntil!)) {
          pairingCode = null;
          _pairUntil = null;
        }
        _notify();
      });
      status = 'Ready nearby. Scan a QR on one phone and approve matching numbers. No shared Wi-Fi or hotspot is needed.';
      return;
    }
    if (!loopbackForTests &&
        Platform.isAndroid &&
        await const MethodChannel('documentz/appearance')
                .invokeMethod<bool>('localNetworkAccess') !=
            true) {
      throw const FormatException(
        'Local network permission was not granted. Reading still works offline.',
      );
    }
    status = 'Preparing saved annotations…';
    _notify();
    await data.prepare(active: () => !_disposed && epoch == _epoch);
    if (_disposed || epoch != _epoch) {
      return;
    }
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final hosts = loopbackForTests
        ? ['127.0.0.1']
        : (interfaces.toList()..sort(
                (a, b) =>
                    syncInterfacePriority(a.name)
                        .compareTo(syncInterfacePriority(b.name)),
              ))
              .expand((i) => i.addresses)
              .where((a) => isSyncLocalAddress(a.address))
              .map((a) => a.address)
              .toSet()
              .toList();
    if (hosts.isEmpty) {
      throw const FormatException(
        'Connect both devices to the same Wi-Fi or hotspot first.',
      );
    }
    final server = await bindSyncServer(loopback: loopbackForTests);
    if (_disposed || epoch != _epoch) {
      await server.close();
      return;
    }
    _server = server;
    _enabled = true;
    addresses = hosts.map((host) => '$host:${server.port}').toList();
    server.listen(
      (socket) {
        if (!_enabled ||
            busy ||
            !isSyncLocalAddress(socket.remoteAddress.address) ||
            _tooManyFailures()) {
          socket.destroy();
          return;
        }
        unawaited(
          _guard(
            () => _serveWire(SyncWire(socket), socket.remoteAddress.address),
          ),
        );
      },
      onError: (Object _) {
        status = 'Local listener stopped. Turn sync off and on to retry.';
        _notify();
      },
    );
    if (!loopbackForTests) {
      await _discoveryLock(true);
      if (_disposed || epoch != _epoch) {
        await _discoveryLock(false);
        return;
      }
      try {
        final discovery = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          45832,
          reuseAddress: true,
        );
        if (_disposed || epoch != _epoch) {
          discovery.close();
          return;
        }
        _discovery = discovery;
        discovery.broadcastEnabled = true;
        discovery.listen(
          (event) {
            if (event != RawSocketEvent.read || !_enabled) {
              return;
            }
            final packet = discovery.receive();
            if (packet == null ||
                packet.data.length > 1024 ||
                !isSyncLocalAddress(packet.address.address)) {
              return;
            }
            try {
              final value = jsonDecode(utf8.decode(packet.data)) as Map;
              if (value['app'] != 'documentz-sync-1' ||
                  value['id'] == id ||
                  value['id'] is! String ||
                  !RegExp(r'^[a-f0-9]{32}$').hasMatch(value['id'] as String)) {
                return;
              }
              final port = value['port'];
              if (port is! int || port < 1 || port > 65535) {
                return;
              }
              if (_found.length >= 64 && !_found.containsKey(value['id'])) {
                return;
              }
              _found[value['id'] as String] = NearbySyncDevice(
                value['id'] as String,
                _label(value['name']),
                '${packet.address.address}:$port',
                DateTime.now(),
              );
              _notify();
            } catch (_) {
              /* Ignore unrelated LAN traffic. */
            }
          },
          onError: (Object _) {
            /* Manual address entry remains available. */
          },
        );
      } on SocketException {
        /* Discovery is optional; direct addresses still work. */
      }
    }
    _announce();
    _beacon = Timer.periodic(const Duration(seconds: 3), (_) {
      _found.removeWhere(
        (_, value) => DateTime.now().difference(value.seen).inSeconds > 15,
      );
      if (_pairUntil != null && DateTime.now().isAfter(_pairUntil!)) {
        pairingCode = null;
        _pairUntil = null;
      }
      _announce();
      _notify();
    });
    status = 'Ready. Sync stays on while you use DocumentZ.';
  });
  Future<void> _discoveryLock(bool enabled) async {
    if (Platform.isAndroid && !loopbackForTests) {
      try {
        await const MethodChannel('documentz/appearance')
            .invokeMethod<void>('localSyncDiscovery', {'enabled': enabled});
      } catch (_) {
        /* Discovery may fail; authenticated address entry still works. */
      }
    }
  }

  void _announce() {
    if (!_enabled || _server == null) {
      return;
    }
    try {
      _discovery?.send(
        utf8.encode(
          jsonEncode({
            'app': 'documentz-sync-1',
            'id': id,
            'name': name,
            'port': _server?.port ?? 45831,
          }),
        ),
        InternetAddress('255.255.255.255'),
        45832,
      );
    } on SocketException {
      /* Direct address entry remains available. */
    }
  }

  bool _tooManyFailures() {
    if (DateTime.now().difference(_failureWindow).inMinutes >= 1) {
      _failures = 0;
      _failureWindow = DateTime.now();
    }
    return _failures >= 5;
  }

  void allowPairing() {
    if (!_enabled || busy) {
      return;
    }
    pairingCode = syncEncode(syncRandomBytes(16));
    _pairUntil = DateTime.now().add(const Duration(minutes: 10));
    _notify();
  }

  Future<void> rename(String value) => _guard(() async {
    name = _label(value);
    await _saveIdentity();
    status = 'Device name updated.';
  });
  Future<void> forget(String peer) => _guard(() async {
    final previous = _known.remove(peer);
    try {
      await _saveIdentity();
    } catch (_) {
      if (previous != null) {
        _known[peer] = previous;
      }
      rethrow;
    }
    status =
        'Device unpaired on this device. Unpair it on the other device too.';
  });
  Future<void> stop() async {
    _epoch++;
    _enabled = false;
    pairingCode = null;
    _pairUntil = null;
    _beacon?.cancel();
    _beacon = null;
    _discovery?.close();
    _discovery = null;
    final server = _server;
    _server = null;
    await _nearby?.stop();
    for (final wire in _wires.toList()) {
      wire.close();
    }
    _found.clear();
    addresses = [];
    if (server != null) {
      await server.close();
    }
    await _discoveryLock(false);
    status = 'Sync is off. Saved annotations remain on this device.';
    _notify();
  }

  void _active([int? epoch]) {
    if (!_enabled || _disposed || (epoch != null && epoch != _epoch)) {
      throw const SocketException('Sync was stopped.');
    }
  }

  Future<Map<String, dynamic>> _hello(
    SimpleKeyPair key,
    String mode, {
    String binding = '',
  }) async => {
    'v': 1,
    'mode': mode,
    'id': id,
    'name': name,
    'key': syncEncode((await key.extractPublicKey()).bytes),
    'nonce': syncEncode(syncRandomBytes(32)),
    'port': _server?.port ?? 45831,
    if (binding.isNotEmpty) 'transportBinding': binding,
    'features': ['pair-sync-v1', 'saved-ack-v1'],
  };
  bool _supports(Map<String, dynamic> hello, String feature) {
    final features = hello['features'];
    return features is List && features.contains(feature);
  }

  void _checkBinding(SyncWire wire, Map<String, dynamic> hello) {
    validateSyncTransportBinding(wire, hello);
  }

  void _validateHello(Map<String, dynamic> hello) {
    if (hello['v'] != 1 ||
        hello['id'] is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(hello['id'] as String) ||
        hello['id'] == id ||
        hello['port'] is! int ||
        (hello['port'] as int) < 1 ||
        (hello['port'] as int) > 65535) {
      throw const FormatException('Invalid sync handshake.');
    }
    syncDecode(hello['key'] as String, 32);
    syncDecode(hello['nonce'] as String, 32);
  }

  Future<void> _rememberPeer(
    String peer,
    String label,
    String address,
    List<int> secret, {
    int lastSync = 0,
    required int epoch,
  }) async {
    _active(epoch);
    final before = _known[peer];
    _known[peer] = {
      'name': _label(label),
      'address': address,
      'secret': syncEncode(secret),
      'lastSync': lastSync,
    };
    try {
      await _saveIdentity();
    } catch (_) {
      if (before != null) {
        _known[peer] = before;
      } else {
        _known.remove(peer);
      }
      rethrow;
    }
  }

  Future<void> _serveWire(
    SyncWire wire,
    String remoteAddress, {
    String? nearbyPeer,
  }) async {
    final epoch = _epoch;
    _wires.add(wire);
    final deadline = Timer(
      wire.binding.isEmpty
          ? const Duration(seconds: 120)
          : const Duration(minutes: 10),
      wire.close,
    );
    try {
      final raw = await wire.read();
      final proof = raw.remove('proof') as String;
      _validateHello(raw);
      _checkBinding(wire, raw);
      if (nearbyPeer != null && raw['id'] != nearbyPeer) {
        throw const FormatException(
          'The nearby device identity does not match.',
        );
      }
      final peerId = raw['id'] as String;
      final mode = raw['mode'];
      final List<int> secret;
      if (mode == 'pair' &&
          pairingCode != null &&
          _pairUntil != null &&
          DateTime.now().isBefore(_pairUntil!)) {
        secret = syncDecode(pairingCode!, 16);
      } else if (mode == 'sync' && _known.containsKey(peerId)) {
        secret = syncDecode(_known[peerId]!['secret'] as String, 32);
      } else {
        throw const FormatException(
          'Pairing is closed or this device is not paired.',
        );
      }
      await verifySyncProof(secret, {'role': 'client', 'hello': raw}, proof);
      await wire.authorize();
      if (mode == 'pair') {
        pairingCode = null;
        _pairUntil = null;
      }
      _active(epoch);
      final key = await X25519().newKeyPair();
      final reply = await _hello(key, mode as String, binding: wire.binding);
      final transcript = {'client': raw, 'server': reply};
      await wire.write({
        ...reply,
        'proof': await syncProof(secret, {'role': 'server', ...transcript}),
      });
      final session = await makeSyncCipher(
        localKey: key,
        remoteKey: raw['key'] as String,
        secret: secret,
        transcript: transcript,
        client: false,
      );
      final cipher = session.cipher;
      if ((await wire.receive(cipher))['kind'] != 'confirm') {
        throw const FormatException('Invalid sync confirmation.');
      }
      if (mode == 'pair') {
        verification = session.verification;
        status = 'Confirm the pairing request.';
        _notify();
        if (!await approve(
          _label(raw['name']),
          verification,
        ).timeout(const Duration(seconds: 60))) {
          throw const FormatException('Pairing was declined.');
        }
        _active(epoch);
        final pairedSecret = syncRandomBytes(32);
        await _rememberPeer(
          peerId,
          _label(raw['name']),
          remoteAddress.startsWith('nearby:')
              ? remoteAddress
              : '$remoteAddress:${raw['port']}',
          pairedSecret,
          epoch: epoch,
        );
        await wire.send(cipher, {
          'kind': 'paired',
          'secret': syncEncode(pairedSecret),
        });
        if ((await wire.receive(cipher))['kind'] != 'stored') {
          throw const FormatException('Pairing was interrupted. Pair again.');
        }
        await wire.send(cipher, {'kind': 'pair-complete'});
        status = 'Paired. Select Sync now to exchange saved annotations.';
        if (_supports(raw, 'pair-sync-v1')) {
          await _exchangeServer(
            wire,
            cipher,
            raw,
            remoteAddress,
            pairedSecret,
            epoch,
          );
        }
      } else {
        await _exchangeServer(wire, cipher, raw, remoteAddress, secret, epoch);
      }
    } catch (_) {
      _failures++;
      rethrow;
    } finally {
      deadline.cancel();
      _wires.remove(wire);
      wire.close();
    }
  }

  Future<void> pairNearby(String peer, String code) => _guard(() async {
    if (!usesNearby || !RegExp(r'^[a-f0-9]{32}$').hasMatch(peer)) {
      throw const FormatException(
        'Choose Nearby phones and enable sync on both updated Android phones.',
      );
    }
    await _connect('nearby:$peer', code: code, expectedId: peer);
  });
  Future<void> pair(String address, String code) =>
      _guard(() => _connect(address, code: code));
  Future<void> pairAny(List<String> addresses, String code) => _guard(() async {
    if (addresses.isEmpty) {
      throw const FormatException('The invitation has no local addresses.');
    }
    await _connect(addresses.first, code: code, alternatives: addresses);
  });
  Future<void> syncWith(String peerId, {String? address}) => _guard(() async {
    final peer = _known[peerId];
    if (peer == null) {
      throw const FormatException('Pair this device first.');
    }
    if (usesNearby) {
      await _connect('nearby:$peerId', expectedId: peerId);
      return;
    }
    if ((peer['address'] as String).startsWith('nearby:') && address == null) {
      throw const FormatException(
        'Choose Nearby phones to sync with this device.',
      );
    }
    await _connect(
      address ?? _found[peerId]?.address ?? (peer['address'] as String),
      expectedId: peerId,
      alternatives: address != null
          ? [address]
          : [
              if (_found[peerId] != null) _found[peerId]!.address,
              peer['address'] as String,
            ],
    );
  });
  Future<void> _connect(
    String address, {
    String? code,
    String? expectedId,
    List<String>? alternatives,
  }) async {
    final epoch = _epoch;
    _active(epoch);
    final mode = code == null ? 'sync' : 'pair';
    final secret = code == null
        ? syncDecode(_known[expectedId]!['secret'] as String, 32)
        : syncDecode(code.trim(), 16);
    status = mode == 'pair'
        ? 'Authenticating pairing…'
        : 'Connecting securely…';
    _notify();
    final SyncWire wire;
    final String connectedAddress;
    if (address.startsWith('nearby:')) {
      if (!usesNearby || _nearby == null) {
        throw const FormatException(
          'Enable Nearby phones on both devices first.',
        );
      }
      status = 'Finding the other phone nearby…';
      _notify();
      final link = await _nearby!.connect(address.substring(7));
      wire = link.wire;
      connectedAddress = address;
    } else {
      final connected = await connectSyncAddresses(
        alternatives ?? [address],
        localAddresses: addresses,
        connector: Platform.isAndroid && !loopbackForTests
            ? connectAndroidLan
            : null,
        active: () => _enabled && !_disposed && epoch == _epoch,
        onAttempt: (attempt, total) {
          status = 'Connecting to local address $attempt of $total…';
          _notify();
        },
      );
      wire = SyncWire(connected.socket);
      connectedAddress = connected.address;
    }
    _wires.add(wire);
    final deadline = Timer(
      wire.binding.isEmpty
          ? const Duration(seconds: 120)
          : const Duration(minutes: 10),
      wire.close,
    );
    try {
      _active(epoch);
      final key = await X25519().newKeyPair();
      final hello = await _hello(key, mode, binding: wire.binding);
      await wire.write({
        ...hello,
        'proof': await syncProof(secret, {'role': 'client', 'hello': hello}),
      });
      final reply = await wire.read();
      final proof = reply.remove('proof') as String;
      _validateHello(reply);
      _checkBinding(wire, reply);
      if (reply['mode'] != mode ||
          (expectedId != null && reply['id'] != expectedId)) {
        throw const FormatException(
          'The connected device identity does not match.',
        );
      }
      final transcript = {'client': hello, 'server': reply};
      await verifySyncProof(secret, {'role': 'server', ...transcript}, proof);
      await wire.authorize();
      final session = await makeSyncCipher(
        localKey: key,
        remoteKey: reply['key'] as String,
        secret: secret,
        transcript: transcript,
        client: true,
      );
      verification = session.verification;
      _notify();
      final cipher = session.cipher;
      await wire.send(cipher, {'kind': 'confirm'});
      final peerId = reply['id'] as String;
      if (mode == 'pair') {
        status =
            'Compare the verification number and approve on the other device.';
        _notify();
        final paired = await wire.receive(cipher);
        if (paired['kind'] != 'paired') {
          throw const FormatException('Pairing was not accepted.');
        }
        await _rememberPeer(
          peerId,
          _label(reply['name']),
          connectedAddress,
          syncDecode(paired['secret'] as String, 32),
          epoch: epoch,
        );
        await wire.send(cipher, {'kind': 'stored'});
        if ((await wire.receive(cipher))['kind'] != 'pair-complete') {
          throw const FormatException('Pairing was interrupted. Pair again.');
        }
        status = 'Paired. Select Sync now to exchange saved annotations.';
        if (_supports(reply, 'pair-sync-v1')) {
          await _exchangeClient(
            wire,
            cipher,
            reply,
            connectedAddress,
            syncDecode(paired['secret'] as String, 32),
            epoch,
          );
        }
      } else {
        await _exchangeClient(
          wire,
          cipher,
          reply,
          connectedAddress,
          secret,
          epoch,
        );
      }
    } finally {
      deadline.cancel();
      _wires.remove(wire);
      wire.close();
    }
  }

  Future<void> _exchangeServer(
    SyncWire wire,
    SyncCipher cipher,
    Map<String, dynamic> hello,
    String remoteAddress,
    List<int> secret,
    int epoch,
  ) async {
    status = 'Comparing saved annotations…';
    _notify();
    await data.prepare(active: () => _enabled && !_disposed && epoch == _epoch);
    await wire.send(cipher, {
      'kind': 'documents',
      'documents': data.fingerprints.toList(),
    });
    final selection = await wire.receive(cipher);
    if (selection['kind'] != 'exchange') {
      throw const FormatException('Invalid sync exchange.');
    }
    final common = _common(selection['documents'], data.fingerprints);
    await _accept(
      Map<String, dynamic>.from(selection['annotations'] as Map),
      common,
      epoch,
    );
    final snapshot = await data.snapshot(common);
    final digest = await syncSnapshotDigest(snapshot);
    await wire.send(cipher, {
      'kind': 'merged',
      'annotations': snapshot,
      'digest': digest,
    });
    final saved = await wire.receive(cipher);
    if (saved['kind'] != 'saved' ||
        (_supports(hello, 'saved-ack-v1') && saved['digest'] != digest)) {
      throw const FormatException(
        'The other device did not confirm the same saved annotations. Retry sync safely.',
      );
    }
    _active(epoch);
    await _rememberPeer(
      hello['id'] as String,
      _label(hello['name']),
      remoteAddress.startsWith('nearby:')
          ? remoteAddress
          : '$remoteAddress:${hello['port']}',
      secret,
      epoch: epoch,
      lastSync: DateTime.now().millisecondsSinceEpoch,
    );
    if (_supports(hello, 'saved-ack-v1')) {
      await wire.send(cipher, {'kind': 'sync-complete', 'digest': digest});
    }
    status = _summary(common.length);
  }

  Future<void> _exchangeClient(
    SyncWire wire,
    SyncCipher cipher,
    Map<String, dynamic> hello,
    String address,
    List<int> secret,
    int epoch,
  ) async {
    status = 'Exchanging saved annotations…';
    _notify();
    await data.prepare(active: () => _enabled && !_disposed && epoch == _epoch);
    final manifest = await wire.receive(cipher);
    if (manifest['kind'] != 'documents') {
      throw const FormatException('Invalid document manifest.');
    }
    final common = _common(manifest['documents'], data.fingerprints);
    await wire.send(cipher, {
      'kind': 'exchange',
      'documents': common.toList(),
      'annotations': await data.snapshot(common),
    });
    final merged = await wire.receive(cipher);
    if (merged['kind'] != 'merged') {
      throw const FormatException('Invalid merged annotations.');
    }
    await _accept(
      Map<String, dynamic>.from(merged['annotations'] as Map),
      common,
      epoch,
    );
    final digest = await syncSnapshotDigest(await data.snapshot(common));
    if (_supports(hello, 'saved-ack-v1') && merged['digest'] != digest) {
      throw const FormatException(
        'The saved annotation sets do not match yet. Retry sync safely.',
      );
    }
    await wire.send(cipher, {'kind': 'saved', 'digest': digest});
    if (_supports(hello, 'saved-ack-v1')) {
      final complete = await wire.receive(cipher);
      if (complete['kind'] != 'sync-complete' || complete['digest'] != digest) {
        throw const FormatException(
          'The other device did not confirm completion. Retry sync safely.',
        );
      }
    }
    _active(epoch);
    await _rememberPeer(
      hello['id'] as String,
      _label(hello['name']),
      address,
      secret,
      epoch: epoch,
      lastSync: DateTime.now().millisecondsSinceEpoch,
    );
    status = _summary(common.length);
  }

  Future<void> _accept(
    Map<String, dynamic> annotations,
    Set<String> common,
    int epoch,
  ) async {
    final size = await syncEncodedSize(annotations);
    if (size > syncPayloadLimit) {
      throw const FormatException('Annotations exceed the 16 MB sync limit.');
    }
    await data.accept(
      annotations,
      common,
      () => _enabled && !_disposed && epoch == _epoch,
    );
  }

  Set<String> _common(Object? raw, Set<String> available) {
    if (raw is! List ||
        raw.length > 5000 ||
        raw.any(
          (v) => v is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(v),
        )) {
      throw const FormatException('Invalid document manifest.');
    }
    return raw.cast<String>().toSet().intersection(available);
  }

  String _summary(int count) => count == 0
      ? 'No matching documents. Import the same original files on both devices, then retry.'
      : 'Synced $count documents.${data.conflicts > 0 ? ' Concurrent edits were preserved; review overlapping marks.' : ''}';
  static String _label(Object? value) {
    final clean = value is String
        ? value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim()
        : '';
    return clean.isEmpty
        ? 'DocumentZ device'
        : clean.substring(0, clean.length > 48 ? 48 : clean.length);
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
