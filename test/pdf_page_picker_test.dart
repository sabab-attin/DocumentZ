import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:documentz/features/pdf_page_picker.dart';

class _PreviewPage implements PdfPage {
  _PreviewPage(this.pageNumber);
  @override
  final int pageNumber;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  dynamic noSuchMethod(Invocation invocation) => invocation.memberName == #render
    ? Future<PdfImage?>.value(null) : super.noSuchMethod(invocation);
}
class _PreviewDocument extends PdfDocument {
  _PreviewDocument(int count) : super(sourceName: 'preview-test') {
    pages = List.generate(count, (i) => _PreviewPage(i + 1));
  }
  @override
  late List<PdfPage> pages;
  @override
  Future<void> dispose() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('page picker previews all pages, jumps to typed page, and returns that page', (tester) async {
    List<int>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await Navigator.push<List<int>>(context, MaterialPageRoute(builder: (_) => PdfPagePicker(
        bytes: Uint8List(0), title: 'Choose page', documentLoader: () async => _PreviewDocument(400)))); },
      child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text(' / 400'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '300');
    await tester.tap(find.byTooltip('Jump to page'));
    await tester.pumpAndSettle();
    expect(find.text('Use page 300'), findsOneWidget);
    await tester.tap(find.text('Use page 300'));
    await tester.pumpAndSettle();
    expect(result, [299]);
  });
  testWidgets('rotation page picker supports selecting several thumbnails', (tester) async {
    List<int>? result;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await Navigator.push<List<int>>(context, MaterialPageRoute(builder: (_) => PdfPagePicker(
        bytes: Uint8List(0), title: 'Rotate', multiple: true, documentLoader: () async => _PreviewDocument(3)))); },
      child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    final checks = find.byType(Checkbox);
    await tester.tap(checks.at(1));
    await tester.tap(checks.at(3));
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Use selected pages'));
    await tester.pumpAndSettle();
    expect(result, [0, 2]);
  });
}
