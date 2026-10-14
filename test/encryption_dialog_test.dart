import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:documentz/features/edit_fields_dialog.dart';

void main() {
  for (final submit in [true, false]) {
    testWidgets(
      submit ? 'password submit waits for the dialog to leave the tree' : 'password cancel preserves controllers through the closing animation',
      (tester) async {
        Map<String, String>? values;
        var completed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    values = await showEditFields(
                      context,
                      'Encrypt',
                      {'open': 'Opening password', 'owner': 'Owner password'},
                      secret: {'open', 'owner'},
                    );
                    completed = true;
                  },
                  child: const Text('Encrypt PDF'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Encrypt PDF'));
        await tester.pumpAndSettle();
        final fields = find.byType(TextField);
        await tester.enterText(fields.at(0), 'open-password');
        await tester.enterText(fields.at(1), 'owner-password');
        await tester.tap(find.text(submit ? 'Continue' : 'Cancel'));
        // The result must not start the next operation during the closing frame.
        await tester.pump(const Duration(milliseconds: 10));
        expect(completed, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(completed, isTrue);
        expect(
          values,
          submit
              ? {'open': 'open-password', 'owner': 'owner-password'}
              : isNull,
        );
        expect(find.byType(TextField), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Encrypt PDF'));
        await tester.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(2));
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets('invalid passwords stay in the dialog and allow correction', (
    tester,
  ) async {
    Map<String, String>? values;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                values = await showEditFields(
                  context,
                  'Encrypt',
                  {'open': 'Opening password', 'owner': 'Owner password'},
                  secret: {'open', 'owner'},
                );
              },
              child: const Text('Encrypt PDF'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Encrypt PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('Use different, nonempty opening and owner passwords.'),
      findsOneWidget,
    );
    expect(values, isNull);
    await tester.enterText(find.byType(TextField).at(0), 'same');
    await tester.enterText(find.byType(TextField).at(1), 'same');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(values, isNull);
    await tester.enterText(find.byType(TextField).at(1), 'different');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(values?['owner'], 'different');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
