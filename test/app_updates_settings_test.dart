import 'package:documentz/features/app_updates.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('documentz/updates');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Map<String, dynamic> state;
  late List<String> calls;
  setUp(() {
    state = {
      'version': '1.0.4',
      'automatic': false,
      'notifications': true,
      'available': null,
      'ready': false,
      'status': 'Check GitHub for a newer version.',
    };
    calls = [];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'automatic') {
        state['automatic'] = (call.arguments as Map)['enabled'];
      }
      if (call.method == 'check') {
        state['available'] = 'v1.0.5';
        state['status'] = 'v1.0.5 is available.';
      }
      if (call.method == 'download') {
        state['ready'] = true;
        state['status'] = 'Download verified. Ready to install.';
      }
      return state;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AppUpdatesSettings()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'update checks and downloads require an explicit user action by default',
    (tester) async {
      await open(tester);
      expect(calls, ['state']);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.tap(find.text('Check for updates'));
      await tester.pumpAndSettle();
      expect(find.text('Download v1.0.5'), findsOneWidget);
      expect(calls, isNot(contains('download')));
      await tester.tap(find.text('Download v1.0.5'));
      await tester.pumpAndSettle();
      expect(find.text('Install update'), findsOneWidget);
      expect(calls, isNot(contains('install')));
      await tester.tap(find.text('Install update'));
      await tester.pumpAndSettle();
      expect(calls, contains('install'));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'automatic checks can be enabled and disabled independently of downloads',
    (tester) async {
      await open(tester);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state['automatic'], isTrue);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(state['automatic'], isFalse);
      expect(calls, isNot(contains('download')));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('network errors show feedback and allow another check', (
    tester,
  ) async {
    await open(tester);
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'check') {
        throw PlatformException(
          code: 'updates',
          message: 'GitHub is unavailable. Try again.',
        );
      }
      return state;
    });
    await tester.tap(find.text('Check for updates'));
    await tester.pumpAndSettle();
    expect(find.text('GitHub is unavailable. Try again.'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'Check for updates'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
