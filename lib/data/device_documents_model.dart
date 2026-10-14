class DeviceDocument {
  const DeviceDocument({
    required this.location,
    required this.name,
    required this.folder,
    required this.size,
    required this.modified,
  });
  final String location, name, folder;
  final int size, modified;
  String get versionKey => '$location:$size:$modified';
}

class DeviceScan {
  const DeviceScan(this.documents, this.folders, this.errors);
  final List<DeviceDocument> documents;
  final List<String> folders, errors;
}
