import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:documentz/data/local_library_web.dart';
import 'package:documentz/data/recent_documents.dart';
import 'package:documentz/features/edit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

void main() {
  testWidgets(
    'one Save action waits for public storage, keeps failed preview and retries',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      RecentDocuments.instance.resetForTests();
      final source = sf.PdfDocument();
      source.pages.add();
      final bytes = Uint8List.fromList(await source.save());
      source.dispose();
      final library = BrowserLibrary();
      var writes = 0, completed = 0;
      final pending = Completer<List<String>>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PdfResultScreen(
                      bytes: bytes,
                      name: 'Paper',
                      repository: library,
                      onSaved: () => completed++,
                      previewBuilder: (_) => const Text('PDF preview'),
                      outputWriter: (_) async {
                        if (++writes == 1) {
                          throw const FileSystemException('Disk full');
                        }
                        return pending.future;
                      },
                    ),
                  ),
                ),
                child: const Text('Edit'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Save copy to Library'), findsNothing);
      expect(find.byTooltip('Share PDF'), findsNothing);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('PDF preview'), findsOneWidget);
      expect(completed, 0);
      expect(RecentDocuments.instance.accessed, isEmpty);
      expect(
        find.text('Save failed. Check storage and permissions, then retry.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Save').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Saving…'), findsOneWidget);
      expect(completed, 0);
      pending.complete(['/downloads/DocumentZ/Paper.pdf']);
      await tester.pumpAndSettle();
      expect(completed, 1);
      expect(find.text('Edit'), findsOneWidget);
      expect(RecentDocuments.instance.accessed, hasLength(1));
      expect(await library.listBooks(), hasLength(1));
    },
  );
}
