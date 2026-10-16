import 'dart:async';
import 'dart:io';

import 'sync_wire.dart';

// Prefer Wi-Fi/hotspot addresses over the private addresses assigned to VPNs
// and mobile data. All advertised addresses remain available as fallbacks.
int syncInterfacePriority(String name) {
  final value = name.toLowerCase();
  if (RegExp(r'^(wlan|wifi|wi-fi|ap\d|swlan|softap)').hasMatch(value)) {
    return 0;
  }
  if (RegExp(r'^(eth|en\d)').hasMatch(value)) {
    return 1;
  }
  if (RegExp(r'^(tun|tap|ppp|wg|utun|ipsec)').hasMatch(value)) {
    return 4;
  }
  if (RegExp(r'^(rmnet|ccmni|pdp|wwan)').hasMatch(value)) {
    return 3;
  }
  return 2;
}

({InternetAddress host, int port}) _endpoint(String raw) {
  final parts = raw.trim().split(':');
  final port = parts.length == 2 ? int.tryParse(parts[1]) : null;
  final host = InternetAddress.tryParse(parts.first);
  if (port == null ||
      port < 1 ||
      port > 65535 ||
      host == null ||
      !isSyncLocalAddress(host.address)) {
    throw const FormatException(
      'Enter a local IPv4 address and port, such as 192.168.1.20:45831.',
    );
  }
  return (host: host, port: port);
}

/// Only TCP reachability is retried. Once a socket is selected, authentication
/// failure stops the operation; an invalid invitation never bypasses approval.
Future<({Socket socket, String address})> connectSyncAddresses(
  List<String> candidates, {
  required List<String> localAddresses,
  required bool Function() active,
  void Function(int attempt, int total)? onAttempt,
  Duration timeout = const Duration(seconds: 4),
}) async {
  if (candidates.isEmpty || candidates.length > 8) {
    throw const FormatException(
      'A pairing invitation needs one to eight local addresses.',
    );
  }
  final endpoints = candidates
      .map((raw) {
        final value = _endpoint(raw);
        return (
          host: value.host,
          port: value.port,
          address: '${value.host.address}:${value.port}',
        );
      })
      .toSet()
      .toList();
  // A shared /24 is a preference, never an assumption about the real subnet.
  // NetworkInterface does not expose the subnet mask on every platform.
  final localPrefixes = localAddresses
      .map((raw) => raw.split(':').first)
      .map((host) => host.split('.').take(3).join('.'))
      .toSet();
  int score(InternetAddress host) =>
      localPrefixes.contains(host.address.split('.').take(3).join('.')) ? 0 : 1;
  // Keep invitation order for equal scores (including Wi-Fi before VPN).
  final ordered = endpoints.asMap().entries.toList()
    ..sort((a, b) {
      final rank = score(a.value.host).compareTo(score(b.value.host));
      return rank == 0 ? a.key.compareTo(b.key) : rank;
    });
  for (var index = 0; index < ordered.length; index++) {
    if (!active()) {
      throw const SocketException('Sync was stopped.');
    }
    final candidate = ordered[index].value;
    onAttempt?.call(index + 1, ordered.length);
    Socket socket;
    try {
      socket = await Socket.connect(
        candidate.host,
        candidate.port,
        timeout: timeout,
      );
    } on SocketException {
      continue;
    } on TimeoutException {
      continue;
    }
    if (!active()) {
      socket.destroy();
      throw const SocketException('Sync was stopped.');
    }
    return (socket: socket, address: candidate.address);
  }
  if (!active()) {
    throw const SocketException('Sync was stopped.');
  }
  throw const FormatException(
    'Could not reach the other device at any supplied address. Keep both apps open on the same Wi-Fi or phone hotspot. Allow local-network access in any VPN, or temporarily disconnect the VPN. Guest Wi-Fi may block devices from connecting; use a phone hotspot instead.',
  );
}
