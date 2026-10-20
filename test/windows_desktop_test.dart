import 'package:documentz/app.dart';
import 'package:documentz/core/preferences.dart';
import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/data/external_documents.dart';
import 'package:documentz/features/app_updates.dart';
import 'package:documentz/features/device_library.dart';
import 'package:documentz/features/desktop_page_input.dart';
import 'package:documentz/features/page_turn.dart';
import 'package:documentz/features/reader_controls.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final windows = TargetPlatformVariant.only(TargetPlatform.windows);

  testWidgets(
    'Windows has Recent and Edit, native opening, and no mobile library or updater',
    (tester) async {
      final preferences = ReaderPreferences();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        ExternalDocuments.channel,
        (_) async => null,
      );
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(ExternalDocuments.channel, null),
      );
      await tester.pumpWidget(
        ReaderApp(preferences: preferences, repository: BrowserLibrary()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Library'), findsNothing);
      expect(find.byType(DeviceLibraryScreen), findsNothing);
      expect(find.text('Recent'), findsWidgets);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Open document'), findsOneWidget);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(AppUpdatesSettings), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    },
    variant: windows,
  );

  testWidgets(
    'desktop page keys and wheel work without taking text editing or menu input',
    (tester) async {
      final turns = <int>[];
      final menu = ValueNotifier(false);
      final field = FocusNode();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: ReaderControlsScope(
              expanded: menu,
              child: DesktopPageInput(
                onTurn: (direction) async => turns.add(direction),
                wheelPaging: true,
                child: Column(
                  children: [
                    TextField(focusNode: field),
                    const Expanded(child: SizedBox.expand()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(turns, [1, -1]);
      final area = tester.getCenter(find.byType(DesktopPageInput));
      tester.binding.handlePointerEvent(
        PointerScrollEvent(position: area, scrollDelta: const Offset(0, 80)),
      );
      await tester.pump();
      expect(turns, [1, -1, 1]);
      menu.value = true;
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(turns, hasLength(3));
      menu.value = false;
      field.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      expect(turns, hasLength(3));
      await tester.pumpWidget(const SizedBox.shrink());
      field.dispose();
      menu.dispose();
    },
    variant: windows,
  );

  testWidgets(
    'Windows turns animate the live page without allocating a GPU snapshot',
    (tester) async {
      final key = GlobalKey<PageTurnState>();
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 1600,
            height: 900,
            child: PageTurn(
              key: key,
              paper: Colors.white,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      var updates = 0;
      final turn = key.currentState!.turn(1, () => updates++);
      expect(updates, 1);
      expect(key.currentState!.busy, isTrue);
      await tester.pump(const Duration(milliseconds: 80));
      final moving = tester
          .widgetList<Transform>(find.byType(Transform))
          .any((widget) => widget.transform.getTranslation().x != 0);
      expect(moving, isTrue);
      await tester.pumpAndSettle();
      await turn;
      expect(key.currentState!.snapshot, isNull);
      expect(key.currentState!.busy, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    },
    variant: windows,
  );

  testWidgets(
    'Windows external document channel drains Unicode filenames with spaces',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final queue = <Map<String, dynamic>>[
        {
          'id': '1',
          'name': 'Research paper.pdf',
          'path': r'C:\Docs\Research paper.pdf',
        },
        {
          'id': '2',
          'name': '\u09ac\u0987.epub',
          'path': 'C:\\Docs\\\u09ac\u0987.epub',
        },
      ];
      final finished = <String>[];
      messenger.setMockMethodCallHandler(ExternalDocuments.channel, (
        call,
      ) async {
        if (call.method == 'takeDocument') {
          return queue.isEmpty ? null : queue.removeAt(0);
        }
        if (call.method == 'finishDocument') {
          finished.add((call.arguments as Map)['id'] as String);
        }
        return null;
      });
      var notifications = 0;
      await ExternalDocuments.start(() => notifications++);
      expect(notifications, 1);
      for (var i = 1; i <= 2; i++) {
        final document = await ExternalDocuments.take();
        expect(document!['id'], '$i');
        await ExternalDocuments.finish(document['id'] as String);
      }
      expect(await ExternalDocuments.take(), isNull);
      expect(finished, ['1', '2']);
      ExternalDocuments.stop();
      messenger.setMockMethodCallHandler(ExternalDocuments.channel, null);
    },
    variant: windows,
  );
}
