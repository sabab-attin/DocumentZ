import 'package:flutter/foundation.dart';

import '../domain/services.dart';
import 'local_sync_models.dart';

bool get localSyncAvailable => false;

class LocalAnnotationSync extends ChangeNotifier {
  LocalAnnotationSync(
    ImportableLibrary library, {
    required this.approve,
    SyncSecretStore? secrets,
    bool loopbackForTests = false,
  });
  SyncPairApproval approve;
  bool get enabled => false;
  bool get supportsNearby => false;
  bool get usesNearby => false;
  String? get nearbyPairingId => null;
  void setNearbyMode(bool value) {}
  Future<void> pairNearby(String peer, String code) async {}
  DateTime? get pairingExpiresAt => null;
  bool get busy => false;
  String get name => 'DocumentZ';
  String get status =>
      'Local sync is available in the installed Android and Windows apps.';
  String get verification => '';
  String? get pairingCode => null;
  List<String> get addresses => [];
  List<SyncPeer> get peers => [];
  List<NearbySyncDevice> get nearby => [];
  Future<void> initialize() async {}
  Future<void> start() async {}
  Future<void> stop() async {}
  void allowPairing() {}
  Future<void> rename(String value) async {}
  Future<void> forget(String peer) async {}
  Future<void> pair(String address, String code) async {}
  Future<void> pairAny(List<String> addresses, String code) async {}
  Future<void> syncWith(String peerId, {String? address}) async {}
}
