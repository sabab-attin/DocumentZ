import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

const androidLanChannel = MethodChannel('documentz/lan_sync');

/// The native side selects a same-subnet Wi-Fi socket without changing the
/// process default network or bypassing an active VPN. All sync authentication
/// and encryption still runs on the ordinary SyncWire above this byte stream.
Future<Socket> connectAndroidLan(
  InternetAddress host,
  int port,
  Duration timeout,
) async {
  final clock = Stopwatch()..start();
  Map<Object?, Object?>? route;
  try {
    route = await androidLanChannel.invokeMapMethod<Object?, Object?>(
      'connect',
      {
        'host': host.address,
        'port': port,
        'timeoutMs': (timeout.inMilliseconds ~/ 2).clamp(100, 2000),
      },
    );
  } on MissingPluginException {
    // Compatibility with older Android builds that predate the route bridge.
  } on PlatformException {
    // Retain the system route if Android cannot open a network-specific socket.
  }
  if (route == null) {
    final remaining = timeout - clock.elapsed;
    if (remaining <= Duration.zero) {
      throw const SocketException('Local sync connection timed out.');
    }
    return Socket.connect(host, port, timeout: remaining);
  }
  final id = route['id'], proxyPort = route['port'];
  if (id is! String ||
      !RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
      proxyPort is! int ||
      proxyPort < 1 ||
      proxyPort > 65535) {
    throw const FormatException('Invalid local sync route.');
  }
  Socket? socket;
  try {
    socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      proxyPort,
      timeout: timeout,
    );
    socket.add(ascii.encode(id));
    await socket.flush();
    return socket;
  } catch (_) {
    socket?.destroy();
    try {
      await androidLanChannel.invokeMethod<void>('close', {'id': id});
    } catch (_) {}
    rethrow;
  }
}
