import 'dart:async';

import 'package:flutter/services.dart';

import 'sync_wire.dart';

/// A bounded byte stream over Nearby. Only the ordinary authenticated sync
/// protocol sees these bytes; native discovery never receives document data.
class NearbySyncTransport {
  static const channel = MethodChannel('documentz/nearby');
  final _links = <String, NearbySyncLink>{};
  final _closedLinks = <String>{};
  void Function(NearbySyncLink)? onIncoming;
  bool _started = false;

  Future<void> start(String id) async {
    channel.setMethodCallHandler(_event);
    try {
      await channel.invokeMethod<void>('start', {'id': id});
      _started = true;
    } on PlatformException catch (error) {
      throw FormatException(
        error.message ?? 'Could not start direct nearby sync.',
      );
    } on MissingPluginException {
      throw const FormatException(
        'Install the updated Android app on both phones to use direct sync.',
      );
    }
  }

  NearbySyncLink _link(Map<Object?, Object?> data) {
    final token = data['link'] as String;
    return _links.putIfAbsent(
      token,
      () => NearbySyncLink._(
        token,
        data['peer'] as String,
        data['binding'] as String,
        () {
          _links.remove(token);
        },
      ),
    );
  }

  Future<void> _event(MethodCall event) async {
    final data = Map<Object?, Object?>.from(event.arguments as Map);
    if (event.method == 'connected') {
      final link = _link(data);
      if (data['incoming'] == true) {
        final receiver = onIncoming;
        if (receiver == null) {
          link.close();
        } else {
          receiver(link);
        }
      }
    } else if (event.method == 'bytes') {
      _links[data['link']]?.receive(data['bytes'] as Uint8List);
    } else if (event.method == 'disconnected') {
      final token = data['link'] as String;
      _closedLinks.add(token);
      if (_closedLinks.length > 32) {
        _closedLinks.remove(_closedLinks.first);
      }
      _links[token]?.finish();
    }
  }

  Future<NearbySyncLink> connect(String peer) async {
    if (!_started) {
      throw const FormatException('Enable direct sync on both phones first.');
    }
    try {
      final raw = await channel.invokeMapMethod<Object?, Object?>('connect', {
        'peer': peer,
      });
      if (raw == null) {
        throw const FormatException('The nearby connection was cancelled.');
      }
      if (_closedLinks.contains(raw['link'])) {
        throw const FormatException(
          'The nearby connection closed before authentication. Retry sync safely.',
        );
      }
      return _link(raw);
    } on PlatformException catch (error) {
      throw FormatException(
        error.message ?? 'Could not connect to the other phone.',
      );
    }
  }

  Future<void> stop() async {
    _started = false;
    for (final link in _links.values.toList()) {
      link.finish();
    }
    try {
      await channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Local streams are already closed; no annotations are sent after stop.
    } on MissingPluginException {
      // Desktop and tests do not need a native Nearby implementation.
    }
    channel.setMethodCallHandler(null);
    _closedLinks.clear();
  }
}

class NearbySyncLink {
  NearbySyncLink._(this.token, this.peer, String binding, this._remove)
    : binding = 'nearby:$binding';
  final String token, peer, binding;
  final void Function() _remove;
  final _input = StreamController<Uint8List>();
  bool _closed = false;
  int _received = 0;
  late final wire = SyncWire.transport(
    _input.stream,
    write: _write,
    close: close,
    authorize: () async {
      await NearbySyncTransport.channel.invokeMethod<void>('authorize', {
        'link': token,
      });
    },
    binding: binding,
  );

  void receive(Uint8List bytes) {
    if (_closed) {
      return;
    }
    _received += bytes.length;
    if (bytes.isEmpty || bytes.length > 32000 || _received > 32 * 1024 * 1024) {
      close();
      return;
    }
    _input.add(bytes);
  }

  Future<void> _write(List<int> bytes) async {
    for (var offset = 0; offset < bytes.length; offset += 32000) {
      if (_closed) {
        throw const FormatException(
          'The nearby connection was closed. Retry sync safely.',
        );
      }
      final end = offset + 32000 < bytes.length ? offset + 32000 : bytes.length;
      try {
        await NearbySyncTransport.channel.invokeMethod<void>('send', {
          'link': token,
          'bytes': Uint8List.fromList(bytes.sublist(offset, end)),
        });
      } on PlatformException catch (error) {
        throw FormatException(
          error.message ??
              'The nearby transfer was interrupted. Retry sync safely.',
        );
      }
    }
  }

  void finish() {
    if (_closed) {
      return;
    }
    _closed = true;
    _remove();
    unawaited(_input.close());
  }

  void close() {
    if (_closed) {
      return;
    }
    finish();
    unawaited(
      NearbySyncTransport.channel
          .invokeMethod<void>('disconnect', {'link': token})
          .catchError((Object _) {}),
    );
  }
}
