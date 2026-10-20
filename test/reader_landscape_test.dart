import 'package:documentz/core/preferences.dart';
import 'package:documentz/core/reader_platform.dart';
import 'package:documentz/domain/book.dart';
import 'package:documentz/features/reader.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('landscape is independent of page layout selection', (
    tester,
  ) async {
    final expanded = ValueNotifier<bool>(false);
    addTearDown(expanded.dispose);
    bool? requested;
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderControlsScope(
          expanded: expanded,
          onSetLandscape: (enabled) async {
            requested = enabled;
            return true;
          },
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  selected = await showReaderDisplayModes(
                    context,
                    selected: 'Single page',
                    modes: const ['Single page', 'Dual page', 'Continuous'],
                  );
                },
                child: const Text('Display'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Landscape'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(selected, isNull);
  });

  testWidgets(
    'landscape has permanent exit and menu controls and Back restores normal view',
    (tester) async {
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(ReaderPlatform.channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(ReaderPlatform.channel, null),
      );
      final preferences = ReaderPreferences(autoHideControls: false);
      addTearDown(preferences.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ReaderScreen(
            book: const Book(
              id: 'sample-landscape',
              title: 'Sample',
              format: BookFormat.pdf,
            ),
            preferences: preferences,
          ),
        ),
      );
      await tester.pumpAndSettle();
      var scope = tester.widget<ReaderControlsScope>(
        find.byType(ReaderControlsScope),
      );
      expect(await scope.onSetLandscape!(true), isTrue);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Exit landscape'), findsOneWidget);
      expect(find.byTooltip('Open reading menu'), findsOneWidget);
      scope = tester.widget<ReaderControlsScope>(
        find.byType(ReaderControlsScope),
      );
      scope.expanded.value = true;
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderControlsScope>(find.byType(ReaderControlsScope))
            .landscape,
        isTrue,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ReaderControlsScope>(find.byType(ReaderControlsScope))
            .landscape,
        isFalse,
      );
      expect(find.byType(ReaderScreen), findsOneWidget);
      expect(
        calls
            .where((c) => c.method == 'landscape')
            .map((c) => c.arguments['enabled']),
        [true, false],
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
