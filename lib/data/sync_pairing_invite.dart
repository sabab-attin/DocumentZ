import 'dart:convert';

/// A short-lived invitation, never a persistent paired-device secret. It is
/// interpreted only by the sync screen, never opened as a web address.
class SyncPairingInvite {
  const SyncPairingInvite({
    required this.addresses,
    required this.code,
    this.nearbyId,
  });
  final List<String> addresses;
  final String code;
  final String? nearbyId;
  static const prefix = 'documentz-sync:1:';
  String encode() {
    final payload = base64UrlEncode(
      utf8.encode(
        jsonEncode({
          'addresses': addresses.take(8).toList(),
          'code': code,
          if (nearbyId != null) 'nearby': nearbyId,
        }),
      ),
    );
    return Uri(
      scheme: 'documentz',
      host: 'pair',
      fragment: 'v1=$payload',
    ).toString();
  }

  static SyncPairingInvite parse(String raw) {
    try {
      if (raw.length > 4096) throw const FormatException();
      final String encoded;
      if (raw.startsWith(prefix)) {
        encoded = raw.substring(prefix.length);
      } else {
        final uri = Uri.parse(raw);
        if (uri.scheme != 'documentz' ||
            uri.host != 'pair' ||
            uri.path.isNotEmpty ||
            uri.hasQuery ||
            uri.hasPort ||
            uri.userInfo.isNotEmpty ||
            !uri.fragment.startsWith('v1=')) {
          throw const FormatException('Not a DocumentZ pairing link.');
        }
        encoded = uri.fragment.substring(3);
      }
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      if (payload is! Map ||
          payload['code'] is! String ||
          payload['addresses'] is! List) {
        throw const FormatException();
      }
      final code = payload['code'] as String;
      if (!RegExp(r'^[A-Za-z0-9_-]{22}$').hasMatch(code) ||
          base64Url.decode(base64Url.normalize(code)).length != 16) {
        throw const FormatException();
      }
      final nearby = payload['nearby'];
      String? nearbyId;
      if (nearby != null) {
        if (nearby is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(nearby)) {
          throw const FormatException();
        }
        nearbyId = nearby;
      }
      final entries = payload['addresses'] as List;
      if ((entries.isEmpty && nearby == null) || entries.length > 8) {
        throw const FormatException();
      }
      final addresses = <String>[];
      for (final entry in entries) {
        if (entry is! String || !_localEndpoint(entry)) {
          throw const FormatException();
        }
        addresses.add(entry);
      }
      return SyncPairingInvite(
        addresses: addresses.toSet().toList(),
        code: code,
        nearbyId: nearbyId,
      );
    } catch (_) {
      throw const FormatException(
        'Invalid DocumentZ pairing QR. Use a fresh code from the other device.',
      );
    }
  }

  static bool _localEndpoint(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final port = int.tryParse(parts[1]);
    if (port == null || port < 1 || port > 65535) return false;
    final octets = parts[0].split('.');
    if (octets.length != 4) return false;
    final numbers = <int>[];
    for (final octet in octets) {
      if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(octet)) return false;
      final number = int.parse(octet);
      if (number > 255) return false;
      numbers.add(number);
    }
    return numbers[0] == 10 ||
        (numbers[0] == 172 && numbers[1] >= 16 && numbers[1] <= 31) ||
        (numbers[0] == 192 && numbers[1] == 168) ||
        (numbers[0] == 169 && numbers[1] == 254);
  }
}
