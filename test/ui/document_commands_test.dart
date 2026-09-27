import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mdviewer/app.dart';
import 'package:mdviewer/platform/file_saving.dart';

import '../support/test_app.dart';

// Harnesses are created inside each testWidgets body (not setUp).
void main() {
  final pdf = Uint8List.fromList(utf8.encode('%PDF-1.7 fake'));

  Future<TestHarness> pumpWithDocument(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    TestHarness? harness,
  }) async {
    final h = harness ?? await createHarness();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MdViewerApp(services: h.services));
    h.access.nextFolder = h.folderRequest();
    await h.services.actions.pickFolder();
    await tester.pumpAndSettle();
    return h;
  }

  testWidgets('Save as PDF asks for a location and writes the renderer PDF there', (tester) async {
    final h = await pumpWithDocument(tester);
    h.renderer.pdfBytes = pdf;
    h.saveLocation = '/out/README.pdf';

    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();

    expect(h.saveSuggestions, ['README.pdf']);
    expect(h.writtenFiles['/out/README.pdf'], pdf);
    expect(find.text('Saved README.pdf'), findsOneWidget);
  });

  testWidgets('Save as PDF does nothing when the user cancels', (tester) async {
    final h = await pumpWithDocument(tester);
    h.renderer.pdfBytes = pdf;
    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();
    expect(h.saveSuggestions, hasLength(1));
    expect(h.writtenFiles, isEmpty);
    expect(h.renderer.calls, isNot(contains('createPdf')));
  });

  testWidgets('Save as PDF reports a failed conversion', (tester) async {
    final h = await pumpWithDocument(tester);
    h.saveLocation = '/out/README.pdf';
    await tester.tap(find.byKey(const Key('action-save-pdf')));
    await tester.pumpAndSettle();
    expect(h.writtenFiles, isEmpty);
    expect(find.textContaining('Could not save PDF'), findsOneWidget);
  });

  testWidgets('Save as PDF is hidden where the renderer cannot create PDFs', (tester) async {
    final harness = await createHarness();
    harness.renderer.savePdfSupported = false;
    await pumpWithDocument(tester, harness: harness);
    expect(find.byKey(const Key('action-save-pdf')), findsNothing);
    await tester.tap(find.byKey(const Key('action-more')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('menu-save-pdf')), findsNothing);
  });

  test('the default writer writes the bytes to the chosen path', () async {
    final dir = await Directory.systemTemp.createTemp('mdv_pdf');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/out.pdf';
    await writeFileBytes(path, pdf);
    expect(await File(path).readAsBytes(), pdf);
  });

  testWidgets('Share hands the Markdown file to the sharer, anchored at the button', (tester) async {
    final harness = await createHarness();
    harness.sharer.isSupported = true;
    final h = await pumpWithDocument(tester, size: const Size(390, 844), harness: harness);

    final button = find.byKey(const Key('action-share'));
    expect(button, findsOneWidget, reason: 'share stays in the title bar on phones');
    await tester.tap(button);
    await tester.pumpAndSettle();

    final shared = h.sharer.shared.single;
    expect(utf8.decode(shared.bytes), '# Readme\n\nSee [guide](guide.md).');
    expect(shared.name, 'README.md');
    expect(shared.mimeType, 'text/markdown');
    expect(shared.origin, tester.getRect(button));
  });

  testWidgets('Share is hidden where sharing is not supported (desktop)', (tester) async {
    await pumpWithDocument(tester);
    expect(find.byKey(const Key('action-share')), findsNothing);
  });

  testWidgets('Share errors are reported', (tester) async {
    final harness = await createHarness();
    harness.sharer
      ..isSupported = true
      ..error = Exception('boom');
    await pumpWithDocument(tester, size: const Size(390, 844), harness: harness);
    await tester.tap(find.byKey(const Key('action-share')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not share'), findsOneWidget);
  });
}
