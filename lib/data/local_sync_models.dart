typedef SyncPairApproval = Future<bool> Function(
  String name,
  String verification,
);

class SyncPeer {
  const SyncPeer(this.id, this.name, this.address, this.lastSync);
  final String id, name, address;
  final int lastSync;
}

class NearbySyncDevice {
  const NearbySyncDevice(this.id, this.name, this.address, this.seen);
  final String id, name, address;
  final DateTime seen;
}

abstract interface class SyncSecretStore {
  Future<String?> read();
  Future<void> write(String value);
}
