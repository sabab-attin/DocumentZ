import 'package:documentz/data/sync_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('storage lock finishes outside a widget test', () async {
    expect(await withSyncStorageLock(() async => 1), 1);
  });

  testWidgets('idle storage lock works inside the widget test clock', (
    tester,
  ) async {
    expect(await withSyncStorageLock(() async => 2), 2);
    expect(await withSyncStorageLock(() async => 3), 3);
  });

  test('storage lock releases after a failed operation', () async {
    await expectLater(
      withSyncStorageLock<void>(() async => throw StateError('test failure')),
      throwsStateError,
    );
    expect(await withSyncStorageLock(() async => 4), 4);
  });
}
