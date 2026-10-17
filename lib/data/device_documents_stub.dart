import 'device_documents_model.dart';
export 'device_documents_model.dart';

Future<bool> addDeviceFolder() async => false;
Future<void> removeDeviceFolder(String folder) async {}
bool get deviceDocumentIndexing => false;
Future<DeviceScan> scanDeviceDocuments({bool refresh = false}) async =>
    const DeviceScan([], [], [
      'Folder access is available in the installed Android and Windows apps.',
    ]);
Stream<List<int>> openDeviceDocument(DeviceDocument document) =>
    Stream.error(UnsupportedError('Use Add document in the browser.'));

Future<DeviceDocument> renameDeviceDocument(
  DeviceDocument document,
  String name,
) async => throw const FormatException(
  'Device files cannot be renamed in this browser.',
);
Future<void> deleteDeviceDocument(DeviceDocument document) async =>
    throw const FormatException(
      'Device files cannot be deleted in this browser.',
    );

bool get supportsDeviceStorageAccess => false;
Future<bool> hasDeviceStorageAccess() async => false;
Future<bool> requestDeviceStorageAccess() async => false;
