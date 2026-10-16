import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:documentz/data/annotation_sync_session.dart';
import 'package:documentz/data/local_annotation_sync.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/domain/services.dart';

class _Secrets implements SyncSecretStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    value = next;
  }
}

class _Library implements ImportableLibrary {
  @override
  bool get persistsFiles => true;
  @override
  Future<List<Book>> listBooks() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('app session survives screen changes and repeated start; pairing lasts ten minutes', () async {
    SharedPreferences.setMockInitialValues({});
    final library = _Library();
    final engine = LocalAnnotationSync(
      library,
      secrets: _Secrets(),
      loopbackForTests: true,
      approve: (_, _) async => false,
    );
    final session = AnnotationSyncSession.withEngine(library, engine);
    try {
      await session.setEnabled(true);
      expect(engine.enabled, isTrue, reason: engine.status);
      final address = engine.addresses.single;
      expect(
        engine.pairingExpiresAt!.difference(DateTime.now()).inSeconds,
        inInclusiveRange(590, 600),
      );
      expect(
        identical(AnnotationSyncSession.forLibrary(library).engine, engine),
        isTrue,
      );
      // The screen relinquishes approval, without disposing the app service.
      engine.approve = (_, _) async => false;
      session.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(engine.enabled, isTrue);
      await engine.start();
      expect(engine.addresses.single, address);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AnnotationSyncSession.preferenceKey,
        ),
        isTrue,
      );
      await session.setEnabled(false);
      expect(engine.enabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AnnotationSyncSession.preferenceKey,
        ),
        isFalse,
      );
    } finally {
      await engine.stop();
      session.dispose();
    }
  });
}
